#!/usr/bin/env bash
set -euo pipefail

if [[ -f "game/project.godot" ]]; then
  echo "[test] Godot simulation tests are executed in CI via gdUnit4-action"
fi

if [[ -f "sim/pyproject.toml" || -f "sim/requirements.txt" ]]; then
  echo "[test] python project detected in sim/"
  python -m pytest sim/tests
  exit 0
fi

if [[ -f "sim/package.json" ]]; then
  echo "[test] node project detected in sim/"
  npm ci --prefix sim
  npm test --prefix sim -- --ci
  exit 0
fi

echo "[test] no local sim test runner configured, skipping"
