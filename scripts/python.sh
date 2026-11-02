#!/usr/bin/env bash
# Source this to choose Python 3.10+ on macOS/Linux and Windows Git Bash.
moonbrick_python() {
	export PYTHONUTF8=1
	local candidate
	for candidate in "py -3" python3 python; do
		command -v "${candidate%% *}" >/dev/null 2>&1 || continue
		# Skips too-old interpreters and stubs (e.g. macOS's python3 before Xcode tools) without running the script.
		if $candidate -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
			$candidate "$@"
			return
		fi
	done
	echo 'error: Moonbrick project safety tools require Python 3.10+' >&2
	return 2
}

# Skills quote their paths, so Bash leaves "~/RobloxProjects/x" alone; expand a leading ~ here.
moonbrick_path() {
	case "$1" in
	'~') printf '%s\n' "$HOME" ;;
	'~/'* | '~\'*) printf '%s\n' "$HOME/${1:2}" ;;
	*) printf '%s\n' "$1" ;;
	esac
}
