# Motorsport Strategist: Current Business State

## 1. Product Positioning

Motorsport Strategist is currently a **playable race-strategy prototype** for a motorsport management game.

The current build demonstrates:
- Deterministic race simulation integrity
- Config-driven balancing and strategy tuning
- Tyre compound and degradation strategy tradeoffs
- Fuel and pit-stop decision impact
- Post-race telemetry capture for analysis

This is still not a full manager game loop, but the race operations layer is now materially deeper than a pure movement demo.

## 2. Delivered Business Value by Version

### V0 (Prototype Foundation)
- Runnable race loop and lap timing visualization.
- Established simulation/presentation separation.

### V1 (Data-Driven Pace)
- Pace profile segmentation and smoothing.
- Non-code race feel tuning from JSON.

### V1.1 (Physics-Derived Speed)
- Curvature/vehicle-limited speed modeling.
- Reusable track asset pipeline from real track data.

### V2 (Race Dynamics)
- Live standings and interval logic.
- Finite race lifecycle and finish order.
- Degradation and overtaking interactions.

### V3 (Strategy Layer)
- Tyre compounds and stint tracking.
- Fuel model (consumption, penalties, refuel).
- Pit stop lifecycle and player pit requests.

### V3.1 (Realism and Analysis)
- Improved tyre behavior shape and telemetry semantics.
- Distance-based pit lane movement behavior.
- JSONL lap snapshot and pit-event telemetry for offline analysis.

### V3.2 (Game Experience and Presentation)
- Full game flow: main menu → race setup → race → results screen.
- F1 Manager-inspired timing tower HUD with cycling data modes (interval, last lap, tyre, fuel).
- Track/UI layer separation with auto-fit rotation and scaling for all circuits.
- Multi-track support: 5 circuits (Monza, Spa, Silverstone, Suzuka, Interlagos).
- Team registry and team colors from config.
- AI strategy controller for automated pit decisions.
- 8-car grid support.

Business meaning:
- The prototype now feels like a game rather than a simulation debug tool. Players navigate menus, choose tracks and teams, watch races with a professional HUD, and see results — a complete session loop.

## 3. Current Feature Set (Externally Observable)

From a stakeholder/player perspective, the prototype currently supports:
- Main menu → race setup → race → results game flow
- Track selection from 5 real-world circuits (Monza, Spa, Silverstone, Suzuka, Interlagos)
- Team selection with color-coded car identification
- 8-car grids with AI strategy for non-player pit decisions
- Start/run/pause/reset race session with time controls (`1x`, `2x`, `4x`)
- F1-style timing tower with cycling data views (interval, last lap, tyre status, fuel level)
- Tyre compounds, stint counters, and pit request workflow
- Fuel simulation with weight-based performance impact
- Pit stop transitions (entry, stop, exit) and compound swaps
- Tracks auto-rotate and scale to fit the viewport naturally
- Post-race results screen with finish order
- Debug overlays for pace/curvature/speed (toggle with `D`)
- Telemetry files for lap snapshots and pit lifecycle events

## 4. Target Audience (Current Stage)

Primary current audience:
- Internal product/engineering stakeholders validating race strategy direction
- Designers balancing tyres, fuel, pit behavior via config
- Technical collaborators onboarding to simulation and telemetry outputs

Secondary future audience:
- End players of a motorsport manager-style game

## 5. Operating Model and Governance

Defined repository governance:
- Protected `main`, PR-only merges
- Required PR check context: `guardrails`
- Branch naming and release tag conventions
- Squash-merge preference for clean history

Current process readiness:
- CI/CD workflows for PR, main artifacts, RC, and production tags exist
- Dependabot for GitHub Actions is configured

Gap still present:
- `CODEOWNERS` is placeholder-only and should be finalized

## 6. Release and Environment Strategy

Environment flow:
- Dev delivery: artifacts on `main` pushes (`build-main`)
- UAT delivery: `rc-vX.Y.Z-N` prerelease flow
- Production delivery: `vX.Y.Z` release flow

This supports controlled promotion from dev to UAT to production once release cadence begins.

## 7. Strategic Strengths

1. Deterministic simulation supports reproducible balancing and confidence in regressions.
2. Config-first behavior tuning reduces engineering bottlenecks for gameplay iteration.
3. Telemetry gives a concrete analysis loop for strategy and balancing decisions.
4. Clear sim/presentation/UI layer separation keeps future feature growth manageable.
5. Versioned schema support preserves backward compatibility while expanding capability.
6. Multi-track support with auto-fit means new circuits can be added without UI/layout rework.
7. Complete session flow (menu → setup → race → results) makes the product demonstrable to stakeholders.

## 8. Current Business Risks

1. Documentation drift risk remains as race systems evolve quickly; product and technical docs can diverge without routine upkeep.
2. Ownership/process risk remains until `CODEOWNERS` is real.
3. Tooling friction can slow contributors who do not have full local Godot CLI/testing setup.
4. Telemetry data exists but lacks first-party reporting dashboards/scripts in-repo.
5. Product perception risk: race strategy depth improved, but broader management loop systems are still not implemented.

## 9. Scope Completed vs Scope Not Yet Implemented

Completed core scope:
- Deterministic lap timing and race progression
- Pace + physics speed models
- Standings and finish-state lifecycle
- Tyre degradation and overtaking interactions
- Tyre compounds and stint tracking
- Fuel model and pit stop mechanics
- Pit strategy request flow and HUD integration
- Telemetry logging for lap and pit lifecycle analysis
- CI and release pipeline foundation
- Full game flow (menus, setup, race, results)
- F1-style timing tower with cycling data modes
- Multi-track support (5 circuits) with auto-fit rotation/scaling
- Team registry and color-coded identification
- AI strategy controller for automated pit decisions
- 8-car grid support

Not yet implemented (major manager-game capabilities):
- Weather systems and dynamic track conditions
- Safety car, flags, and regulation event systems
- Team/driver management loop (contracts, budget, development)
- Longitudinal season mode and persistence
- In-product telemetry analysis tooling/dashboard
- Multiplayer/network race operations
- Player-controlled car strategy beyond pit compound cycling

## 10. Recommended Immediate Priorities

1. Add lightweight telemetry analysis tooling (`tools/`) for repeatable balancing reports.
2. Finalize `CODEOWNERS` to align governance with branch protection goals.
3. Define the next gameplay milestone beyond race operations (for example weather + safety car).
4. Define KPI tracking for balancing quality (compound crossover lap, pit-loss distribution, race variance).
5. Plan observability improvements for live race debugging beyond JSONL export.

## 11. Handoff Summary

The project has progressed from race simulation baseline into an early but complete race session experience.
The prototype now has a full game flow, professional-quality HUD, multi-track support, and AI opponents — making it demonstrable as a product rather than a debug tool.
The next phase should prioritize management-loop depth (team/driver systems, season mode) and analytics tooling while preserving deterministic simulation quality.
