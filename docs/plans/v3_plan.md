# V3 Implementation Plan — Pit Stops, Tyre Strategy & Fuel

## Context

V2 shipped live standings, race end conditions, tyre degradation, and overtaking logic. Cars now
degrade over a race stint but have no way to recover performance, and fuel has no effect on pace.
In a real Motorsport Manager game, the core gameplay loop is **pit stop strategy** — deciding
*when* to pit, *which compound* to fit, and *how much fuel* to carry.

V3 adds three interconnected systems:
1. **Tyre compounds & stint tracking** — different tyre types with unique degradation curves
2. **Pit stops** — with realistic entry/exit distances on the track, not a simple time penalty
3. **Fuel model** — weight-based speed penalty that makes cars faster as fuel burns off

After V3, the player can observe degradation and fuel state, call a pit stop at the right moment,
choose tyres and refuel, and rejoin — creating the first real strategic decision loop.

**Design north star**: The existing `DegradationModel` is stateless and takes `(lap_count, fractional_lap, config)`.
V3 introduces a **stint-based** degradation model where each pit stop resets the car's tyre age
(stint lap count) and swaps the `DegradationConfig` to match the new compound. The model itself
stays stateless — only the inputs change. Fuel is a separate multiplier applied alongside degradation.

---

## Implementation Order and Dependencies

```
Feature 1: Tyre Compounds                <- implement first (no dependencies)
        |
        v
Feature 2: Stint Tracking                <- needs F1 (compound defines degradation curve)
        |
        v
Feature 3: Fuel Model                    <- independent of F1/F2 but implements in parallel
        |
        v
Feature 4: Pit Stop Execution            <- needs F2, F3 (pit stop resets stint, refuels)
        |
        v
Feature 5: Pit Strategy Queue            <- needs F4 (player issues "pit next lap" command)
        |
        v
Feature 6: HUD Updates                   <- needs F1-F5 (display compound, fuel, stint, pit status)
```

Each feature ships as its own commit on a single branch `feat/v3-pit-strategy` and is PR'd into `main`.

---

## Current State (What Exists and What We Build On)

| What | Status | File |
|---|---|---|
| `DegradationConfig` | Has warmup/peak/degradation_rate/min_multiplier | `game/sim/src/race_types.gd` |
| `DegradationModel.compute_multiplier()` | Stateless, takes lap_count + fractional_lap | `game/sim/src/degradation_model.gd` |
| `CarState.degradation_multiplier` | Updated every chunk in `_compute_car_speed` | `game/sim/src/race_simulator.gd` |
| `_car_degradation_configs` dict | Maps car.id -> DegradationConfig (resolved at init) | `game/sim/src/race_simulator.gd` |
| Per-car degradation override | `CarConfig.degradation` field, fallback to global | `game/sim/src/race_types.gd` |
| HUD Deg column | Shows `degradation_multiplier` as percentage | `game/ui/race_hud.gd` |
| `_register_lap_crossing()` | Detects finish-line crossing, calls state machine | `game/sim/src/race_simulator.gd` |
| Config loader V2 branch | Parses degradation + overtaking | `game/scripts/race_config_loader.gd` |
| Track data (Monza) | Centerline + curvature, no pit lane geometry | `data/tracks/monza/monza_centerline.json` |
| Track length (Monza) | ~2025.5 game units | `data/tracks/monza/monza_centerline.json` |

---

## File Inventory

### New Files

| File | Feature | Purpose |
|---|---|---|
| `game/sim/src/tyre_compound.gd` | F1 | Compound definitions (soft/medium/hard) with degradation curves |
| `game/sim/src/stint_tracker.gd` | F2 | Per-car stint state: current compound, stint lap count, pit history |
| `game/sim/src/fuel_model.gd` | F3 | Fuel load, consumption, weight-based speed penalty |
| `game/sim/src/pit_stop_manager.gd` | F4 | Pit lane execution: entry/exit at track distances, stop duration |
| `game/sim/src/pit_strategy.gd` | F5 | Command queue: accept "pit next lap" orders, resolve compound + fuel |
| `game/sim/tests/tyre_compound_test.gd` | F1 | |
| `game/sim/tests/stint_tracker_test.gd` | F2 | |
| `game/sim/tests/fuel_model_test.gd` | F3 | |
| `game/sim/tests/pit_stop_manager_test.gd` | F4 | |
| `game/sim/tests/pit_strategy_test.gd` | F5 | |
| `config/race_v3.json` | All | V3 config with compounds, fuel, pit config |

### Modified Files

| File | Features | What Changes |
|---|---|---|
| `game/sim/src/race_types.gd` | All | New types: TyreCompoundConfig, FuelConfig, PitConfig, CompletedStint; new fields on CarState, CarConfig, RaceConfig |
| `game/sim/src/race_simulator.gd` | F2-F5 | Integrate stint tracker, fuel model, pit stop manager; modify speed computation |
| `game/sim/src/degradation_model.gd` | — | **No changes** — stays stateless. Stint tracker feeds it different inputs. |
| `game/sim/src/overtaking_manager.gd` | F4 | Skip cars with `is_in_pit == true` in `process_interactions()` |
| `game/scripts/race_config_loader.gd` | F1, F3, F4 | Schema 3.0 parse branch; compound + fuel + pit config parsing |
| `game/scripts/race_controller.gd` | F5 | Accept pit commands; pass commands to simulator |
| `game/ui/race_hud.gd` | F6 | New columns: Compound, Fuel, Stint; pit status indicator; pit button per car |
| `game/ui/race_hud.tscn` | F6 | GridContainer column count update |
| `game/sim/tests/race_simulator_test.gd` | F2-F4 | V3 integration tests |

### Untouched

`pace_profile.gd`, `speed_profile.gd`, `track_geometry.gd`, `fixed_step_runner.gd`,
`standings_calculator.gd`, `race_state_machine.gd`, `track_sampler.gd`, `track_loader.gd`,
`car_dot.gd`, all debug overlays,
`config/race_v0.json`, `config/race_v1.json`, `config/race_v1.1.json`, `config/race_v2.json`.

---

## Feature 1: Tyre Compounds

### Concept

A tyre compound is a named degradation profile. Each compound has its own `DegradationConfig`
that controls warmup, peak performance, degradation rate, and floor. Typical compounds:

| Compound | Peak Speed | Degradation Rate | Character |
|---|---|---|---|
| Soft | Fastest (peak_multiplier ~1.05) | Highest (degrades quickly) | Sprint weapon |
| Medium | Baseline (peak_multiplier ~1.0) | Medium | Balanced |
| Hard | Slowest (peak_multiplier ~0.95) | Lowest (lasts longest) | Endurance pick |

The existing `DegradationModel.compute_multiplier()` already handles the math. Compounds
simply define different config values fed into that same function.

### New Types (`race_types.gd`)

```gdscript
class TyreCompoundConfig extends RefCounted:
    var name: String = "medium"              # "soft", "medium", "hard" (or custom names)
    var degradation: DegradationConfig = DegradationConfig.new()

    func clone() -> TyreCompoundConfig:
        var copied := TyreCompoundConfig.new()
        copied.name = name
        copied.degradation = degradation.clone() if degradation != null else DegradationConfig.new()
        return copied
```

Add to `RaceConfig`:

```gdscript
var compounds: Array[TyreCompoundConfig] = []  # available compounds for this race
```

### New Module: `game/sim/src/tyre_compound.gd`

```gdscript
class_name TyreCompound extends RefCounted

static func find_compound(
    compounds: Array[RaceTypes.TyreCompoundConfig],
    compound_name: String
) -> RaceTypes.TyreCompoundConfig
    # Returns the matching compound, or null if not found

static func get_default_compound_name(compounds: Array[RaceTypes.TyreCompoundConfig]) -> String
    # Returns the name of the first compound (used as fallback)
    # Returns "medium" if compounds array is empty

static func validate_compounds(compounds: Array[RaceTypes.TyreCompoundConfig]) -> PackedStringArray
    # Checks: at least 1 compound defined, no duplicate names, each has valid degradation
```

### Config Format

```json
{
  "compounds": [
    {
      "name": "soft",
      "degradation": {
        "warmup_laps": 0.3,
        "peak_multiplier": 1.05,
        "degradation_rate": 0.04,
        "min_multiplier": 0.70
      }
    },
    {
      "name": "medium",
      "degradation": {
        "warmup_laps": 0.5,
        "peak_multiplier": 1.0,
        "degradation_rate": 0.02,
        "min_multiplier": 0.75
      }
    },
    {
      "name": "hard",
      "degradation": {
        "warmup_laps": 0.8,
        "peak_multiplier": 0.95,
        "degradation_rate": 0.01,
        "min_multiplier": 0.80
      }
    }
  ]
}
```

### Backward Compatibility

If `compounds` is absent or empty (V2 configs), the system falls back to the existing
`degradation` field on `RaceConfig` / `CarConfig`. V2 configs work with zero changes.
When compounds ARE defined, the per-car `degradation` field is ignored — compound-based
degradation via stint tracking takes over.

### Tests (`tyre_compound_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_find_compound_by_name` | Returns correct compound for "soft", "medium", "hard" |
| `test_find_compound_returns_null_for_unknown` | Unknown name returns null |
| `test_default_compound_is_first_in_array` | First compound is the default |
| `test_empty_compounds_default_is_medium` | Fallback when no compounds defined |
| `test_validate_rejects_duplicate_names` | Two compounds named "soft" -> error |
| `test_validate_rejects_empty_array` | Requires at least 1 compound |
| `test_validate_delegates_to_degradation_model` | Invalid degradation values caught |
| `test_compound_clone_is_deep` | Mutating clone doesn't affect original |

### Guardrails

- **DO NOT create a new degradation math model.** Compounds are config wrappers around
  the existing `DegradationModel.compute_multiplier()`. No new physics.
- **DO NOT hardcode compound names.** "soft"/"medium"/"hard" are config-driven strings,
  not an enum. This allows future custom compounds (e.g., "intermediate", "wet").
- **DO NOT store compound state in TyreCompound.** It's a static utility class.
  Runtime state lives in StintTracker (Feature 2).

---

## Feature 2: Stint Tracking

### Concept

A "stint" is the period between pit stops. When a car starts the race on soft tyres, that's
stint 1. After a pit stop onto mediums, that's stint 2. The stint tracker manages:

- **Current compound name** (which tyre is fitted)
- **Stint lap count** (laps since last pit stop — used as `lap_count` input to DegradationModel)
- **Stint fractional progress** (distance within current stint lap)
- **Pit history** (array of completed stints for race review)

### New Types (`race_types.gd`)

Add to `CarState`:

```gdscript
var current_compound: String = "medium"      # name of fitted compound
var stint_lap_count: int = 0                 # laps completed on current tyres
var stint_number: int = 1                    # which stint (1 = first, 2 = after 1st stop, etc.)
var is_in_pit: bool = false                  # currently in pit lane
var pit_phase: int = 0                       # 0=racing, 1=entering, 2=stopped, 3=exiting
```

Add to `CarConfig`:

```gdscript
var starting_compound: String = ""           # compound name for race start (empty = use first compound)
```

Add a completed stint record type:

```gdscript
class CompletedStint extends RefCounted:
    var compound_name: String = ""
    var laps: int = 0
    var stint_number: int = 0

    func clone() -> CompletedStint:
        var copied := CompletedStint.new()
        copied.compound_name = compound_name
        copied.laps = laps
        copied.stint_number = stint_number
        return copied
```

### New Module: `game/sim/src/stint_tracker.gd`

```gdscript
class_name StintTracker extends RefCounted

var _car_stints: Dictionary = {}       # car_id -> { compound_name, stint_lap_count, stint_number, history }
var _compounds: Array[RaceTypes.TyreCompoundConfig] = []

func configure(
    cars: Array[RaceTypes.CarState],
    compounds: Array[RaceTypes.TyreCompoundConfig],
    starting_compounds: Dictionary    # car_id -> compound_name (from config)
) -> void

func reset() -> void

func get_compound_name(car_id: String) -> String
func get_stint_lap_count(car_id: String) -> int
func get_stint_number(car_id: String) -> int
func get_degradation_config(car_id: String) -> RaceTypes.DegradationConfig
    # Returns the DegradationConfig from the car's current compound
    # This is what gets fed to DegradationModel.compute_multiplier()

func on_lap_completed(car_id: String) -> void
    # Increment stint_lap_count for this car

func on_pit_stop_complete(car_id: String, new_compound_name: String) -> void
    # Record completed stint in history
    # Reset stint_lap_count to 0
    # Set new compound
    # Increment stint_number
```

### Simulator Integration

In `race_simulator.gd`, modify `_compute_car_speed()`:

**Current** (V2):
```gdscript
var deg_config = _car_degradation_configs.get(car.id, null)
var fractional_lap = car.distance_along_track / _runtime.track_length
car.degradation_multiplier = DegradationModel.compute_multiplier(car.lap_count, fractional_lap, deg_config)
```

**New** (V3 — when compounds are active):
```gdscript
var deg_config = _stint_tracker.get_degradation_config(car.id)
var stint_lap_count = _stint_tracker.get_stint_lap_count(car.id)
var fractional_lap = car.distance_along_track / _runtime.track_length
car.degradation_multiplier = DegradationModel.compute_multiplier(stint_lap_count, fractional_lap, deg_config)
car.current_compound = _stint_tracker.get_compound_name(car.id)
car.stint_lap_count = stint_lap_count
car.stint_number = _stint_tracker.get_stint_number(car.id)
```

**Key change**: `lap_count` (total race laps) is replaced by `stint_lap_count` (laps on current
tyres). This makes degradation reset on each pit stop without any change to `DegradationModel`.

In `_register_lap_crossing()`, after incrementing `car.lap_count`:
```gdscript
if _stint_tracker != null:
    _stint_tracker.on_lap_completed(car.id)
```

### Backward Compatibility

When `compounds` is empty (V2 configs), `_stint_tracker` is null. The existing
`_car_degradation_configs` path is used unchanged. When compounds are defined,
`_car_degradation_configs` is not populated — the stint tracker owns degradation resolution.

### Tests (`stint_tracker_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_initial_compound_matches_config` | Car starts on specified compound |
| `test_default_compound_when_not_specified` | Uses first compound if car has no starting compound |
| `test_stint_lap_increments_on_lap_complete` | Calling on_lap_completed increases stint_lap_count |
| `test_pit_stop_resets_stint_laps` | After on_pit_stop_complete, stint_lap_count is 0 |
| `test_pit_stop_changes_compound` | Compound name changes after pit |
| `test_pit_stop_increments_stint_number` | stint_number goes from 1 to 2 |
| `test_degradation_config_matches_compound` | get_degradation_config returns compound's config |
| `test_pit_stop_records_history` | Completed stint appears in history |
| `test_multiple_pit_stops` | 3 stints work correctly |
| `test_unknown_compound_on_pit_falls_back` | Invalid compound name falls back to first compound |
| `test_reset_clears_all_state` | After reset, everything back to initial |

### Guardrails

- **DO NOT modify `DegradationModel`.** It stays stateless. Only the inputs change.
- **DO NOT store the DegradationConfig on CarState.** CarState holds the multiplier result.
  The config lives in StintTracker.
- **DO NOT use total `lap_count` for degradation when compounds are active.** Use `stint_lap_count`.
- **DO NOT forget to call `on_lap_completed` on the stint tracker** in `_register_lap_crossing`.

---

## Feature 3: Fuel Model

### Concept

Cars carry fuel that burns during the race. Heavier fuel loads make the car slower.
As fuel burns off, the car gets progressively lighter and faster. This creates a natural
strategic tension: start with more fuel (fewer pit stops but slower) or less fuel (faster
but must pit sooner).

### The Physics

```
fuel_weight_multiplier = 1.0 - (current_fuel_kg / max_fuel_capacity_kg) * weight_penalty_factor

where:
  current_fuel_kg     = fuel remaining (decreases each lap)
  max_fuel_capacity_kg = maximum fuel the car can carry
  weight_penalty_factor = how much a full tank slows the car (e.g., 0.05 = 5% slower at full tank)
```

Example with `weight_penalty_factor = 0.05`:
- Full tank (100 kg): multiplier = `1.0 - (100/100) * 0.05` = 0.95 (5% slower)
- Half tank (50 kg): multiplier = `1.0 - (50/100) * 0.05` = 0.975 (2.5% slower)
- Empty tank (0 kg): multiplier = 1.0 (no penalty)

**Why this model**: It mirrors real F1 where a car with a full fuel load is measurably slower
per lap. The multiplier approach composes cleanly with the existing degradation multiplier —
final speed = `base_speed * degradation_multiplier * fuel_multiplier`.

### Fuel Consumption

```
fuel_consumed_per_lap = starting_fuel_kg / estimated_race_laps_on_this_fuel
```

Or more simply, `fuel_consumption_per_lap` is a config-driven constant (kg per lap).
Fuel is consumed at each lap crossing (discrete, not continuous). This matches the
lap-based degradation model.

### What Happens When Fuel Runs Out

If `current_fuel_kg <= 0`:
- Car does NOT stop immediately (would be jarring and complex).
- Instead, apply a severe speed penalty: `fuel_empty_penalty` (e.g., 0.5 = 50% speed).
- This simulates "running on fumes" and creates urgency to pit.
- A future version can add DNF (did not finish) for fuel-out if desired.

### New Types (`race_types.gd`)

```gdscript
class FuelConfig extends RefCounted:
    var enabled: bool = true
    var max_capacity_kg: float = 110.0         # maximum fuel tank capacity
    var consumption_per_lap_kg: float = 2.5    # fuel burned per completed lap
    var weight_penalty_factor: float = 0.05    # speed penalty at full tank (0.05 = 5%)
    var fuel_empty_penalty: float = 0.50       # multiplier when fuel is zero
    var refuel_rate_kg_per_sec: float = 2.0    # how fast fuel is added during pit stop

    func clone() -> FuelConfig:
        # ... standard deep clone
```

Add to `CarConfig`:

```gdscript
var starting_fuel_kg: float = -1.0  # -1 = use max_capacity; positive = specific amount
```

Add to `CarState`:

```gdscript
var fuel_kg: float = 0.0              # current fuel remaining
var fuel_multiplier: float = 1.0      # current speed multiplier from fuel weight
```

Add to `RaceConfig`:

```gdscript
var fuel: FuelConfig = null  # null = fuel disabled (no weight effect)
```

### New Module: `game/sim/src/fuel_model.gd`

```gdscript
class_name FuelModel extends RefCounted

static func compute_multiplier(
    current_fuel_kg: float,
    config: RaceTypes.FuelConfig
) -> float
    # Returns multiplier in [fuel_empty_penalty, 1.0]
    # If config is null, returns 1.0
    # If current_fuel_kg <= 0: return fuel_empty_penalty
    # Otherwise: return 1.0 - (current_fuel_kg / max_capacity_kg) * weight_penalty_factor

static func consume_fuel(
    current_fuel_kg: float,
    consumption_per_lap_kg: float
) -> float
    # Returns: maxf(current_fuel_kg - consumption_per_lap_kg, 0.0)

static func refuel(
    current_fuel_kg: float,
    added_fuel_kg: float,
    max_capacity_kg: float
) -> float
    # Returns: minf(current_fuel_kg + added_fuel_kg, max_capacity_kg)

static func compute_refuel_time(
    current_fuel_kg: float,
    target_fuel_kg: float,
    refuel_rate_kg_per_sec: float
) -> float
    # Returns time in seconds to add fuel from current to target
    # maxf(target_fuel_kg - current_fuel_kg, 0.0) / refuel_rate_kg_per_sec

static func validate_config(config: RaceTypes.FuelConfig) -> PackedStringArray
    # Checks: max_capacity > 0, consumption >= 0, weight_penalty in [0, 1],
    #         fuel_empty_penalty in (0, 1], refuel_rate > 0
```

**Stateless by design**: Like DegradationModel, FuelModel is a pure function module.
Fuel state (`current_fuel_kg`) lives on `CarState`. The model computes results from inputs.

### Simulator Integration

In `_compute_car_speed()`, AFTER degradation but BEFORE final speed assignment:

```gdscript
# Existing: speed *= car.degradation_multiplier
# NEW: fuel weight penalty
if _fuel_config != null:
    car.fuel_multiplier = FuelModel.compute_multiplier(car.fuel_kg, _fuel_config)
    speed *= car.fuel_multiplier
speed = maxf(speed, 0.001)
car.effective_speed_units_per_sec = speed
```

In `_register_lap_crossing()`, after incrementing `car.lap_count`:

```gdscript
if _fuel_config != null:
    car.fuel_kg = FuelModel.consume_fuel(car.fuel_kg, _fuel_config.consumption_per_lap_kg)
```

In `initialize()`:

```gdscript
# For each car, set starting fuel
for i in range(_cars.size()):
    var car_config = _config.cars[i]
    if _fuel_config != null:
        if car_config.starting_fuel_kg > 0.0:
            _cars[i].fuel_kg = minf(car_config.starting_fuel_kg, _fuel_config.max_capacity_kg)
        else:
            _cars[i].fuel_kg = _fuel_config.max_capacity_kg  # default to full tank
```

### Tests (`fuel_model_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_null_config_returns_1` | No fuel config -> multiplier 1.0 |
| `test_full_tank_penalty` | Full tank applies weight_penalty_factor |
| `test_empty_tank_no_penalty` | Zero fuel -> multiplier 1.0 |
| `test_half_tank_intermediate` | 50% fuel -> half the penalty |
| `test_fuel_empty_penalty_applied` | fuel_kg <= 0 -> fuel_empty_penalty multiplier |
| `test_consume_reduces_fuel` | consume_fuel decreases fuel_kg |
| `test_consume_floors_at_zero` | Cannot go below 0 fuel |
| `test_refuel_adds_fuel` | refuel increases fuel_kg |
| `test_refuel_caps_at_max` | Cannot exceed max_capacity_kg |
| `test_refuel_time_calculation` | Correct time for given rate and delta |
| `test_validate_rejects_negative_capacity` | max_capacity <= 0 -> error |
| `test_validate_rejects_penalty_over_1` | weight_penalty_factor > 1.0 -> error |
| `test_starting_fuel_respects_config` | Per-car starting fuel used when specified |
| `test_default_starting_fuel_is_max` | No per-car value -> full tank |

### Guardrails

- **DO NOT make fuel continuous (per-distance).** Fuel is consumed per lap, matching the
  lap-based degradation model. This keeps everything consistent and config portable.
- **DO NOT let fuel go negative.** Floor at 0.0. Apply `fuel_empty_penalty` when at zero.
- **DO NOT make FuelModel stateful.** It's a pure function module like DegradationModel.
  Fuel state lives on `CarState`.
- **DO NOT combine fuel_multiplier and degradation_multiplier into one field.** Keep them
  separate on CarState for HUD display and debugging. They multiply together in `_compute_car_speed`.
- **DO NOT forget `fuel_kg` and `fuel_multiplier` in `clone()` and `reset_runtime_state()`.**

---

## Feature 4: Pit Stop Execution

### Concept

A pit stop uses **config-defined distances** on the main track to model realistic pit entry and exit
positions. For Monza, the pit entry is before the Parabolica and the pit exit is after Turn 1.

At Monza, the pit lane runs alongside the main straight. Pit entry is on the straight
after exiting Parabolica (near the end of the lap). Pit exit is right before Turn 1
(Variante del Rettifilo, near the start of the next lap).

When a car is scheduled to pit:

1. **Approach**: Car races normally until reaching `pit_entry_distance` on the track
   (after Parabolica, on the main straight).
2. **Entry phase**: At `pit_entry_distance`, the car diverts to the pit lane at `pit_lane_speed`.
   This lasts for `pit_entry_duration` seconds (time to travel from track to pit box).
3. **Stopped phase**: Car is stationary in the pit box. Tyres are changed. Fuel is added.
   Duration = `base_pit_stop_duration` + refuel time (computed from fuel delta and refuel rate).
4. **Exit phase**: Car travels from pit box back to track at `pit_lane_speed` for
   `pit_exit_duration` seconds.
5. **Rejoin**: Car rejoins the track at `pit_exit_distance` (right before Turn 1)
   with new tyres and fuel.

### Pit Lane Distance Model

The pit lane is modeled as a shortcut/detour between two track positions:

```
                    Parabolica                          Turn 1
Track: ----...-----[pit_entry ~1950]====S/F LINE====[pit_exit ~80]-----...----
                         \                              /
                          \------- PIT LANE -----------/
                              (entry -> box -> exit)
```

- `pit_entry_distance`: distance along track where cars leave the racing line (e.g., ~1950 units
  on Monza — on the main straight after Parabolica, near end of lap)
- `pit_exit_distance`: distance along track where cars rejoin (e.g., ~80 units on Monza — right
  before Turn 1, near start of next lap)
- During pit phases, the car's `distance_along_track` is NOT updated normally. Instead:
  - On entry: `distance_along_track` freezes at `pit_entry_distance`
  - On stopped: car sits at a conceptual pit box position
  - On exit: `distance_along_track` snaps to `pit_exit_distance` when the car rejoins

This means the car "disappears" from the racing line at the entry point and "reappears"
at the exit point. Visually, the car dot can be hidden or moved to a pit lane indicator area.

### Track-Specific Pit Config

Pit entry/exit distances are track-specific, so they live inside the `pit` config block.
For Monza (track length ~2025 units):

```json
{
  "pit": {
    "enabled": true,
    "pit_entry_distance": 1950.0,
    "pit_exit_distance": 80.0,
    "pit_lane_speed_limit": 20.0,
    "base_pit_stop_duration": 3.0,
    "pit_entry_duration": 8.0,
    "pit_exit_duration": 8.0,
    "min_stop_lap": 1,
    "max_stops": 5
  }
}
```

**Real-world Monza reference**: The pit lane runs alongside the main straight between
Parabolica and Turn 1 (Variante del Rettifilo). Pit entry is on the main straight after
exiting Parabolica (~1950 units, near the end of the lap). Pit exit is right before
Turn 1 (~80 units, near the start of the next lap). The entry/exit durations (8 seconds
each) model the time spent traveling through the pit lane at reduced speed.

### New Types (`race_types.gd`)

```gdscript
class PitConfig extends RefCounted:
    var enabled: bool = true
    var pit_entry_distance: float = 0.0        # track distance where car diverts to pit
    var pit_exit_distance: float = 0.0         # track distance where car rejoins track
    var pit_lane_speed_limit: float = 20.0     # speed in pit lane (units/sec)
    var base_pit_stop_duration: float = 3.0    # seconds stationary for tyre change only
    var pit_entry_duration: float = 8.0        # seconds traveling from entry to pit box
    var pit_exit_duration: float = 8.0         # seconds traveling from pit box to exit
    var min_stop_lap: int = 1                  # cannot pit before this many completed laps
    var max_stops: int = 5                     # safety limit on total pit stops

    func clone() -> PitConfig:
        # ... standard deep clone
```

Add to `RaceConfig`:

```gdscript
var pit: PitConfig = null  # null = pitting disabled
```

Pit phases on CarState (encoded as int):

```
0 = PIT_PHASE_RACING     (normal on-track)
1 = PIT_PHASE_ENTRY      (traveling to pit box at pit_lane_speed)
2 = PIT_PHASE_STOPPED    (stationary in pit box, work in progress)
3 = PIT_PHASE_EXIT       (traveling from pit box to track at pit_lane_speed)
```

Add to `CarState`:

```gdscript
var pit_time_remaining: float = 0.0    # countdown for current pit phase
var pit_stops_completed: int = 0        # number of completed pit stops
var pit_target_compound: String = ""    # compound to fit during this stop
var pit_target_fuel_kg: float = -1.0    # fuel to add (-1 = fill to max)
```

### New Module: `game/sim/src/pit_stop_manager.gd`

```gdscript
class_name PitStopManager extends RefCounted

var _config: RaceTypes.PitConfig
var _fuel_config: RaceTypes.FuelConfig
var _is_enabled: bool = false

func configure(config: RaceTypes.PitConfig, fuel_config: RaceTypes.FuelConfig) -> void
func reset() -> void
func is_enabled() -> bool

func should_enter_pit(car: RaceTypes.CarState, pending_requests: Dictionary) -> bool
    # Returns true if:
    #   - car has a pending pit request
    #   - car.distance_along_track has reached or passed pit_entry_distance
    #   - car.lap_count >= min_stop_lap
    #   - car.pit_stops_completed < max_stops
    #   - car is not finished

func begin_pit_entry(car: RaceTypes.CarState, request: Dictionary) -> void
    # Set pit_phase = PIT_PHASE_ENTRY
    # Set pit_time_remaining = pit_entry_duration
    # Set is_in_pit = true
    # Set pit_target_compound from request
    # Set pit_target_fuel_kg from request
    # Freeze distance_along_track at pit_entry_distance

func process_pit_phase(car: RaceTypes.CarState, chunk_dt: float) -> Dictionary
    # Returns { "completed": bool, "new_compound": String, "refueled_to_kg": float }
    # Decrements pit_time_remaining by chunk_dt
    # Phase transitions:
    #   PIT_ENTRY complete -> PIT_STOPPED
    #     Set remaining = compute_stop_duration(car)
    #   PIT_STOPPED complete -> PIT_EXIT
    #     Tyres changed, fuel added (this is when the work happens)
    #     Set remaining = pit_exit_duration
    #   PIT_EXIT complete -> RACING
    #     Set is_in_pit = false, pit_phase = 0
    #     Set distance_along_track = pit_exit_distance (rejoin point)
    #     Return completed=true with new compound and fuel info

func compute_stop_duration(car: RaceTypes.CarState) -> float
    # Total stationary time = base_pit_stop_duration + refuel_time
    # refuel_time = FuelModel.compute_refuel_time(car.fuel_kg, target, rate)
    # If no refueling needed: just base duration

func get_pit_speed(car: RaceTypes.CarState) -> float
    # PIT_PHASE_ENTRY or PIT_PHASE_EXIT: return pit_lane_speed_limit
    # PIT_PHASE_STOPPED: return 0.0
    # PIT_PHASE_RACING: return -1.0 (sentinel: use normal speed)
```

### Simulator Integration — Pit Entry Detection

The key change: pit entry is NOT triggered at the start/finish line. It's triggered when
the car reaches `pit_entry_distance` during normal movement.

In `_apply_car_movement()`, AFTER updating `distance_along_track` but BEFORE lap crossing:

```gdscript
# Check if car should enter pit (only if car has pending request)
if _pit_stop_manager != null and _pit_stop_manager.is_enabled():
    if not car.is_in_pit and _pit_stop_manager.should_enter_pit(car, _pit_strategy.get_pending_requests()):
        var request = _pit_strategy.consume_request(car.id)
        _pit_stop_manager.begin_pit_entry(car, request)
        return  # Skip the rest of movement for this chunk — car is now in pit
```

**CRITICAL**: The pit entry distance check uses `distance_along_track`. The car's distance is
checked BEFORE lap crossing detection. This means:
- If `pit_entry_distance` is before the finish line (e.g., 1800 on a 2025 track), the car
  enters pit before crossing the finish line. The lap is NOT counted.
- If `pit_exit_distance` is after the start line (e.g., 200), the car rejoins ahead of the
  start/finish line and will cross it naturally later.

### Simulator Integration — Pit Processing in Step Loop

```gdscript
# Phase 1: Compute each car's speed
for car in _cars:
    if not _race_state_machine.is_car_racing(car):
        car.effective_speed_units_per_sec = 0.0
        continue

    if car.is_in_pit:
        var pit_result = _pit_stop_manager.process_pit_phase(car, chunk_dt)
        if pit_result.get("new_compound", "") != "":
            _stint_tracker.on_pit_stop_complete(car.id, pit_result["new_compound"])
        if pit_result.get("refueled_to_kg", -1.0) >= 0.0:
            car.fuel_kg = pit_result["refueled_to_kg"]
        car.pit_stops_completed += int(pit_result.get("completed", false))
        var pit_speed = _pit_stop_manager.get_pit_speed(car)
        car.effective_speed_units_per_sec = maxf(pit_speed, 0.0)
        continue

    _compute_car_speed(car)
```

### Important: Pit Cars and Overtaking

Cars in pit (`is_in_pit == true`) are **excluded from overtaking interactions**.
Modify `overtaking_manager.process_interactions()` to skip cars where `car.is_in_pit == true`.

### Important: Pit Cars and Standings

Cars in pit keep their `total_distance` from before entering. Since they don't accumulate
distance while stopped, other cars will pass them in `total_distance` naturally. When the car
exits at `pit_exit_distance`, `total_distance` recalculates from `lap_count * track_length + distance_along_track`.

### Important: Lap Count During Pit

When a car enters the pit BEFORE the finish line (e.g., at distance ~1950 on a ~2025-unit track),
it does NOT complete that lap. The car diverts before crossing the start/finish line. The lap
crossing happens only when the car actually passes the finish line distance. After exiting at
`pit_exit_distance` (e.g., ~80), the car must travel the full lap (~80 -> ~2025 -> crossing)
before the lap is counted. This is correct — in real F1, a pit stop costs roughly one lap of time.

Note: Since the pit entry and exit are both on the main straight (entry after Parabolica, exit
before Turn 1), the car enters near the end of the straight and exits near the beginning — the
pit lane runs alongside the full length of the straight.

### Tests (`pit_stop_manager_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_disabled_when_no_config` | null config -> is_enabled() == false |
| `test_entry_triggered_at_entry_distance` | Car at pit_entry_distance with request -> enters pit |
| `test_no_entry_before_entry_distance` | Car before pit_entry_distance -> stays on track |
| `test_entry_sets_pit_phase_and_flags` | begin_pit_entry sets phase=1, is_in_pit=true |
| `test_distance_frozen_during_entry` | distance_along_track stays at entry point |
| `test_entry_transitions_to_stopped` | After entry_duration, phase moves to 2 |
| `test_stopped_transitions_to_exit` | After stop_duration, phase moves to 3 |
| `test_exit_transitions_to_racing` | After exit_duration, phase=0, is_in_pit=false |
| `test_exit_sets_distance_to_exit_point` | On exit, distance_along_track = pit_exit_distance |
| `test_full_pit_stop_total_duration` | Total = entry + stop + refuel + exit |
| `test_stop_duration_includes_refuel_time` | More fuel needed = longer stop |
| `test_no_refuel_when_fuel_disabled` | FuelConfig null -> base duration only |
| `test_compound_change_on_stop_to_exit` | new_compound returned at correct transition |
| `test_pit_speed_during_entry` | Speed = pit_lane_speed during entry |
| `test_pit_speed_during_stopped` | Speed = 0 during stopped |
| `test_pit_speed_during_exit` | Speed = pit_lane_speed during exit |
| `test_min_stop_lap_enforced` | Cannot pit before min_stop_lap completed laps |
| `test_max_stops_enforced` | Cannot exceed max_stops |
| `test_no_pit_without_request` | Car doesn't pit unless requested |
| `test_no_pit_during_finishing` | Cannot pit when race is in FINISHING/FINISHED |
| `test_lap_not_counted_when_entering_pit` | Entering before finish line doesn't count as lap |

### Guardrails

- **DO NOT let pit_entry_distance == pit_exit_distance.** Validate in config loader.
  Entry must differ from exit to prevent zero-distance pit lane.
- **DO NOT let a car pit on the last lap or during FINISHING/FINISHED state.** Pit requests
  should be ignored when the race is ending.
- **DO NOT process overtaking for cars in pit.** They are off the racing line.
- **DO NOT let pit stop duration be zero.** `base_pit_stop_duration` minimum = 1.0 second.
- **DO NOT move the car's `distance_along_track` during PIT_ENTRY or PIT_STOPPED.** It freezes
  at `pit_entry_distance`. Only PIT_EXIT completion snaps it to `pit_exit_distance`.
- **DO NOT count a lap when the car enters the pit before the finish line.** The car enters
  at `pit_entry_distance` which is before the finish line. No lap crossing occurs.
- **DO NOT forget to update `reset_runtime_state()` and `clone()` for ALL new CarState fields.**
- **DO NOT let `pit_entry_distance` or `pit_exit_distance` exceed track_length.** Validate
  both are in `[0, track_length)`.
- **DO NOT update `distance_along_track` during PIT_ENTRY or PIT_STOPPED phases.**
  The car is conceptually "off the track" — its track position is meaningless until exit.

---

## Feature 5: Pit Strategy Queue

### Concept

The player can issue a "pit next lap" command for any car, specifying target compound and
optionally target fuel amount. The command is queued and executes when the car reaches
`pit_entry_distance` on the track.

### New Module: `game/sim/src/pit_strategy.gd`

```gdscript
class_name PitStrategy extends RefCounted

var _pending_requests: Dictionary = {}
    # car_id -> { "compound": String, "fuel_kg": float, "requested_at": float }

func reset() -> void
func get_pending_requests() -> Dictionary

func request_pit_stop(
    car_id: String,
    target_compound: String,
    target_fuel_kg: float,      # -1 = fill to max
    race_time: float
) -> void
    # Queue a pit stop. If request already exists, overwrite (latest command wins)

func cancel_pit_stop(car_id: String) -> void
func has_pending_request(car_id: String) -> bool

func consume_request(car_id: String) -> Dictionary
    # Returns and removes: { "compound": String, "fuel_kg": float }
    # Returns empty dict if no request
```

### Controller Integration

Add a signal from HUD -> controller -> simulator:

```gdscript
# In race_hud.gd:
signal pit_requested(car_id: String, compound: String, fuel_kg: float)
signal pit_cancelled(car_id: String)

# In race_controller.gd:
func _on_pit_requested(car_id: String, compound: String, fuel_kg: float) -> void:
    if _simulator != null:
        _simulator.request_pit_stop(car_id, compound, fuel_kg)

func _on_pit_cancelled(car_id: String) -> void:
    if _simulator != null:
        _simulator.cancel_pit_stop(car_id)
```

Add to `RaceSimulator`:

```gdscript
func request_pit_stop(car_id: String, compound_name: String, fuel_kg: float = -1.0) -> void:
    if _pit_strategy != null:
        _pit_strategy.request_pit_stop(car_id, compound_name, fuel_kg, _race_time)

func cancel_pit_stop(car_id: String) -> void:
    if _pit_strategy != null:
        _pit_strategy.cancel_pit_stop(car_id)
```

### Tests (`pit_strategy_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_request_registers_pending` | After request, has_pending_request returns true |
| `test_cancel_removes_pending` | After cancel, has_pending_request returns false |
| `test_consume_returns_and_removes` | consume_request returns data and clears it |
| `test_overwrite_replaces_previous` | Second request overwrites first |
| `test_consume_empty_returns_empty_dict` | No request -> empty dict |
| `test_request_includes_fuel` | Fuel target stored and returned |
| `test_reset_clears_all` | After reset, no pending requests |

### Guardrails

- **DO NOT auto-pit cars.** V3 is manual-only. AI strategy comes in a future version.
- **DO NOT allow pit requests for finished cars.** Validate car is still racing.
- **DO NOT allow pit requests when pit config is disabled.** Silently ignore.

---

## Feature 6: HUD Updates

### New Columns

Update the HUD column layout to:
**P | ID | Compound | Speed | Lap Count | Stint | Gap | Deg | Fuel | Current Lap | Last Lap | Best Lap**

- **Compound**: Shows current tyre compound abbreviation: `"S"` (soft), `"M"` (medium), `"H"` (hard).
  Use first letter, uppercase. If compound name is longer, show first 3 chars.
- **Stint**: Shows stint_lap_count (laps since last stop): `"3"`.
- **Fuel**: Shows fuel remaining as a percentage of max capacity: `"85%"`.
  When fuel at zero: `"EMPTY"`.

### Pit Status Indicators

- When car has pending pit request: show `"[PIT]"` suffix in the ID column
- When car is in pit: show `"IN PIT"` in the Speed column instead of speed value
- When car is in PIT_STOPPED phase: show `"BOX [3.2s]"` with countdown
- When car exits pit: compound column updates to new compound

### Pit Button

Add a clickable "PIT" button per car row. Clicking it:
1. If no pending request: emit `pit_requested` signal with default compound (next in rotation)
   and default fuel (-1 = fill to max)
2. If pending request exists: emit `pit_cancelled` to cancel it

For V3, keep this minimal. Compound selection can be a small popup or cycle-on-click.

### Update GridContainer

Update `_body_grid.columns` from 9 to 12 (adding Compound, Stint, and Fuel columns).

### Guardrails

- **DO NOT show pit controls when pit config is disabled.** Hide the pit button and
  compound/stint/fuel columns when pit is null/disabled.
- **DO NOT show pit button for finished cars.** Disable/hide it.
- **DO NOT show fuel column when fuel config is disabled.** Hide it.

---

## Config Schema: `config/race_v3.json`

```json
{
  "schema_version": "3.0",
  "count_first_lap_from_start": true,
  "seed": 42,
  "default_time_scale": 1.0,
  "total_laps": 15,
  "track": {
    "geometry_asset": "../data/tracks/monza/monza_centerline.json",
    "physics": {
      "a_lat_max": 25.0,
      "a_long_accel": 8.0,
      "a_long_brake": 20.0,
      "v_top_speed": 83.0,
      "curvature_epsilon": 0.0001
    }
  },
  "compounds": [
    {
      "name": "soft",
      "degradation": {
        "warmup_laps": 0.3,
        "peak_multiplier": 1.05,
        "degradation_rate": 0.04,
        "min_multiplier": 0.70
      }
    },
    {
      "name": "medium",
      "degradation": {
        "warmup_laps": 0.5,
        "peak_multiplier": 1.0,
        "degradation_rate": 0.02,
        "min_multiplier": 0.75
      }
    },
    {
      "name": "hard",
      "degradation": {
        "warmup_laps": 0.8,
        "peak_multiplier": 0.95,
        "degradation_rate": 0.01,
        "min_multiplier": 0.80
      }
    }
  ],
  "fuel": {
    "enabled": true,
    "max_capacity_kg": 110.0,
    "consumption_per_lap_kg": 2.5,
    "weight_penalty_factor": 0.05,
    "fuel_empty_penalty": 0.50,
    "refuel_rate_kg_per_sec": 2.0
  },
  "pit": {
    "enabled": true,
    "pit_entry_distance": 1950.0,
    "pit_exit_distance": 80.0,
    "pit_lane_speed_limit": 20.0,
    "base_pit_stop_duration": 3.0,
    "pit_entry_duration": 8.0,
    "pit_exit_duration": 8.0,
    "min_stop_lap": 1,
    "max_stops": 5
  },
  "overtaking": {
    "enabled": true,
    "proximity_distance": 50.0,
    "overtake_speed_threshold": 2.0,
    "held_up_speed_buffer": 0.1,
    "cooldown_seconds": 3.0
  },
  "cars": [
    {
      "id": "car_01",
      "display_name": "Red Bull",
      "v_ref": 83.0,
      "starting_compound": "soft",
      "starting_fuel_kg": 100.0
    },
    {
      "id": "car_02",
      "display_name": "Ferrari",
      "v_ref": 81.0,
      "starting_compound": "medium",
      "starting_fuel_kg": 110.0
    },
    {
      "id": "car_03",
      "display_name": "Mercedes",
      "v_ref": 80.0,
      "starting_compound": "soft",
      "starting_fuel_kg": 90.0
    },
    {
      "id": "car_04",
      "display_name": "McLaren",
      "v_ref": 79.0,
      "starting_compound": "hard",
      "starting_fuel_kg": 110.0
    }
  ],
  "debug": {
    "show_pace_profile": false,
    "show_curvature_overlay": false,
    "show_speed_overlay": true
  }
}
```

### Config Loader Changes

Add `schema_version "3.0"` routing in `race_config_loader.gd`.

V3 reuses the V2 parse branch for overtaking. The V3 parse branch extends V2 with:
- `compounds` array parsing (reuse `_parse_degradation_config` for each compound's degradation)
- `fuel` object parsing
- `pit` object parsing (with distance + duration fields)
- Per-car `starting_compound` and `starting_fuel_kg` fields

Accepted `schema_version` values: add `"3.0"` to the allowed set in `_parse_schema_version`.

**Backward compatibility:**

| Config version | compounds | fuel | pit | starting_compound | starting_fuel_kg |
|---|---|---|---|---|---|
| 1.0, 1.1 | empty (legacy degradation) | null (disabled) | null (disabled) | N/A | N/A |
| 2.0 | empty (legacy degradation) | null (disabled) | null (disabled) | N/A | N/A |
| 3.0 | from config | from config | from config | from config | from config |

---

## Global Guardrails (Apply to All Features)

1. **Sim/presentation boundary**: All new modules go in `game/sim/src/`. No Godot Node
   dependencies. No file I/O. Pure logic. Only HUD changes touch Godot UI classes.

2. **Determinism**: All durations, fuel consumption, and phase transitions are fixed-step.
   No randomness in V3. Identical inputs produce identical results.

3. **Backward compatibility**: V1, V1.1, and V2 configs must still work with zero changes.
   All new fields have safe defaults. When compounds are empty, V2 degradation path is used.
   When fuel is null, no fuel effect. When pit is null, no pit stops.

4. **Tests first**: Each new module gets its own test file. Existing tests must not break.
   Run the full GdUnit suite after each feature.

5. **Config-driven**: No magic numbers in code. All tuning parameters live in JSON config.

6. **Clone/reset discipline**: Every new field on `CarState` must be added to BOTH
   `clone()` AND `reset_runtime_state()`. This is the #1 source of bugs — verify manually
   for every field you add.

7. **The `_cars` array in RaceSimulator is SACRED.** Never sort it, never reorder it.
   Position is a field on each car, not an array index.

8. **DegradationModel stays untouched.** Pit stops work by changing the INPUTS
   (stint_lap_count + compound's DegradationConfig), not by modifying the model.

9. **FuelModel is stateless.** Like DegradationModel, it takes inputs and returns values.
   Fuel state lives on `CarState`.

10. **Pit entry/exit distances are track-specific.** They must be validated against
    `track_length` in the config loader. Both must be in `[0, track_length)` and must differ.

---

## Things That Could Go Wrong (Error-Prone Areas)

### 1. Stint Lap Count vs Race Lap Count

The existing code feeds `car.lap_count` to `DegradationModel`. V3 must feed `stint_lap_count`
instead when compounds are active. If any code path still uses `car.lap_count` for degradation,
tyres will not reset on pit stops.

**Mitigation**: Create a single function `_get_degradation_inputs(car)` that returns
`(lap_count, fractional_lap, config)`. When compounds active, it queries stint tracker.
When not, it uses the V2 path. All degradation computation goes through this one function.

### 2. Pit Stop During Overtaking

A car entering the pit might be within proximity of another car. Overtaking must be skipped
for pit-bound cars.

**Mitigation**: In `overtaking_manager.process_interactions()`, add:
`if car.is_in_pit: continue`. One-line addition to the existing loop.

### 3. Pit Entry Timing — Distance vs Lap Crossing

Pit entry is at `pit_entry_distance`, NOT at the finish line. If the check runs in
`_register_lap_crossing()`, it would only trigger at the finish line — wrong!

**Mitigation**: Check `should_enter_pit` in `_apply_car_movement()` AFTER distance update
but BEFORE lap crossing detection. The car's `distance_along_track` passes through
`pit_entry_distance` mid-lap, triggering the pit diversion before reaching the finish.

### 4. Compound Not Found

If a player requests a compound name that doesn't exist in the config.

**Mitigation**: `TyreCompound.find_compound()` returns null for unknown names. Fall back
to the first compound in the array. Log a warning but don't crash.

### 5. Pit Stop + Race End Interaction

If the leader finishes while another car is in the pit.

**Mitigation**: A car in pit does not cross the finish line, so it won't trigger finish.
It finishes on its next real lap crossing after exiting. The race state machine handles
this correctly — `on_lap_completed` is only called at actual crossings.

### 6. Reset While Car Is In Pit

**Mitigation**: `reset()` calls `reset()` on stint tracker, fuel model state (via CarState),
and pit stop manager. `CarState.reset_runtime_state()` clears all pit/fuel/stint fields.

### 7. Fuel Multiplier Stacking with Degradation

Both degradation and fuel produce speed multipliers. They must compose correctly:
`speed = base_speed * degradation_multiplier * fuel_multiplier`.

**Mitigation**: Apply degradation first, then fuel, both in `_compute_car_speed()`.
Keep them as separate fields on CarState. Never merge them into one value.

### 8. Pit Entry Distance Near Track Boundary

If `pit_entry_distance` is very close to `track_length` (e.g., 2020 on a 2025 track),
the car might wrap past it in a single chunk step.

**Mitigation**: In the entry check, use a range check:
`previous_distance < pit_entry_distance <= new_distance` (accounting for wrap-around).
This is the same pattern used in lap crossing detection.

### 9. Fuel Consumption During Pit Stop

Should fuel be consumed while the car is in the pit? No — fuel burns per completed lap,
and the car doesn't complete a lap while pitting.

**Mitigation**: Fuel consumption only happens in `_register_lap_crossing()`. Since pit
stops don't trigger lap crossings, fuel is naturally not consumed during stops.

### 10. Refuel Time Calculation Edge Cases

If `target_fuel_kg < current_fuel_kg` (player wants LESS fuel), refuel time should be 0,
not negative. If `refuel_rate_kg_per_sec = 0`, would cause division by zero.

**Mitigation**: `compute_refuel_time` clamps delta to `maxf(0.0)`. Config validation
ensures `refuel_rate_kg_per_sec > 0`.

---

## Verification Checklist

### Per-Feature

**F1 (Tyre Compounds):**
- [ ] `TyreCompoundConfig` type with name + degradation + clone
- [ ] `TyreCompound` static utility class (find, default, validate)
- [ ] `compounds` array on RaceConfig, parsed in config loader
- [ ] V2 configs still work (empty compounds = legacy degradation)
- [ ] All 8 compound tests pass

**F2 (Stint Tracking):**
- [ ] `StintTracker` module with configure/reset/lap/pit methods
- [ ] `stint_lap_count`, `current_compound`, `stint_number` on CarState with clone/reset
- [ ] Simulator feeds `stint_lap_count` to DegradationModel when compounds active
- [ ] `on_lap_completed` called in `_register_lap_crossing`
- [ ] All 11 stint tracker tests pass

**F3 (Fuel Model):**
- [ ] `FuelConfig` type with clone
- [ ] `FuelModel` static module (compute_multiplier, consume, refuel, validate)
- [ ] `fuel_kg` and `fuel_multiplier` on CarState with clone/reset
- [ ] Per-car `starting_fuel_kg` parsed in config loader
- [ ] Fuel consumed per lap in `_register_lap_crossing`
- [ ] Speed penalty applied in `_compute_car_speed` after degradation
- [ ] All 14 fuel model tests pass
- [ ] V2 configs still work (null fuel = no effect)

**F4 (Pit Stop Execution):**
- [ ] `PitConfig` type with entry/exit distances + clone
- [ ] `PitStopManager` with distance-based entry, phase transitions, distance-based exit
- [ ] All pit-related fields on CarState with clone/reset
- [ ] Pit entry at `pit_entry_distance`, not at finish line
- [ ] Pit exit snaps `distance_along_track` to `pit_exit_distance`
- [ ] Stop duration includes refuel time
- [ ] Pit cars excluded from overtaking
- [ ] Pit cars don't trigger race finish while in pit
- [ ] Lap NOT counted when entering pit before finish line
- [ ] All 21 pit stop manager tests pass

**F5 (Pit Strategy Queue):**
- [ ] `PitStrategy` with request/cancel/consume (includes fuel target)
- [ ] `RaceSimulator.request_pit_stop()` and `cancel_pit_stop()` public methods
- [ ] HUD signal -> controller -> simulator pit command flow
- [ ] All 7 strategy tests pass

**F6 (HUD Updates):**
- [ ] Compound, Stint, and Fuel columns added
- [ ] Pit button per car row
- [ ] Pit status indicators ([PIT], IN PIT, BOX countdown)
- [ ] Columns hidden when pit/fuel disabled
- [ ] GridContainer columns updated to 12

### End-to-End Manual Verification

1. Run with `race_v3.json`, 15 laps, 4 cars with different compounds and fuel loads.
2. Observe soft-tyre cars degrade faster than hard-tyre cars.
3. Observe heavier-fueled cars are slightly slower at race start.
4. As fuel burns off, cars get faster (fuel multiplier approaches 1.0).
5. Click PIT button on a car -> `[PIT]` appears in ID column.
6. Car reaches pit entry distance and diverts. Speed shows "IN PIT".
7. Car dot disappears from racing line (or moves to pit indicator area).
8. Stop duration is longer when more fuel is needed.
9. Car exits at pit exit distance with new compound. Compound column updates.
10. Degradation visibly resets (goes back toward peak) after pit stop.
11. Fuel gauge resets to refueled amount.
12. Car loses positions during pit stop, then recovers with fresh tyres and lighter fuel.
13. Race ends correctly even when a car is mid-pit-stop.
14. Reset -> everything restored. All pit, fuel, stint state cleared.
15. Switch to `race_v2.json` -> still works (no compounds, no fuel, no pit, legacy degradation).
16. Switch to `race_v1.1.json` -> still works.

---

## Architecture Decisions

### Why Config-Defined Pit Distances (Not Pit Lane Geometry)

The current track data (TUMFTM racetrack-database) provides centerline + curvature only —
no pit lane path. Rather than requiring a second polyline:

- `pit_entry_distance` and `pit_exit_distance` are defined as distances along the main track
  centerline in the config JSON
- These are track-specific values that correspond to real-world pit lane positions
- The car "disappears" from the racing line at entry and "reappears" at exit
- This is architecturally clean: adding full pit lane geometry later only changes
  `PitStopManager` internals and rendering — StintTracker, PitStrategy, compounds, and fuel
  are completely unaffected

### Why Fuel Is a Separate Multiplier

Fuel and degradation both affect speed, but they are independent systems:
- Degradation depends on tyre compound + stint laps (resets on pit stop)
- Fuel depends on total fuel remaining (partially refilled on pit stop)

Keeping them as separate multipliers (`degradation_multiplier` and `fuel_multiplier`) on
CarState means:
- The HUD can show both independently
- The player can reason about each factor separately
- Testing is easier (test fuel in isolation from degradation)
- Future additions (engine modes, DRS) follow the same pattern: independent multipliers

### Why Lap-Based Fuel Consumption (Not Distance-Based)

Fuel is consumed per completed lap, not per meter traveled. This matches:
- The existing lap-based degradation model
- Real-world F1 engineering (teams calculate fuel per lap)
- Config portability between tracks of different lengths
- Simplicity (no fractional fuel tracking per integration step)
