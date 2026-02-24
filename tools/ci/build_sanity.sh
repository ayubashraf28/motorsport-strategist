#!/usr/bin/env bash
set -euo pipefail

for required_dir in sim game tools; do
  if [[ ! -d "$required_dir" ]]; then
    echo "[build-sanity] missing required directory: $required_dir"
    exit 1
  fi
done

if [[ -f "tools/ci/build_sanity_custom.sh" ]]; then
  echo "[build-sanity] running custom project sanity checks"
  bash tools/ci/build_sanity_custom.sh
  exit 0
fi

echo "[build-sanity] baseline checks passed"
