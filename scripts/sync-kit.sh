#!/usr/bin/env bash
# Update only managed files, keeping previous versions under .moonbrick/backups/.
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/scripts/python.sh"
moonbrick_python "$kit/scripts/project.py" sync "${1:?usage: sync-kit.sh <project-dir>}"
