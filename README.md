# motorsport-strategist

Production-ready repository bootstrap for a `main` + environments workflow.

## Branching and release model

- `main`: always releasable, protected branch
- Feature branches: `feat/*`, `fix/*`, `chore/*`
- UAT candidates: tags `rc-vX.Y.Z-N` from `main`
- Production releases: tags `vX.Y.Z` from `main`

## Environments

- `dev`: build artifacts for internal testing on every merge to `main`
- `uat`: release candidate artifacts from `rc-vX.Y.Z-N` tags
- `prod`: stable release artifacts from `v*` tags

## Repository layout

- `sim/`: deterministic simulation logic and tests
- `game/`: Godot project and assets
- `tools/`: CI helpers and local automation scripts
