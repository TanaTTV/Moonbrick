#!/usr/bin/env bash
# Install the toolchain for a roblox-kit project (run from the project root):
# Rokit (if missing) -> rojo, luau-lsp, selene, StyLua from rokit.toml -> Rojo Studio plugin -> Roblox type definitions.
set -euo pipefail
export PATH="$HOME/.rokit/bin:$PATH"

if ! command -v rokit >/dev/null 2>&1; then
	echo "Installing Rokit (Roblox toolchain manager)..."
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*)
		powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
			"Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression"
		;;
	*)
		curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
		;;
	esac
	command -v rokit >/dev/null 2>&1 || { echo "error: Rokit install failed; see https://github.com/rojo-rbx/rokit"; exit 1; }
fi

# Trust exactly the tools pinned in rokit.toml, then install them.
tools=$(sed -n 's/^[A-Za-z_-]* *= *"\([^@"]*\)@.*/\1/p' rokit.toml)
# shellcheck disable=SC2086
rokit trust $tools >/dev/null
rokit install >/dev/null
echo "Tools: $(rojo --version), luau-lsp $(luau-lsp --version), $(selene --version), $(stylua --version)"

rojo plugin install >/dev/null && echo "Rojo Studio plugin installed (restart Studio if it was open)."

curl -fsSL -o globalTypes.d.luau \
	https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.PluginSecurity.d.luau \
	&& echo "Roblox type definitions downloaded."
