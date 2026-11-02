#!/usr/bin/env bash
# Hook entry point. Fails open: every path exits 0, and a bug can only mean no hook output.
# These run across all of the user's projects, so drop irrelevant events here, before starting Python.
# Builtins only on the common paths: each fork costs tens of milliseconds under Git Bash.
event="${1:-}"
IFS= read -r -d '' input
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
in_project() { [ -f "$dir/default.project.json" ] && [ -f "$dir/tools/MCPKit.luau" ]; }

shopt -s nocasematch
case "$event" in
prompt)
	[[ "$input" =~ roblox|luau|rojo ]] || exit 0
	;;
post-tool)
	# Studio and Blender tools can run from any folder; everything else matters only in a project.
	case "$input" in
	*.luau* | *tools/check.sh* | *'"mcp__Roblox'* | *'"mcp__blender'*) ;;
	*) in_project || exit 0 ;;
	esac
	;;
esac
shopt -u nocasematch

self="${BASH_SOURCE[0]//\\//}" # CLAUDE_PLUGIN_ROOT has backslashes on Windows
script="${self%/*}/moonbrick_hooks.py"
# moonbrick_hooks.py always exits 0, so anything else (the Microsoft Store stub, an ancient Python) means try the next.
for candidate in python3 python py; do
	command -v "$candidate" >/dev/null 2>&1 || continue
	# -S skips site-packages for a faster start; -E ignores the user's Python environment.
	"$candidate" -E -S -X utf8 "$script" "$event" <<<"$input" 2>/dev/null && exit 0
done
exit 0
