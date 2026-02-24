#!/usr/bin/env bash
set -euo pipefail

echo "[lint] scanning for unresolved merge conflict markers"
if git grep -nE '^(<<<<<<<|=======|>>>>>>>)' -- .; then
  echo "[lint] failed: merge conflict markers found"
  exit 1
fi

echo "[lint] baseline checks passed"
