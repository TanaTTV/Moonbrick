#!/usr/bin/env bash
# Fail closed: tool exit codes are authoritative, even when diagnostics are empty.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
export PATH="$HOME/.rokit/bin:$PATH"
case "${1:-}" in ''|--fix) ;; *) echo 'usage: bash tools/check.sh [--fix]' >&2; exit 2 ;; esac

dirs=()
for d in src tests; do
	if [ -d "$d" ] && [ -n "$(find "$d" -type f \( -name '*.luau' -o -name '*.lua' \) -print -quit)" ]; then dirs+=("$d"); fi
done
[ -f tools/MCPKit.luau ] && dirs+=(tools/MCPKit.luau)
if [ ${#dirs[@]} -eq 0 ]; then echo 'OK (no scripts)'; exit 0; fi
for tool in rojo luau-lsp selene; do
	command -v "$tool" >/dev/null 2>&1 || { echo "error: missing $tool; run setup-tools.sh" >&2; exit 2; }
done
tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
if [ "${1:-}" = --fix ]; then
	command -v stylua >/dev/null 2>&1 || { echo 'error: missing stylua' >&2; exit 2; }
	stylua "${dirs[@]}" >"$tmp/format" 2>&1 || { cat "$tmp/format"; echo 'error: stylua failed'; exit 2; }
fi
if [ ! -s globalTypes.d.luau ]; then
	curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp/types" \
		https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau \
		&& [ -s "$tmp/types" ] || { echo 'error: could not download Roblox definitions'; exit 2; }
	mv "$tmp/types" globalTypes.d.luau || exit 2
fi
rojo sourcemap default.project.json -o "$tmp/sourcemap.json" >"$tmp/rojo" 2>&1 \
	&& [ -s "$tmp/sourcemap.json" ] || { cat "$tmp/rojo"; echo 'error: rojo sourcemap failed'; exit 2; }
mv "$tmp/sourcemap.json" sourcemap.json || exit 2

luau_status=0; lint_status=0
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --formatter=plain "${dirs[@]}" >"$tmp/types-out" 2>&1 || luau_status=$?
selene --display-style=quiet "${dirs[@]}" >"$tmp/lint-out" 2>&1 || lint_status=$?
root="$(pwd -W 2>/dev/null || pwd)"
out="$(cat "$tmp/types-out" "$tmp/lint-out" | tr '\\' '/' \
	| awk -v r="$root/" 'BEGIN { r = tolower(r) } { if (index(tolower($0), r) == 1) $0 = substr($0, length(r) + 1); print }' \
	| sed -e 's# \[game/[^]]*\]##' \
	| grep -vE '^\[(INFO|WARN)\]|^Results:|^[0-9]+ (errors|warnings|parse errors)|^[[:space:]]*$' | awk '!seen[$0]++')"
# Keep multi-line diagnostics in order, and cap the output so one broken file can't flood the session.
if [ -n "$out" ]; then
	total="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
	printf '%s\n' "$out" | head -n 40
	[ "$total" -le 40 ] || echo "... $((total - 40)) more lines; fix the first errors and re-run"
fi
if [ "$luau_status" -ne 0 ] || [ "$lint_status" -ne 0 ]; then
	echo "error: luau-lsp exit=$luau_status; selene exit=$lint_status"
	[ -n "$out" ] || cat "$tmp/types-out" "$tmp/lint-out"
	exit 1
fi
[ -z "$out" ] || exit 1
echo OK
