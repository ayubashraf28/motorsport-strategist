# Motorsport Strategist: Current Business State

## 1. Product Positioning

Motorsport Strategist is currently a **playable prototype foundation** for a motorsport management game.

The current build demonstrates:
- Deterministic race simulation integrity
- Config-driven race behavior tuning
- Live race presentation with standings and finish outcomes
- Extensible architecture for future management mechanics

This is not yet a full manager game; it is a robust simulation-and-visualization base for one.

## 2. Delivered Business Value by Version

### V0 (Prototype Foundation)
- Established a runnable race loop with lap timing and visualized cars.
- Proved deterministic simulation + Godot presentation separation.
- Created initial confidence that race math can be trusted.

### V1 (Data-Driven Pace Behavior)
- Added pace profile segmentation and smooth transitions.
- Improved visible realism without sacrificing determinism.
- Enabled non-code tuning through JSON config changes.

### V1.1 (Physics-Derived Speed)
- Replaced hand-authored multipliers with curvature/physics-based speed constraints.
- Introduced reusable track asset pipeline (Monza derived geometry).
- Reduced manual tuning burden for new tracks.

### V2 (Race Dynamics and Outcome)
- Added race positions and interval logic (live standings).
- Added finite race states and finish ordering.
- Added degradation model (performance changes over race distance).
- Added overtaking/held-up/cooldown interactions.
- Upgraded HUD to surface race-critical information.

Business meaning:
- The product now demonstrates an actual race experience, not only a moving-track demo.

## 3. Current Feature Set (Externally Observable)

From a user/stakeholder perspective, the current prototype supports:
- Start/run/pause/reset race session
- Speed controls (`1x`, `2x`, `4x`)
- Car progression with lap counting, last/best/current lap timings
- Position board with interval-style gap display
- Degradation percentage visibility
- Race completion and final order behavior
- Debug visualizations for pace, curvature, and speed profiles

## 4. Target Audience (Current Stage)

Primary immediate audience:
- Internal product/engineering stakeholders validating simulation direction
- Designers tuning race behavior through config
- Technical collaborators onboarding to future features

Secondary future audience:
- End players of a motorsport manager-style title (not yet addressed fully)

## 5. Operating Model and Governance

Defined governance model in repository standards:
- Protected `main`, PR-only merge policy
- Required PR check context: `guardrails`
- Branch naming and release tagging conventions
- Squash-merge preference for clean history

Current process readiness:
- CI/CD workflows for PR, main artifacts, RC, and production tags are implemented.
- Dependabot for GitHub Actions is configured weekly.

Gaps:
- `CODEOWNERS` is placeholder-only and needs real owner mapping.

## 6. Release and Environment Strategy (Business View)

Environment flow:
- Dev delivery: artifacts on `main` pushes (`build-main`)
- UAT delivery: `rc-vX.Y.Z-N` prerelease flow
- Production delivery: `vX.Y.Z` release flow

This supports a controlled promotion model (dev -> UAT -> prod) even while product scope is still prototype-stage.

Current status:
- Workflow infrastructure exists.
- No release tags currently exist, so UAT/prod release paths have not yet been exercised in this repo state.

## 7. Strategic Strengths

1. Deterministic simulation core lowers regression risk and supports reproducible balancing.
2. Clear boundary between simulation and presentation reduces future rework.
3. Versioned config schema allows backward compatibility while adding capability.
4. ADR + architecture documentation discipline is already present.
5. Feature trajectory aligns with motorsport management gameplay needs.

## 8. Current Business Risks

1. Documentation drift risk:
   - Root README still frames V1.1 as current baseline while runtime defaults to V2 config.
2. Ownership and continuity risk:
   - Missing CODEOWNERS can slow approvals and increase key-person dependency.
3. Tooling friction risk for contributors:
   - Local Windows environments without `bash` cannot run CI helper scripts directly.
4. Product-perception risk:
   - Prototype currently focuses on race dynamics; broader manager-loop systems are not yet implemented.

## 9. Scope Completed vs. Scope Not Yet Implemented

Completed core scope:
- Deterministic lap-timing engine
- Pace + physics speed models
- Track geometry data ingestion
- Standings, race finish flow, degradation, overtaking
- Basic HUD and debug overlays
- CI and release pipeline foundation

Not yet implemented (major manager-game capabilities):
- Pit stops and tire compounds
- Fuel strategy
- Weather systems
- Safety car/flags/regulation events
- Team/driver management loop (contracts, finances, development)
- Telemetry persistence and analytical dashboards
- Multiplayer/networked race operations

## 10. Recommended Immediate Priorities (Handoff Ready)

1. Update high-level product docs (`README.md`) to reflect V2 runtime baseline.
2. Finalize ownership model (`CODEOWNERS`) to match protected-branch process.
3. Add local PowerShell equivalents for CI scripts or require Git Bash explicitly in onboarding docs.
4. Define next gameplay milestone (for example: pit-stop/tyre strategy) with ADR + plan before implementation.
5. Start business KPI definitions for prototype progression (race completion rate, overtake frequency, lap-time spread, balance stability).

## 11. Handoff Summary

The project is in a strong technical prototype phase with production-leaning engineering discipline.
It already supports realistic race-flow simulation behaviors and operational CI/release patterns.
The next phase should focus on expanding from race simulation into full manager-loop gameplay systems while preserving deterministic core quality.
