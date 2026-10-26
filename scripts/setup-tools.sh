#!/usr/bin/env bash
# Install the toolchain for a moonbrick project (run from the project root):
# Rokit (if missing) -> rojo, luau-lsp, selene, StyLua from rokit.toml -> Rojo Studio plugin -> Roblox type definitions.
set -euo pipefail
export PATH="$HOME/.rokit/bin:$PATH"
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/scripts/python.sh"

if ! command -v rokit >/dev/null 2>&1; then
	echo "Installing Rokit (Roblox toolchain manager)..."
	moonbrick_python "$kit/scripts/fetch-rokit.py"
	command -v rokit >/dev/null 2>&1 || { echo "error: Rokit install failed; see https://github.com/rojo-rbx/rokit"; exit 1; }
fi

# Trust exactly the tools pinned in rokit.toml, then install them.
tools=$(sed -n 's/^[A-Za-z0-9_-]* *= *"\([^@"]*\)@.*/\1/p' rokit.toml)
[ -n "$tools" ] || { echo 'error: no tools found in rokit.toml' >&2; exit 1; }
# shellcheck disable=SC2086
rokit trust $tools >/dev/null
rokit install >/dev/null
echo "Tools: $(rojo --version), luau-lsp $(luau-lsp --version), $(selene --version), $(stylua --version)"

rojo plugin install >/dev/null && echo "Rojo Studio plugin installed (restart Studio if it was open)." \
	|| echo 'note: Rojo Studio plugin not installed (is Roblox Studio installed?)'

# Roblox definitions pinned to the luau-lsp release in rokit.toml; keep in sync with template/tools/check.sh.
DEFS_URL=https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/0382dc76ca9b73df3c8e7c9cd85a8dd493cbd0ae/scripts/globalTypes.PluginSecurity.d.luau
DEFS_SHA256=e441a5cefd41d05649e14659b5bc23147bb1637b91ff86b04cbf1f45d8a4573c
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" "$DEFS_URL"
sum="$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$tmp"; else shasum -a 256 "$tmp"; fi)"
[ "${sum%% *}" = "$DEFS_SHA256" ] || { echo 'error: Roblox definitions checksum mismatch' >&2; exit 1; }
mv "$tmp" globalTypes.d.luau
echo 'Roblox type definitions downloaded.'
