# Racing Manager Prototype v1 Architecture

## Goal

Extend the v0 deterministic lap-timing prototype with data-driven pace variation so cars:
- accelerate on straights
- decelerate in corners
- transition smoothly without multiplier snapping

## Core boundary

### Simulation (`game/sim/src`)

Authoritative logic:
- pace profile validation and sampling
- car effective speed computation (`base_speed_units_per_sec * multiplier`)
- deterministic chunk integration
- lap crossing and timing updates

### Presentation (`game/scripts`, `game/scenes`, `game/ui`)

Responsibilities:
- load `config/race_v1.json`
- provide track length runtime parameter from baked curve
- render dots and timing HUD
- render start/finish marker
- render pace debug overlay (color-coded segments + blend markers)

## Data flow

1. Controller loads config from `config/race_v1.json`.
2. Track sampler bakes curve and computes total lap length.
3. Simulator initializes with:
- car base speeds
- track pace profile config
- runtime track length
4. Pace profile validates segment coverage and blend constraints.
5. Runtime loop:
- fixed-step runner drives `sim.step(fixed_dt)`
- simulator internally chunks movement at `1/120` for deterministic integration
- controller maps distance to world position and updates HUD/debug visuals

## Pace profile rules

Representation:
- segments partition lap distance (`start_distance`, `end_distance`, `multiplier`)
- profile loops at lap end

Smoothing:
- each boundary has centered blend window (`blend_distance`)
- blend function is smoothstep: `t*t*(3 - 2*t)`
- result is continuous, deterministic, and bounded between adjacent segment multipliers

## Determinism notes

- fixed-step loop remains authoritative for frame-to-sim progression
- simulator chunk integration protects high-speed/high-dt cases
- profile sampling is pure and deterministic for identical inputs

## Failure handling

Invalid profile/config examples:
- gaps or overlaps
- non-positive multipliers
- last segment not ending at track length
- segment shorter than blend distance

Behavior:
- simulator does not start
- HUD shows explicit validation errors
