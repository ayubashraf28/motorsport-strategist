# ADR 0002: V1 Pace Profile and Smooth Boundary Transitions

## Status

Accepted

## Context

V0 used constant per-car speed around the lap, which produced deterministic timing but unrealistic motion.

V1 needs:
- section-based speed variation
- smooth transitions (no abrupt speed snapping)
- deterministic, testable behavior
- config-driven tuning without code changes

## Decision

1. Introduce `config/race_v1.json` as the authoritative runtime config.
2. Model track pace as contiguous lap segments with multipliers.
3. Use `base_speed_units_per_sec` per car and compute:
- `effective_speed = base_speed_units_per_sec * sampled_multiplier`
4. Apply smoothing in a centered boundary blend window using smoothstep.
5. Enforce runtime validation:
- contiguous full-lap segment coverage
- positive multipliers
- last segment ends at track length
- segment length >= blend distance
6. Add debug visuals:
- visible start/finish marker
- color-coded pace profile overlay
- blend-window markers

## Alternatives considered

### Instant multiplier switching at boundaries

Pros:
- simpler implementation

Cons:
- visible speed snapping
- harder to tune naturally

### Physics-based cornering model

Pros:
- potentially more realistic speed curves

Cons:
- significantly higher complexity for this stage
- weaker determinism unless heavily constrained

## Consequences

- V1 improves visual realism while preserving deterministic simulation.
- Pace tuning is fully data-driven through config.
- Validation becomes stricter but prevents silent misconfiguration.
