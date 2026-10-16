#!/usr/bin/env bash
# Copy every recipe into a fresh scaffold and run the project's strict check + Rojo build.
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
dir="${1:-$kit/.artifacts/recipes-check}"
rm -rf "$dir"
bash "$kit/scripts/new-project.sh" "$dir" recipes-check --no-tools >/dev/null
for recipe in "$dir"/tools/recipes/*/; do
  for side in server client shared; do
    if [ -d "$recipe$side" ]; then cp "$recipe$side"/*.luau "$dir/src/$side/"; fi
  done
done
cd "$dir"
bash tools/check.sh
rojo build default.project.json -o recipes.rbxlx >/dev/null
echo "recipes OK"
