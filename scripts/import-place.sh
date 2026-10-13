#!/usr/bin/env bash
# Import a place file into a roblox-kit project with Rojo syncback.
# Usage: bash import-place.sh <project-dir> <place.rbxl|place.rbxlx>
#
# Layout after import: each service's existing content lives under src/<Service>/ and the Kit is mounted
# alongside it. Workspace parts, terrain and lighting stay in the place file.
set -euo pipefail
project="${1:?usage: import-place.sh <project-dir> <place-file>}"
place="${2:?usage: import-place.sh <project-dir> <place-file>}"
export PATH="$HOME/.rokit/bin:$PATH"
[ -f "$place" ] || { echo "error: place file not found: $place"; exit 1; }
place="$(cd "$(dirname "$place")" && pwd)/$(basename "$place")"
cd "$project"
name="$(grep -m1 '"name"' default.project.json | sed 's/.*"name"[^"]*"\([^"]*\)".*/\1/')"

# Services to import. Nested entries use "Parent/Child".
entries="ServerScriptService ReplicatedStorage ReplicatedFirst ServerStorage StarterGui StarterPlayer/StarterPlayerScripts StarterPlayer/StarterCharacterScripts"

has() { case " $entries " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Emit a project file for the remaining entries; with kit=1 also mount the Kit folders.
project_json() {
	local kit="$1" first=1 sp=""
	printf '{\n  "name": "%s",\n  "tree": {\n    "$className": "DataModel"' "$name"
	for e in $entries; do
		case "$e" in
		StarterPlayer/*) sp="$sp ${e#StarterPlayer/}" ;;
		*)
			printf ',\n    "%s": {\n      "$path": "src/%s"' "$e" "$e"
			if [ "$kit" = 1 ]; then
				case "$e" in
				ServerScriptService) printf ',\n      "Kit": { "$path": "src/kit/server" }' ;;
				ReplicatedStorage) printf ',\n      "Kit": { "$path": "src/kit/shared" }' ;;
				ServerStorage) printf ',\n      "MCPKit": { "$path": "tools/MCPKit.luau" },\n      "Tests": { "$path": "tests" }' ;;
				esac
			fi
			printf '\n    }'
			;;
		esac
	done
	if [ -n "$sp" ]; then
		printf ',\n    "StarterPlayer": {'
		for c in $sp; do
			[ $first = 1 ] && first=0 || printf ','
			printf '\n      "%s": { "$path": "src/StarterPlayer/%s" }' "$c" "$c"
		done
		printf '\n    }'
	fi
	if [ "$kit" = 1 ] && ! has ServerScriptService; then
		printf ',\n    "ServerScriptService": { "Kit": { "$path": "src/kit/server" } }'
	fi
	if [ "$kit" = 1 ] && ! has ReplicatedStorage; then
		printf ',\n    "ReplicatedStorage": { "Kit": { "$path": "src/kit/shared" } }'
	fi
	if [ "$kit" = 1 ] && ! has ServerStorage; then
		printf ',\n    "ServerStorage": { "MCPKit": { "$path": "tools/MCPKit.luau" }, "Tests": { "$path": "tests" } }'
	fi
	printf '\n  }\n}\n'
}

rm -rf src/server src/client src/shared src/world # template folders unused in this layout
for e in $entries; do mkdir -p "src/$e"; done

# Syncback can't add project entries the place lacks; drop each one it reports and retry.
for _ in 1 2 3 4 5 6 7 8; do
	project_json 0 >default.project.json
	if out="$(rojo syncback default.project.json --input "$place" --non-interactive 2>&1)"; then
		break
	fi
	missing="$(printf '%s' "$out" | sed -n "s/.*The child '\([^']*\)' of Instance '\([^']*\)' is present only in a project file.*/\2\/\1/p" | head -1)"
	[ -n "$missing" ] || { printf '%s\n' "$out" | tail -5; exit 1; }
	child="${missing#*/}"
	parent="${missing%%/*}"
	if [ "$parent" = StarterPlayer ]; then
		entries="$(printf '%s\n' $entries | grep -vx "StarterPlayer/$child" | tr '\n' ' ')"
	elif [ "$child" = StarterPlayer ]; then
		entries="$(printf '%s\n' $entries | grep -v '^StarterPlayer/' | tr '\n' ' ')"
	else
		entries="$(printf '%s\n' $entries | grep -vx "$child" | tr '\n' ' ')"
	fi
	rm -rf "src/$child" "src/StarterPlayer/$child"
done

# Kit-managed items that came along from the place (e.g. re-importing a kit project) are replaced by the mounts.
rm -rf src/ServerScriptService/Kit* src/ReplicatedStorage/Kit* src/ServerStorage/MCPKit* src/ServerStorage/Tests*
project_json 1 >default.project.json
for e in $entries; do [ -n "$(ls -A "src/$e" 2>/dev/null)" ] || touch "src/$e/.gitkeep"; done
[ -d src/StarterPlayer ] && [ -z "$(ls -A src/StarterPlayer)" ] && rmdir src/StarterPlayer

rojo sourcemap default.project.json -o sourcemap.json >/dev/null # validates the final project
git add -A
git commit -q -m "Import $(basename "$place")" || true
echo "Imported $(find src -name '*.lua*' -not -path 'src/kit/*' | wc -l | tr -d ' ') scripts from $(basename "$place") (services: $entries)"
