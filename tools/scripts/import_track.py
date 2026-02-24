#!/usr/bin/env python3
"""Convert a racetrack CSV centerline to the V1.1 JSON geometry asset format.

Expected CSV columns:
    x_m,y_m,w_tr_right_m,w_tr_left_m
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import List, Sequence, Tuple

Point = Tuple[float, float]


def _distance(a: Point, b: Point) -> float:
    return math.hypot(b[0] - a[0], b[1] - a[1])


def _lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def _load_points(path: Path) -> List[Point]:
    points: List[Point] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        clean_lines: List[str] = []
        for line in handle:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                clean_lines.append(stripped.lstrip("#").strip() + "\n")
                continue
            clean_lines.append(line)
        reader = csv.DictReader(clean_lines)
        for row in reader:
            points.append((float(row["x_m"]), float(row["y_m"])))
    if len(points) < 3:
        raise ValueError("CSV must contain at least 3 centerline points.")
    return points


def _center_points(points: Sequence[Point]) -> List[Point]:
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    return [(p[0] - cx, p[1] - cy) for p in points]


def _close_loop(points: Sequence[Point]) -> List[Point]:
    loop = list(points)
    if _distance(loop[0], loop[-1]) > 1e-6:
        loop.append(loop[0])
    return loop


def _apply_transform(
    points: Sequence[Point], scale: float, flip_y: bool
) -> List[Point]:
    out: List[Point] = []
    for x, y in points:
        y_out = -y if flip_y else y
        out.append((x * scale, y_out * scale))
    return out


def _polyline_length(points: Sequence[Point]) -> float:
    return sum(_distance(points[i - 1], points[i]) for i in range(1, len(points)))


def _sample_polyline_closed(points_closed: Sequence[Point], step: float) -> Tuple[List[Point], float]:
    """Sample a closed polyline at uniform arc-length spacing.

    Returns samples without duplicating the endpoint. The loop closure is implicit.
    """
    total_length = _polyline_length(points_closed)
    if total_length <= 0.0:
        raise ValueError("Track length must be positive after transforms.")
    if step <= 0.0:
        raise ValueError("Sample interval must be > 0.")

    sample_count = max(3, int(round(total_length / step)))
    ds = total_length / float(sample_count)

    # Build cumulative arc lengths over the closed polyline.
    cumulative: List[float] = [0.0]
    for i in range(1, len(points_closed)):
        cumulative.append(cumulative[-1] + _distance(points_closed[i - 1], points_closed[i]))

    samples: List[Point] = []
    seg_index = 1
    for i in range(sample_count):
        target = ds * float(i)
        while seg_index < len(cumulative) - 1 and cumulative[seg_index] < target:
            seg_index += 1
        d0 = cumulative[seg_index - 1]
        d1 = cumulative[seg_index]
        p0 = points_closed[seg_index - 1]
        p1 = points_closed[seg_index]
        if d1 - d0 <= 1e-9:
            samples.append(p1)
            continue
        t = (target - d0) / (d1 - d0)
        samples.append(_lerp(p0, p1, t))
    return samples, ds


def _signed_curvature(prev_p: Point, curr_p: Point, next_p: Point) -> float:
    """Compute signed curvature with a three-point formula."""
    ax = curr_p[0] - prev_p[0]
    ay = curr_p[1] - prev_p[1]
    bx = next_p[0] - curr_p[0]
    by = next_p[1] - curr_p[1]
    cx = next_p[0] - prev_p[0]
    cy = next_p[1] - prev_p[1]

    a = math.hypot(ax, ay)
    b = math.hypot(bx, by)
    c = math.hypot(cx, cy)
    denom = a * b * c
    if denom <= 1e-12:
        return 0.0

    area2 = ax * cy - ay * cx
    return (2.0 * area2) / denom


def _compute_curvatures(samples: Sequence[Point]) -> List[float]:
    n = len(samples)
    curvatures: List[float] = [0.0] * n
    for i in range(n):
        curvatures[i] = _signed_curvature(
            samples[(i - 1) % n],
            samples[i],
            samples[(i + 1) % n],
        )
    return curvatures


def _build_payload(
    samples: Sequence[Point],
    curvatures: Sequence[float],
    sample_interval: float,
    source: str,
) -> dict:
    sample_count = len(samples)
    track_length = 0.0
    for i in range(sample_count):
        track_length += _distance(samples[i], samples[(i + 1) % sample_count])
    effective_interval = track_length / float(sample_count)
    return {
        "source": source,
        "import_script_version": "1.0",
        "sample_interval_units": effective_interval,
        "track_length_units": track_length,
        "sample_count": sample_count,
        "samples": [
            {"x": samples[i][0], "y": samples[i][1], "kappa": curvatures[i]}
            for i in range(sample_count)
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert racetrack CSV centerline into V1.1 geometry JSON."
    )
    parser.add_argument("--input-csv", required=True, help="Path to source centerline CSV.")
    parser.add_argument("--output-json", required=True, help="Path for output JSON asset.")
    parser.add_argument(
        "--sample-interval",
        type=float,
        default=4.0,
        help="Uniform sample spacing in game units after scaling.",
    )
    parser.add_argument(
        "--scale",
        type=float,
        default=0.35,
        help="Import-time scale factor from source units to game units.",
    )
    parser.add_argument(
        "--flip-y",
        action="store_true",
        default=True,
        help="Flip Y axis for Godot's Y-down convention (default on).",
    )
    parser.add_argument(
        "--no-flip-y",
        dest="flip_y",
        action="store_false",
        help="Disable Y-axis flip.",
    )
    parser.add_argument(
        "--source-label",
        default="TUMFTM/racetrack-database, Monza.csv, LGPL-3.0",
        help="Source attribution string stored in the JSON output.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.sample_interval <= 0.0:
        raise ValueError("--sample-interval must be > 0.")
    if args.scale <= 0.0:
        raise ValueError("--scale must be > 0.")

    input_path = Path(args.input_csv)
    output_path = Path(args.output_json)
    points = _load_points(input_path)
    points = _center_points(points)
    points = _apply_transform(points, args.scale, args.flip_y)
    points_closed = _close_loop(points)

    samples, actual_ds = _sample_polyline_closed(points_closed, args.sample_interval)
    curvatures = _compute_curvatures(samples)
    payload = _build_payload(
        samples=samples,
        curvatures=curvatures,
        sample_interval=actual_ds,
        source=args.source_label,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
