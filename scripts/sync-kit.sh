#!/usr/bin/env bash
# Copy moonbrick's Luau code (MCPKit, libraries, library tests) into a project, replacing older copies.
# Game code is never touched: only tools/MCPKit.luau, src/kit/** and tests/kit/** are written.
# Usage: bash sync-kit.sh <project-dir>
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
project="${1:?usage: sync-kit.sh <project-dir>}"
version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$kit/.claude-plugin/plugin.json")"

mkdir -p "$project/tools" "$project/src/kit/shared" "$project/src/kit/server" "$project/tests/kit"
cp "$kit/luau/MCPKit.luau" "$project/tools/MCPKit.luau"
cp "$kit/template/tools/check.sh" "$project/tools/check.sh"
cp -R "$kit/luau/lib/shared/." "$project/src/kit/shared/"
cp -R "$kit/luau/lib/server/." "$project/src/kit/server/"
cp "$kit/template/src/kit/server/DebugHooks.luau" "$kit/template/src/kit/server/DevTools.server.luau" "$project/src/kit/server/"
cp -R "$kit/luau/tests/." "$project/tests/kit/"
echo "$version" >"$project/tools/.moonbrick-version"
echo "moonbrick $version synced into $project"
