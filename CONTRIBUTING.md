# Contributing

## Workflow

1. Branch from `main` using `feat/*`, `fix/*`, or `chore/*`.
2. Keep commits focused and atomic.
3. Open a pull request into `main`.
4. Ensure code review and checks pass before merge.

## Release flow

1. Merge approved pull requests into `main`.
2. Create `rc-vX.Y.Z-N` tags on `main` for UAT candidates.
3. Create `vX.Y.Z` tags on `main` for production releases.

## Commit style

Use Conventional Commits when possible:

- `feat: add race strategy model`
- `fix: handle safety car lap edge case`
- `chore: update tooling`

## Pull requests

- Include a clear summary and testing notes.
- Link any related issue/ticket.
- Prefer squash merge to keep history clean.
