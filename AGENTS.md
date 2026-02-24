# AGENTS.md

Repository working rules for all future implementation.

## Non-negotiable standards

1. Protection-first delivery
- Use short-lived branches and pull requests into `main`.
- Keep required checks green before merge.
- Do not bypass branch protection unless explicitly approved for an emergency.

2. Production-ready code and comments
- Write production-ready code by default.
- Add clear comments for non-obvious logic, assumptions, edge cases, and constraints.
- Keep comments useful: explain intent and tradeoffs, not obvious syntax.

3. File and folder discipline
- Do not add random files to the repository root unless root placement is required by convention.
- Place new files in the correct domain folder (`sim/`, `game/`, `tools/`, `docs/`, `config/`).
- For every new folder or subsystem, include a short `README.md` describing purpose and ownership.

4. UI/UX quality bar
- Follow strong UI/UX standards: responsive layouts, accessibility, clarity, and consistent interaction patterns.
- Reuse component systems and design primitives when available.
- Validate states (loading, empty, error, success) and keyboard/navigation behavior.

5. Library usage policy
- Prefer proven libraries for common problems instead of re-implementing everything manually.
- Select libraries based on maintenance quality, security posture, license, and fit.
- Keep dependency choices intentional and documented when they affect architecture.

## Engineering expectations

- Keep modules cohesive and avoid mixed responsibilities.
- Add or update tests whenever behavior changes.
- Keep scripts deterministic and CI-friendly.
- Update docs when structure, architecture, or workflow changes.

## Baseline repository layout

- `sim/`: deterministic simulation domain logic and tests
- `game/`: game/client presentation, scenes, UI, and assets
- `tools/`: automation, CI helpers, and developer scripts
- `docs/`: architecture, decisions (ADR), and UI/UX documentation
- `config/`: shared configuration templates and environment examples
