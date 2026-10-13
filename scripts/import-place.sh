#!/usr/bin/env bash
# Stage syncback, validate, then promote. Never delete code or stage unrelated git changes.
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/scripts/python.sh"
export PATH="$HOME/.rokit/bin:$PATH"
moonbrick_python "$kit/scripts/project.py" import "${1:?usage: import-place.sh <fresh-project> <place-file>}" "${2:?place file required}"
