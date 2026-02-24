# V2 Implementation Plan — Live Standings, Race End, Overtaking, Degradation

## Context

V1.1 ships physics-derived speed profiles from real Monza geometry. Cars slow for corners,
brake realistically, and differ by `v_ref`. But the experience is not yet a *race*:

- The HUD shows cars in static config order — no standings, no positions
- The race never ends — it loops forever
- Cars phase through each other — no overtaking rules
- Speed is constant across the entire race — no degradation

V2 turns this into a race. After V2, there is a leader, a finishing order, realistic
passing battles, and tyre-like degradation that changes pace over the race distance.

**Design north star**: the user's end goal is a Motorsport Manager-style game. Every type,
module, and config field in V2 must be designed so future features (tyre compounds, pit stops,
fuel, weather, DRS zones, safety cars) can be added by *extending* V2 code, not rewriting it.

---

## Implementation Order and Dependencies

```
Feature 1: Live Standings           <- implement first (no dependencies)
        |
        v
Feature 2: Race End Condition       <- needs F1 (positions to determine leader)
        |
        v
Feature 3: Pace Degradation         <- needs F2 (lap count drives degradation)
        |
        v
Feature 4: Overtaking Logic         <- needs F1 (positions), F2 (finished-car checks),
                                       F3 (degradation creates the speed deltas that
                                       make overtaking interesting to test)
```

Each feature ships as its own branch (`feat/v2-standings`, `feat/v2-race-end`,
`feat/v2-degradation`, `feat/v2-overtaking`) and is PR'd into `main` in sequence.

---

## Current State (What Exists)

| What | Status |
|---|---|
| `CarState` fields | id, display_name, v_ref, effective_speed, distance_along_track, lap_count, lap_start_time, last_lap_time, best_lap_time, current_multiplier |
| `RaceSnapshot` | race_time, cars (in config array order) |
| Position tracking | **None** -- no position field, HUD unsorted |
| Race end | **None** -- infinite loop |
| Overtaking | **None** -- cars phase through each other |
| Degradation | **None** -- constant speed per car |
| HUD columns | ID, Speed, Lap Count, Current Lap, Last Lap, Best Lap |
| Sim step | `_step_car_chunk()` computes speed + applies distance in one pass |

---

## File Inventory

### New Files

| File | Feature | Purpose |
|---|---|---|
| `game/sim/src/standings_calculator.gd` | F1 | Position computation from car states |
| `game/sim/src/race_state_machine.gd` | F2 | NOT_STARTED -> RUNNING -> FINISHING -> FINISHED |
| `game/sim/src/degradation_model.gd` | F3 | Warmup/peak/degradation multiplier per car |
| `game/sim/src/overtaking_manager.gd` | F4 | Proximity detection, held-up logic, cooldowns |
| `game/sim/tests/standings_calculator_test.gd` | F1 | |
| `game/sim/tests/race_state_machine_test.gd` | F2 | |
| `game/sim/tests/degradation_model_test.gd` | F3 | |
| `game/sim/tests/overtaking_manager_test.gd` | F4 | |
| `config/race_v2.json` | All | V2 config with all new fields |

### Modified Files

| File | Features | What Changes |
|---|---|---|
| `game/sim/src/race_types.gd` | All | New fields on CarState, RaceSnapshot, RaceConfig; new types |
| `game/sim/src/race_simulator.gd` | All | Integrate all four modules; refactor `_step_car_chunk` into two phases |
| `game/scripts/race_config_loader.gd` | F2, F3, F4 | Schema 2.0 parse branch; new field parsing |
| `game/scripts/race_controller.gd` | F2 | Auto-pause on race finish |
| `game/ui/race_hud.gd` | F1, F2, F3, F4 | Sort by position; P, Gap, Deg columns; race state display |
| `game/ui/race_hud.tscn` | F1 | GridContainer column count update |
| `game/sim/tests/race_simulator_test.gd` | F2, F4 | V2 integration tests |

### Untouched

`fixed_step_runner.gd`, `pace_profile.gd`, `speed_profile.gd`, `track_geometry.gd`,
`track_sampler.gd`, `track_loader.gd`, `car_dot.gd`, all debug overlays,
`config/race_v0.json`, `config/race_v1.json`, `config/race_v1.1.json`.

---

## Feature 1: Live Standings Board

### New Types (`race_types.gd`)

Add to `CarState`:

```gdscript
var position: int = 0            # 1-based race position (1 = leader)
var total_distance: float = 0.0  # lap_count * track_length + distance_along_track
```

Update `reset_runtime_state()` to zero both. Update `clone()` to copy both.

**Why `total_distance`**: `distance_along_track` wraps at the finish line. A car on lap 5
at distance 10 is ahead of a car on lap 4 at distance 5000. `total_distance` is a single
monotonically increasing number that captures both lap count and within-lap position.
It is the **only** value safe for cross-car comparison.

### New Module: `game/sim/src/standings_calculator.gd`

```gdscript
class_name StandingsCalculator extends RefCounted

static func update_positions(cars: Array[RaceTypes.CarState]) -> void
    # Sort indices by total_distance DESC (stable sort -- config order breaks ties)
    # Assign position = rank (1-based)

static func compute_interval_to_car_ahead(
    cars: Array[RaceTypes.CarState]
) -> Dictionary
    # Returns { car_id: float } where float is the distance gap
    # Leader's interval = 0.0
    # For car at position P: find car at position P-1,
    #   interval = ahead.total_distance - this.total_distance
```

### Simulator Integration

In `race_simulator.gd`:

After moving all cars in each chunk, update `total_distance` and call standings:

```gdscript
# At end of each chunk, after all cars moved:
for car in _cars:
    car.total_distance = float(car.lap_count) * _runtime.track_length + car.distance_along_track
StandingsCalculator.update_positions(_cars)
```

In `reset()`: after resetting car states, call `StandingsCalculator.update_positions(_cars)`
so initial positions reflect grid order (config array order = starting grid).

### HUD Changes

Add **P** (position) as the first column and **Gap** (interval to car ahead in seconds)
after Lap Count.

New column layout: **P | ID | Speed | Lap Count | Gap | Current Lap | Last Lap | Best Lap**

**Gap display**: Show in seconds (F1 broadcast style). Compute as:
`interval_distance / car.effective_speed_units_per_sec`. Display P1 as `"Leader"`.
If car's speed is 0, display `"--"`.

**Sorting**: In `render()`, create a local sorted copy of `snapshot.cars` ordered by
`car.position` ASC. Do NOT mutate the snapshot itself.

Update `_body_grid.columns` in the scene file (`race_hud.tscn`) from 6 to 8.
Add header labels for P and Gap.

### Tests (`standings_calculator_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_single_car_is_position_1` | One car -> position = 1 |
| `test_faster_car_has_lower_position` | Two cars at different total_distance -> higher distance = P1 |
| `test_lapped_car_is_behind` | Car on fewer laps is behind even if distance_along_track is higher |
| `test_same_distance_preserves_config_order` | Ties broken by array index (grid order) |
| `test_positions_update_after_pass` | Move car A past B in total_distance -> positions swap |
| `test_interval_is_correct` | Three cars -> interval values match expected gaps |
| `test_leader_interval_is_zero` | P1 car has 0.0 interval |
| `test_empty_cars_array_is_noop` | No crash on empty input |

### Guardrails

- **DO NOT sort the `_cars` array inside RaceSimulator.** The internal array must stay in
  config order. Position is a field ON each car, not determined by array index. Sorting the
  array would break the config-index contract that `get_snapshot()` relies on and would break
  Feature 4's overtaking pair tracking.
- **DO NOT compute positions in the HUD.** The HUD sorts a local copy for display.
  Authoritative positions live in `CarState.position`, computed in the sim layer.
- **DO NOT use `distance_along_track` for cross-car comparison.** It wraps at the finish
  line. Always use `total_distance`.
- **DO NOT forget to update `total_distance` on every chunk step**, not just on lap crossing.

### Error Scenarios

- All cars at distance 0 (race start): positions should be 1, 2, 3... in config order.
- `total_distance` overflow: `float64` handles ~10^15 -- fine for any realistic race.
- Snapshot with empty `cars` array: standings calculator must be a no-op.

### Enhancement Possibilities

- Interval to leader (in addition to interval to car ahead).
- Positions gained/lost relative to starting grid.
- Fastest lap indicator per car.

---

## Feature 2: Race End Condition

### New Types (`race_types.gd`)

Add race state enum:

```gdscript
enum RaceState {
    NOT_STARTED = 0,
    RUNNING = 1,
    FINISHING = 2,  # Leader done, others still crossing
    FINISHED = 3    # All cars finished
}
```

Add to `CarState`:

```gdscript
var is_finished: bool = false
var finish_position: int = 0   # 1-based finish order (0 = not yet finished)
var finish_time: float = -1.0  # race_time when car crossed finish after leader
```

Add to `RaceConfig`:

```gdscript
var total_laps: int = 0  # 0 = unlimited (V1/V1.1 backward compatible)
```

Add to `RaceSnapshot`:

```gdscript
var race_state: int = RaceTypes.RaceState.NOT_STARTED
var total_laps: int = 0
var finish_order: Array[String] = []  # car IDs in finishing order
```

Update `reset_runtime_state()`, `clone()` for all modified types.

### New Module: `game/sim/src/race_state_machine.gd`

```gdscript
class_name RaceStateMachine extends RefCounted

var _state: int = RaceTypes.RaceState.NOT_STARTED
var _total_laps: int = 0
var _finish_order: Array[String] = []
var _next_finish_position: int = 1
var _total_car_count: int = 0

func configure(total_laps: int, car_count: int) -> void
func reset() -> void
func get_state() -> int
func get_finish_order() -> Array[String]
func is_unlimited() -> bool    # total_laps <= 0

func on_race_start() -> void
    # NOT_STARTED -> RUNNING

func on_lap_completed(car: RaceTypes.CarState, crossing_time: float) -> void
    # Called from _register_lap_crossing AFTER incrementing lap_count.
    #
    # If RUNNING and not unlimited and car.lap_count >= total_laps:
    #   -> FINISHING
    #   Mark car finished (is_finished, finish_position, finish_time)
    #   Append to finish_order
    #
    # If FINISHING and car crosses finish (any lap crossing for unfinished car):
    #   Mark car finished
    #   Append to finish_order
    #   If all cars finished -> FINISHED

func is_car_racing(car: RaceTypes.CarState) -> bool
    # Returns true if car should still move
    return not car.is_finished
```

**State transitions:**

```
NOT_STARTED --on_race_start()--> RUNNING
RUNNING --leader hits total_laps--> FINISHING
FINISHING --last car crosses--> FINISHED
```

### Simulator Integration

In `race_simulator.gd`:

- Add member: `_race_state_machine: RaceStateMachine`
- In `initialize()`: configure state machine with `total_laps` and car count
- In `step()`:
  - If FINISHED: return immediately (no more simulation)
  - If NOT_STARTED: call `on_race_start()` on first step
- In `_step_car_chunk()`:
  - If `not _race_state_machine.is_car_racing(car)`: skip this car entirely, set `effective_speed = 0.0`
- In `_register_lap_crossing()`:
  - After incrementing `lap_count`, call `_race_state_machine.on_lap_completed(car, crossing_time)`
- In `get_snapshot()`: populate `race_state`, `total_laps`, `finish_order`
- In `reset()`: reset state machine and clear finish fields on all cars

### Controller Changes

In `_apply_snapshot()`:
- When `race_state == FINISHED` and not already paused: auto-pause

### HUD Changes

- Status message shows race state: `"Running Lap 3/10"`, `"Finishing..."`, `"Race Over"`
- Finished cars show finish position and time delta from winner in the Gap column:
  `"F1"`, `"F2 +1.234s"`, `"F3 +5.678s"`

### Tests (`race_state_machine_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_initial_state_is_not_started` | Fresh state machine |
| `test_transitions_to_running` | After `on_race_start()` |
| `test_leader_finishing_triggers_finishing` | First car at `total_laps` -> FINISHING |
| `test_all_cars_finishing_triggers_finished` | Last car crosses -> FINISHED |
| `test_finished_car_stops_accumulating_laps` | Finished car's `lap_count` stays frozen |
| `test_unlimited_laps_never_finishes` | `total_laps=0` -> stays RUNNING forever |
| `test_finish_order_matches_crossing_sequence` | 3 cars finishing in order |
| `test_finish_time_is_analytical_crossing_time` | Not chunk boundary time |
| `test_backmarker_finishes_on_next_crossing` | Lapped car finishes when it next crosses the line |
| `test_reset_clears_everything` | All state restored to NOT_STARTED |

Add to `race_simulator_test.gd`:

| Test | What It Verifies |
|---|---|
| `test_race_ends_after_total_laps` | FINISHED state after all cross |
| `test_finished_car_speed_is_zero` | Finished car effective_speed = 0 |
| `test_step_is_noop_after_finished` | race_time stops advancing |

### Guardrails

- **DO NOT check `lap_count >= total_laps` on every step.** Only check inside
  `_register_lap_crossing` when a lap is actually completed. Checking every step wastes
  cycles and risks double-triggering.
- **DO NOT let a finished car accumulate distance.** Skip `_step_car_chunk` entirely.
  Set `effective_speed = 0.0` for HUD display.
- **DO NOT modify `finish_position` after assignment.** It is immutable once set.
- **DO NOT assume leader is `cars[0]`.** Leader is the car with `position == 1`
  (from Feature 1). Use position, not array index.
- **DO NOT transition NOT_STARTED -> FINISHING directly.** Must go through RUNNING.

### Error Scenarios

- `total_laps = 1`: race finishes after first full lap for the leader.
- All cars identical speed: they all finish on the same crossing. Finish order = position
  order at that moment (config order since they never separated).
- Leader finishes mid-chunk: crossing time is analytical. Other cars that also cross
  in the same chunk are marked finished if appropriate.
- `total_laps` absent from config: defaults to 0 (unlimited). V1/V1.1 backward compatible.
- Reset after FINISHED: must fully restore NOT_STARTED with all finish fields cleared.

### Enhancement Possibilities

- Timed races (finish after N minutes instead of N laps).
- DNF (did not finish) status for mechanical failures.
- Safety car causing race neutralization.
- Chequered flag animation when leader finishes.

---

## Feature 3: Pace Degradation

### New Types (`race_types.gd`)

```gdscript
class DegradationConfig extends RefCounted:
    var warmup_laps: float = 0.5       # laps until peak performance
    var peak_multiplier: float = 1.0   # multiplier at peak (typically 1.0)
    var degradation_rate: float = 0.0  # multiplier loss per lap after peak
    var min_multiplier: float = 0.7    # floor -- speed never drops below this
    func clone() -> DegradationConfig
```

Add to `CarConfig`:

```gdscript
var degradation: RaceTypes.DegradationConfig = null  # per-car override; null = use global
```

Add to `RaceConfig`:

```gdscript
var degradation: RaceTypes.DegradationConfig = null  # global default; null = no degradation
```

Add to `CarState`:

```gdscript
var degradation_multiplier: float = 1.0  # current degradation factor [0..1]
```

Update `reset_runtime_state()` to set `degradation_multiplier = 1.0`. Update `clone()`.

### The Degradation Curve

The model uses **lap count + fractional lap progress** as the input:

```
race_progress = lap_count + (distance_along_track / track_length)
```

Three phases:

```
Phase 1 -- Warm-up (race_progress < warmup_laps):
    Linear ramp from warmup_start to peak_multiplier.
    warmup_start = max(peak_multiplier - warmup_laps * degradation_rate, min_multiplier)

Phase 2 -- Peak (race_progress == warmup_laps):
    multiplier = peak_multiplier

Phase 3 -- Degradation (race_progress > warmup_laps):
    multiplier = peak_multiplier - (race_progress - warmup_laps) * degradation_rate
    Floored at min_multiplier.
```

This creates the realistic F1 tyre profile: cold start -> optimal grip -> gradual fall-off.

**Why lap-based, not distance-based**: Tyre degradation in motorsport correlates with
lap count. Pit stop strategy (future feature) is lap-based. Config is portable between
tracks of different lengths.

### New Module: `game/sim/src/degradation_model.gd`

```gdscript
class_name DegradationModel extends RefCounted

static func compute_multiplier(
    lap_count: int,
    fractional_lap: float,       # distance_along_track / track_length [0.0..1.0)
    config: DegradationConfig
) -> float
    # Returns multiplier in [config.min_multiplier, config.peak_multiplier]
    # If config is null, returns 1.0

static func validate_config(config: DegradationConfig) -> PackedStringArray
    # Checks: peak > 0 and <= 2.0, min > 0 and <= peak,
    #         degradation_rate >= 0, warmup_laps >= 0
```

**Stateless by design**: The model takes inputs and returns a value. It holds no internal
state about "current tyre life." This is critical for future extensibility -- when pit stops
arrive, a stop resets the car's lap count for degradation purposes (fresh tyres), and the
model can be called with the new count without any state management.

### Simulator Integration

In `race_simulator.gd`:

During `initialize()`, build a lookup: `_car_degradation_configs: Dictionary`
(car.id -> DegradationConfig). For each car, use car-specific config if present,
otherwise use global config, otherwise null (no degradation).

In `_step_car_chunk()`, AFTER computing speed from the profile but BEFORE applying to distance:

```gdscript
var deg_config: DegradationConfig = _car_degradation_configs.get(car.id)
car.degradation_multiplier = DegradationModel.compute_multiplier(
    car.lap_count,
    car.distance_along_track / _runtime.track_length,
    deg_config
)
speed *= car.degradation_multiplier
speed = maxf(speed, 0.001)  # absolute floor -- never zero or negative
```

In `reset()`: `car.degradation_multiplier = 1.0`

### Config Format

Global default applies to all cars that don't override:

```json
{
  "degradation": {
    "warmup_laps": 0.5,
    "peak_multiplier": 1.0,
    "degradation_rate": 0.02,
    "min_multiplier": 0.7
  },
  "cars": [
    {
      "id": "car_01", "v_ref": 83.0,
      "degradation": {
        "warmup_laps": 0.3,
        "degradation_rate": 0.015,
        "min_multiplier": 0.75
      }
    },
    { "id": "car_02", "v_ref": 79.0 }
  ]
}
```

Car 01 uses its own degradation. Car 02 uses the global. If global is absent too,
`degradation_multiplier` stays 1.0 (backward compatible with V1/V1.1).

### HUD Changes

Add **Deg** column showing degradation as a percentage: `"98%"`, `"85%"`.

### Tests (`degradation_model_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_null_config_returns_1` | No degradation -> multiplier 1.0 |
| `test_peak_at_warmup_laps` | At exactly warmup_laps, multiplier == peak |
| `test_warmup_ramp_is_linear` | At half warmup_laps, multiplier between start and peak |
| `test_degradation_after_peak` | After warmup, multiplier decreases by rate per lap |
| `test_min_multiplier_floor` | After many laps, multiplier never below min |
| `test_zero_rate_stays_at_peak` | degradation_rate=0 -> always peak (backward compat) |
| `test_fractional_lap_is_smooth` | Mid-lap, multiplier interpolated, not stepped |
| `test_speed_floor_prevents_zero` | Extreme degradation can't produce zero speed |
| `test_per_car_config_overrides_global` | Car with own config uses it; car without uses global |
| `test_warmup_laps_zero_starts_at_peak` | No warmup phase |

### Guardrails

- **DO NOT apply degradation inside the speed profile module.** The speed profile is a
  static precomputed array representing the track's ideal speed. Degradation is runtime
  state that changes per-car per-lap. Apply it in `_step_car_chunk` after sampling the profile.
- **DO NOT allow degradation to produce zero or negative speed.** Always clamp:
  `speed = maxf(speed, 0.001)`.
- **DO NOT make degradation distance-based within a lap.** Use `lap_count + fractional_lap`.
  Distance-based would couple degradation to track length and make config non-portable.
- **DO NOT reset degradation_multiplier on lap crossing.** It is continuous.
- **DO NOT close off the tyre compound path.** `DegradationConfig` will later gain a
  `compound` field. A pit stop will swap the config and reset the car's degradation progress.
  Keep the model stateless so compound swaps are trivial.
- **DO NOT store degradation state (accumulated wear, phase) inside DegradationModel.**
  The model is a pure function of (lap_count, fractional_lap, config). This is what makes
  it deterministic, testable, and extensible.

### Error Scenarios

- `warmup_laps = 0`: start at peak immediately -- valid.
- `degradation_rate = 0`: no degradation, always at peak -- backward compatible mode.
- `min_multiplier > peak_multiplier`: validation error -- reject in config loader.
- `peak_multiplier = 0.5`: valid but unusual -- 50% base speed. Allow it.
- Very high `degradation_rate` (1.0/lap): hits min_multiplier within 1 lap. Should work.

### Enhancement Possibilities

- **Tyre compounds**: DegradationConfig per compound (soft = faster peak + higher deg rate,
  hard = slower peak + lower deg rate). Swap config on pit stop.
- **Non-linear degradation**: exponential fall-off, "cliff" at certain lap count.
- **Temperature/weather** affecting degradation_rate dynamically.
- **Fuel load**: additional multiplier that linearly decreases as fuel burns (lighter = faster).

---

## Feature 4: Overtaking Logic

This is the most complex feature. Read this section carefully before implementing.

### The Model: Proximity-Threshold Overtaking

Cars do NOT phase through each other. When a faster car catches a slower car:

1. **Within proximity?** Is the faster car within `proximity_distance` of the car ahead
   (measured on the track, accounting for wrap-around)?
2. **Enough speed advantage?** Is `speed_behind - speed_ahead >= overtake_speed_threshold`?
3. **Yes -> Natural pass**: The faster car keeps its full speed. Over the next few
   integration chunks, its dot naturally moves past the slower car. No teleporting.
4. **No -> Held up**: The faster car's speed is capped to the car ahead's speed + a tiny
   buffer. The car is stuck in a "train" until it builds enough of a speed advantage.
5. **Cooldown**: After a pass, the same pair cannot interact for `cooldown_seconds`.
   This prevents A-passes-B-then-B-passes-A oscillation.

### New Types (`race_types.gd`)

```gdscript
class OvertakingConfig extends RefCounted:
    var enabled: bool = true
    var proximity_distance: float = 50.0      # how close to trigger interaction
    var overtake_speed_threshold: float = 2.0  # minimum speed advantage to pass (units/s)
    var held_up_speed_buffer: float = 0.1      # when held up, trail at this margin above car ahead
    var cooldown_seconds: float = 3.0          # post-overtake interaction suppression
    func clone() -> OvertakingConfig
```

Add to `RaceConfig`:

```gdscript
var overtaking: RaceTypes.OvertakingConfig = null  # null = no overtaking (phase-through)
```

Add to `CarState`:

```gdscript
var is_held_up: bool = false
var held_up_by: String = ""  # ID of car blocking this car
```

### New Module: `game/sim/src/overtaking_manager.gd`

```gdscript
class_name OvertakingManager extends RefCounted

var _config: OvertakingConfig
var _cooldowns: Dictionary = {}  # "carA:carB" -> expiry_race_time
var _is_enabled: bool = false

func configure(config: OvertakingConfig) -> void
func reset() -> void
func is_enabled() -> bool

func process_interactions(
    cars: Array[RaceTypes.CarState],
    track_length: float,
    race_time: float
) -> void
```

### The Algorithm (in `process_interactions`)

```
1. Clear all is_held_up flags on all cars.

2. Build sorted_cars: list of (car_index, total_distance)
   sorted by total_distance DESCENDING (leader first).

3. Process FRONT TO BACK (from leader toward back of pack):
   Skip the leader (position 0 in sorted list -- no one ahead to interact with).

   For each car B (starting from 2nd in sorted list):
     a. Find car A = the car directly ahead of B in the sorted list.

     b. If A.is_finished: skip (finished cars don't block).

     c. Compute track gap:
        track_gap = fposmod(A.distance_along_track - B.distance_along_track, track_length)

     d. If track_gap > proximity_distance: no interaction, continue.

     e. If track_gap <= 0: skip (same position or B is ahead -- tie case).

     f. Compute speed_delta = B.effective_speed - A.effective_speed

     g. If speed_delta <= 0: B is slower or equal. No interaction.

     h. Check cooldown: if pair (A.id, B.id) is in cooldown, skip.
        (During cooldown, both cars move at natural speed -- if B passes, it passes.)

     i. If speed_delta >= overtake_speed_threshold:
        -> OVERTAKE: B keeps its speed. Natural passing happens via distance update.
        -> Register cooldown for this pair.

     j. Else (speed_delta > 0 but < threshold):
        -> HELD UP: Set B.effective_speed = A.effective_speed + held_up_speed_buffer
        -> Set B.is_held_up = true, B.held_up_by = A.id
```

**Why front-to-back processing order**: When processing car C behind car B behind car A:
- First B checks against A -> B might get held up to A's speed.
- Then C checks against B -> C sees B's (possibly reduced) speed.
- This correctly creates "trains" of cars stuck behind a slow leader.
If we processed back-to-front, C would check against B's uncapped speed (stale data).

### Multi-Car Bunching (The Train Problem)

When 3+ cars are bunched within `proximity_distance` of each other:
- Front-to-back processing creates a correct "DRS train" effect.
- Car A (leader of the group) runs at natural speed.
- Car B is held up to A's speed (+ buffer).
- Car C is held up to B's speed (which is ~A's speed + buffer).
- The entire group moves at approximately A's pace.

This is realistic -- in F1, DRS trains form when multiple cars are within 1 second.

### Lapped Traffic

When the leader (lap 5) approaches a backmarker (lap 4):
- The leader has higher `total_distance`.
- In the sorted list, the leader appears before the backmarker.
- But on the TRACK, the backmarker might be directly ahead of the leader.

The **track gap** calculation handles this:

```gdscript
track_gap = fposmod(A.distance_along_track - B.distance_along_track, track_length)
```

This gives the physical distance on the circuit between the two cars, regardless of
which lap they're on. The `total_distance` comparison determines who is "ahead in the race."

Blue flags (letting leaders through) can be added later by reducing the
`overtake_speed_threshold` for leader-vs-backmarker interactions.

### The Cooldown System

```gdscript
func _get_cooldown_key(id_a: String, id_b: String) -> String:
    # Canonical key: alphabetical order so (A,B) == (B,A)
    return id_a + ":" + id_b if id_a < id_b else id_b + ":" + id_a

func _is_in_cooldown(id_a: String, id_b: String, race_time: float) -> bool:
    var key := _get_cooldown_key(id_a, id_b)
    return _cooldowns.has(key) and race_time < _cooldowns[key]

func _register_cooldown(id_a: String, id_b: String, race_time: float) -> void:
    _cooldowns[_get_cooldown_key(id_a, id_b)] = race_time + _config.cooldown_seconds
```

Periodically expire old entries (every ~120 chunks / 1 second) to prevent unbounded
dictionary growth.

### CRITICAL: Refactoring `_step_car_chunk` into Two Phases

The current `_step_car_chunk` computes speed AND applies distance in one pass per car.
This is wrong for overtaking -- all speeds must be known before any distances change.

**Refactor the chunk loop in `step()` from:**

```gdscript
for car in _cars:
    _step_car_chunk(car, chunk_start_time, chunk_dt)
```

**To:**

```gdscript
# Phase 1: Compute raw speed for each car
for car in _cars:
    if not _race_state_machine.is_car_racing(car):
        car.effective_speed_units_per_sec = 0.0
        continue
    _compute_car_speed(car)

# Phase 2: Overtaking interactions (modifies effective_speed on held-up cars)
if _overtaking_manager.is_enabled():
    _overtaking_manager.process_interactions(_cars, _runtime.track_length, _race_time)

# Phase 3: Apply distance and detect lap crossings
for car in _cars:
    if not _race_state_machine.is_car_racing(car):
        continue
    _apply_car_movement(car, chunk_start_time, chunk_dt)

# Phase 4: Update standings
for car in _cars:
    car.total_distance = float(car.lap_count) * _runtime.track_length + car.distance_along_track
StandingsCalculator.update_positions(_cars)
```

**`_compute_car_speed(car)` contains**: profile sampling + degradation multiplier +
speed floor. Everything that was in `_step_car_chunk` before the distance update.

**`_apply_car_movement(car, chunk_start_time, chunk_dt)` contains**: distance update +
lap crossing detection + lap registration. Everything after speed computation.

### Config Format

```json
{
  "overtaking": {
    "enabled": true,
    "proximity_distance": 50.0,
    "overtake_speed_threshold": 2.0,
    "held_up_speed_buffer": 0.1,
    "cooldown_seconds": 3.0
  }
}
```

If absent or `enabled: false` -> phase-through (V1/V1.1 backward compatible).

### HUD Changes

When `car.is_held_up == true`, add a `[H]` suffix to the speed column:
`"65.3 u/s [H]"`. Optional: highlight the row in yellow.

### Tests (`overtaking_manager_test.gd`)

| Test | What It Verifies |
|---|---|
| `test_no_interaction_when_disabled` | enabled=false -> no speed changes |
| `test_no_interaction_when_far_apart` | Beyond proximity -> no interaction |
| `test_held_up_below_threshold` | B 1 u/s faster within proximity -> B capped |
| `test_overtake_above_threshold` | B 5 u/s faster within proximity -> B keeps speed |
| `test_cooldown_prevents_re_interaction` | After overtake, pair has no interaction for cooldown |
| `test_cooldown_expires` | After cooldown_seconds, interaction resumes |
| `test_three_car_train` | C behind B behind A, all close -> C and B held up to A's pace |
| `test_lapped_traffic` | Leader approaches backmarker -> proximity detected correctly |
| `test_same_total_distance_no_crash` | Two cars at exact same position -> no error |
| `test_held_up_speed_matches_car_ahead` | B held up -> B.speed == A.speed + buffer |
| `test_finished_car_does_not_block` | Finished car skipped in interactions |
| `test_cooldown_key_is_symmetric` | (A,B) == (B,A) |
| `test_reset_clears_cooldowns` | After reset, all cooldowns gone |

Add to `race_simulator_test.gd`:

| Test | What It Verifies |
|---|---|
| `test_two_phase_step_produces_same_results_as_v1` | Without overtaking, refactored step matches original |
| `test_held_up_car_does_not_phase_through` | Two cars, slower ahead, faster behind but below threshold -> no passing |

### Guardrails

- **DO NOT modify positions in the overtaking manager.** The overtaking manager only
  modifies `effective_speed`. Positions are recomputed by `StandingsCalculator` after
  distances are applied. Separation of concerns.
- **DO NOT teleport cars.** An overtake means the faster car naturally passes because
  its speed is higher. The overtaking system only decides WHETHER to allow full speed
  or cap it. No distance swapping.
- **DO NOT process overtaking per-car in isolation.** All speeds must be computed first
  (Phase 1), THEN interactions resolved (Phase 2), THEN all distances applied (Phase 3).
- **DO NOT use `distance_along_track` alone for proximity.** Use the `fposmod` wrap-aware
  track gap to handle cars on different laps.
- **DO NOT forget to clear `is_held_up` flags at the start of each chunk.** Held-up
  status is recomputed every chunk.
- **DO NOT let the cooldown dictionary grow unbounded.** Expire old entries periodically.
- **DO NOT let held-up speed exceed the car's natural speed.** If `car_ahead` is faster,
  held-up logic must not apply (check `speed_delta > 0` first).
- **DO NOT process the leader.** The first car in the sorted list has no one ahead to
  interact with -- skip it.

### Error Scenarios

- Car A and B at exactly `proximity_distance`: include the boundary (`<=`).
- Wrap-around proximity: car A at distance 5, car B at distance (track_length - 3).
  `fposmod` correctly gives track gap of 8 units.
- All cars held up in a 20-car train: performance is O(N) per chunk since each car
  only checks the one car directly ahead. No O(N^2) issue.
- Overtaking during FINISHING state: racing cars can still overtake. Only `is_finished`
  cars are excluded.
- Two cars with the same speed within proximity: `speed_delta == 0` -> no interaction.
  They simply move together.

### Enhancement Possibilities

- **DRS zones**: track segments where `overtake_speed_threshold` is reduced.
- **Slipstream**: car behind gets a speed bonus when within proximity.
- **Defensive driving**: per-car "defense" rating increasing the threshold against them.
- **Wet weather**: `proximity_distance` increases, threshold changes.
- **Pit lane immunity**: cars in pit lane don't interact with on-track cars.

---

## Config Schema: `config/race_v2.json`

```json
{
  "schema_version": "2.0",
  "count_first_lap_from_start": true,
  "seed": 42,
  "default_time_scale": 1.0,
  "total_laps": 10,
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
  "degradation": {
    "warmup_laps": 0.5,
    "peak_multiplier": 1.0,
    "degradation_rate": 0.02,
    "min_multiplier": 0.7
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
      "degradation": {
        "warmup_laps": 0.3,
        "peak_multiplier": 1.0,
        "degradation_rate": 0.015,
        "min_multiplier": 0.75
      }
    },
    {
      "id": "car_02",
      "display_name": "Ferrari",
      "v_ref": 81.0
    },
    {
      "id": "car_03",
      "display_name": "Mercedes",
      "v_ref": 80.0,
      "degradation": {
        "warmup_laps": 0.5,
        "peak_multiplier": 1.0,
        "degradation_rate": 0.025,
        "min_multiplier": 0.65
      }
    },
    {
      "id": "car_04",
      "display_name": "McLaren",
      "v_ref": 79.0
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

Add `schema_version "2.0"` routing in `race_config_loader.gd`.

V2 reuses the V1.1 track parsing (`SpeedProfileConfig`). The V2 parse branch extends
V1.1 with: `total_laps`, `degradation` (global), `overtaking`, per-car `degradation`.

**Backward compatibility table:**

| Config version | total_laps | degradation | overtaking |
|---|---|---|---|
| 1.0 | 0 (unlimited) | null (none) | null (phase-through) |
| 1.1 | 0 (unlimited) | null (none) | null (phase-through) |
| 2.0 | from config | from config | from config |

File candidate order: `race_v2.json` -> `race_v1.1.json` -> `race_v1.json`.

---

## Global Guardrails (Apply to All Features)

1. **Sim/presentation boundary**: All new modules (`StandingsCalculator`,
   `RaceStateMachine`, `DegradationModel`, `OvertakingManager`) go in `game/sim/src/`.
   No Godot Node dependencies. No file I/O. Pure logic.

2. **Determinism**: All computations are fixed-step, seeded where randomness exists
   (none in V2), and produce identical results for identical inputs. No frame-dependent logic.

3. **Backward compatibility**: V1 and V1.1 configs must still work with zero changes.
   All new fields have safe defaults (0, null, false) that preserve existing behavior.

4. **Tests first**: Each new module gets its own test file. Existing tests must not break.
   Run the full suite after each feature branch.

5. **Config-driven**: No magic numbers in code. All tuning parameters live in JSON.

6. **Clone/reset discipline**: Every new field on `CarState` must be added to both
   `clone()` and `reset_runtime_state()`. Forgetting either causes subtle snapshot bugs
   or reset bugs. Verify this manually for every field you add.

7. **The `_cars` array in RaceSimulator is SACRED.** Never sort it, never reorder it,
   never remove elements. It stays in config order for the lifetime of the simulator.
   Position is a field on each car, not an array index.

---

## Things That Could Go Wrong (Error-Prone Areas)

### 1. The Two-Phase Refactor (Feature 4)

Splitting `_step_car_chunk` into `_compute_car_speed` + `_apply_car_movement` is the
highest-risk change. If any speed-related logic leaks into Phase 3 or any distance-related
logic leaks into Phase 1, results will differ from V1.1.

**Mitigation**: Before adding overtaking, write a regression test that runs the refactored
two-phase step WITHOUT overtaking and verifies identical `total_distance` and `lap_count`
results to the original single-pass implementation. Only then add overtaking.

### 2. Finish Detection vs. Standings Timing

`_register_lap_crossing` is called inside `_apply_car_movement` (Phase 3). But standings
are computed in Phase 4. This means the state machine sees the lap crossing BEFORE standings
are updated. The state machine must use `car.lap_count` (already incremented in Phase 3),
not `car.position`, to determine if the leader has finished.

**Mitigation**: In `on_lap_completed`, check `car.lap_count >= total_laps` directly.
Do not check `car.position == 1`. Position may be stale at that point.

### 3. Cooldown Key Symmetry

If cooldown key for (A, B) is different from (B, A), the cooldown only applies in one
direction, and oscillation still happens.

**Mitigation**: Always sort the two IDs alphabetically before building the key.
Write a specific test: `test_cooldown_key_is_symmetric`.

### 4. Track Gap Wrap-Around

If car A is at distance 1 and car B is at distance (track_length - 1), the naive
gap `A - B` is negative. `fposmod` fixes this but it must be used correctly.

**Mitigation**: The proximity calculation is:
```gdscript
var track_gap := fposmod(ahead.distance_along_track - behind.distance_along_track, track_length)
```
Write a test specifically for the wrap-around case.

### 5. Degradation + Overtaking Interaction

A car whose degradation is severe might be held up AND degrading simultaneously.
Its effective speed should be: `min(held_up_speed, degraded_speed)`. The order of
application matters: degradation is applied in Phase 1 (speed computation), overtaking
caps in Phase 2. So degradation is already baked into the speed that the overtaking
manager sees. This is correct -- a degraded car's speed advantage over the car ahead
is naturally smaller, making overtakes harder. No special handling needed.

### 6. Finished Cars in Standings

A finished car should retain its finish position even as other cars continue racing.
The standings calculator should NOT demote a finished car's position. Finished cars'
`total_distance` is frozen (they stop moving), so the standings calculator will naturally
keep them behind racing cars that pass them in total_distance.

**But wait**: the finish_position and the live position are different concepts.
`car.finish_position` (from the state machine) is the finishing order.
`car.position` (from standings calculator) is the live race position.
A finished P1 car's `car.position` might become 3 if two cars pass its frozen distance.
The HUD should display `finish_position` for finished cars, not `position`.

**Mitigation**: In the HUD, if `car.is_finished`, show `car.finish_position` in the P column
and display `car.finish_time` delta from winner in the Gap column.

---

## Verification Checklist

### Per-Feature

**F1 (Standings):**
- [ ] `position` and `total_distance` on CarState with clone/reset
- [ ] StandingsCalculator module with update_positions
- [ ] Simulator calls update_positions after each chunk
- [ ] HUD sorted by position with P and Gap columns (gap in seconds)
- [ ] All 8 standings tests pass
- [ ] Existing tests pass (no regressions)

**F2 (Race End):**
- [ ] RaceState enum and finish fields on CarState
- [ ] total_laps on RaceConfig, parsed in config loader
- [ ] RaceStateMachine with full state transitions
- [ ] Simulator integrates state machine: skip finished, stop after FINISHED
- [ ] Snapshot includes race_state and finish_order
- [ ] HUD shows race state and finish results
- [ ] Auto-pause on FINISHED
- [ ] All 10+ state machine tests pass
- [ ] V1/V1.1 configs still work (unlimited laps)

**F3 (Degradation):**
- [ ] DegradationConfig type with clone
- [ ] DegradationModel.compute_multiplier (stateless)
- [ ] Global + per-car config with fallback chain
- [ ] Applied in speed computation, floored at 0.001
- [ ] HUD Deg column showing percentage
- [ ] All 10 degradation tests pass
- [ ] No degradation config -> multiplier 1.0 (backward compatible)

**F4 (Overtaking):**
- [ ] OvertakingConfig type with clone
- [ ] OvertakingManager with process_interactions
- [ ] Two-phase refactor of _step_car_chunk
- [ ] Front-to-back processing for correct train behavior
- [ ] Track-gap proximity with fposmod wrap-around
- [ ] Cooldown system with symmetric keys
- [ ] HUD held-up indicator
- [ ] All 13+ overtaking tests pass
- [ ] Regression test: two-phase step without overtaking == original results
- [ ] No overtaking config -> phase-through (backward compatible)

### End-to-End Manual Verification

1. Run with `race_v2.json`, 10 laps, 4 cars with different v_ref and degradation.
2. HUD shows live positions updating as faster cars catch slower ones.
3. Gaps shown in seconds, updating in real-time.
4. Cars bunch up behind slower cars (held-up trains visible).
5. Overtakes happen when speed advantage is sufficient.
6. Degradation visible: cars start slower, peak around lap 1, gradually slow.
7. Race ends after leader completes 10 laps.
8. Other cars finish as they cross the line.
9. Final standings displayed. Auto-pause.
10. Reset -> everything restored to starting state.
11. Switch to `race_v1.1.json` -> still works (no standings sorting, no end, no degradation).
