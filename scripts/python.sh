#!/usr/bin/env bash
# Source this to choose Python 3 on macOS/Linux and Windows Git Bash.
moonbrick_python() {
	export PYTHONUTF8=1
	if command -v py >/dev/null 2>&1; then py -3 "$@"
	elif command -v python3 >/dev/null 2>&1; then python3 "$@"
	elif command -v python >/dev/null 2>&1; then python "$@"
	else echo 'error: Moonbrick project safety tools require Python 3.10+' >&2; return 2
	fi
}
