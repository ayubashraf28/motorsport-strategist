# ADR 0001: v0 Godot Root and Simulation Placement

## Status

Accepted

## Context

The repository has a conceptual top-level `sim/` domain for deterministic simulation, while Godot runtime and testing require scripts to exist under the active Godot project root.

For v0, we need:
- quick runnable prototype in Godot
- deterministic tests in CI
- clear separation between simulation and presentation

## Decision

1. Keep `project.godot` under `game/` (project root is `game/`, not repo root).
2. Place authoritative v0 simulation code in `game/sim/src` with no scene/UI dependencies.
3. Keep repository-level `sim/` as architecture ownership boundary and future extraction target.
4. Run simulation tests in headless Godot using GdUnit4 from `game/sim/tests`.

## Alternatives considered

### Repo root as Godot project root

Pros:
- direct `res://sim` access from repo root

Cons:
- editor indexes docs/tools/config and creates ongoing noise
- broader import surface than needed

### Separate C# or external package for simulation

Pros:
- strongest technical decoupling

Cons:
- additional toolchain complexity for v0
- slower iteration

## Consequences

- v0 ships quickly with deterministic tests and strong boundaries.
- path migration is still needed to move runtime simulation into repo-level `sim/` later.
- extraction plan is explicit: keep interfaces stable (`RaceConfig`, `RaceRuntimeParams`, `RaceSnapshot`, `RaceSimulator`) so relocation is mechanical.

