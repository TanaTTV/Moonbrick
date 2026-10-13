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
tools=$(sed -n 's/^[A-Za-z_-]* *= *"\([^@"]*\)@.*/\1/p' rokit.toml)
# shellcheck disable=SC2086
rokit trust $tools >/dev/null
rokit install >/dev/null
echo "Tools: $(rojo --version), luau-lsp $(luau-lsp --version), $(selene --version), $(stylua --version)"

rojo plugin install >/dev/null && echo "Rojo Studio plugin installed (restart Studio if it was open)."

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" \
	https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau
[ -s "$tmp" ] || { echo 'error: empty Roblox definitions download' >&2; exit 1; }
mv "$tmp" globalTypes.d.luau
echo 'Roblox type definitions downloaded.'
