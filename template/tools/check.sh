#!/usr/bin/env bash
# Type-check (strict) + lint src/ and tests/. Prints "OK" when clean, otherwise one line per problem.
# Usage: bash tools/check.sh [--fix]   (--fix also formats with StyLua)
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"

dirs=()
for d in src tests; do
	if find "$d" -name '*.luau' -o -name '*.lua' 2>/dev/null | grep -q .; then dirs+=("$d"); fi
done
if [ ${#dirs[@]} -eq 0 ]; then echo "OK (no scripts)"; exit 0; fi

[ "${1:-}" = "--fix" ] && stylua "${dirs[@]}" >/dev/null 2>&1
if [ ! -f globalTypes.d.luau ]; then
	curl -fsSL -o globalTypes.d.luau \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.PluginSecurity.d.luau \
		|| { echo "could not download Roblox type definitions (offline?)"; exit 2; }
fi
rojo sourcemap default.project.json -o sourcemap.json >/dev/null 2>&1

root="$(pwd -W 2>/dev/null || pwd)"
out="$(
	{
		luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --formatter=plain "${dirs[@]}" 2>&1
		selene --display-style=quiet "${dirs[@]}" 2>&1
	} | tr '\\' '/' \
		| awk -v r="$root/" 'BEGIN { r = tolower(r) } { if (index(tolower($0), r) == 1) $0 = substr($0, length(r) + 1); print }' \
		| sed -e 's# \[game/[^]]*\]##' \
		| grep -vE '^\[(INFO|WARN)\]|^Results:|^[0-9]+ (errors|warnings|parse errors)|^[[:space:]]*$' \
		| sort -u
)"
if [ -n "$out" ]; then echo "$out"; exit 1; fi
echo "OK"
