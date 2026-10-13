#!/usr/bin/env bash
# SessionStart: no writes or output outside Moonbrick projects.
set -u
cat >/dev/null
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$dir/default.project.json" ] && [ -f "$dir/tools/MCPKit.luau" ] || exit 0
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/scripts/python.sh"
export PATH="$HOME/.rokit/bin:$PATH"
moonbrick_python "$kit/scripts/dev-server.py"
