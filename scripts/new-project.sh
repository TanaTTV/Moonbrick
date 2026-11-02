#!/usr/bin/env bash
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/scripts/python.sh"
target="$(moonbrick_path "${1:?usage: new-project.sh <target-dir> [project-name] [--no-tools]}")"
shift
name="$(basename "$target")"
tools=1
if [ "$#" -gt 0 ] && [ "$1" != --no-tools ]; then name="$1"; shift; fi
if [ "$#" -gt 0 ] && [ "$1" = --no-tools ]; then tools=0; shift; fi
[ "$#" -eq 0 ] || { echo 'error: unexpected arguments' >&2; exit 2; }
moonbrick_python "$kit/scripts/project.py" new "$target" "$name"
cd "$target"
# Commit before tool setup so a network failure there still leaves a complete, committed project.
# A retry lands here too, so never stage anything once this folder has its own first commit.
[ -e .git ] || git init -q
if ! git rev-parse -q --verify HEAD >/dev/null 2>&1; then
	git add -- .
	identity=()
	git config user.name >/dev/null 2>&1 || identity+=(-c user.name=Moonbrick)
	git config user.email >/dev/null 2>&1 || identity+=(-c user.email=moonbrick@localhost)
	git ${identity[@]+"${identity[@]}"} commit -q -m "New moonbrick project: $name" || {
		echo "error: the first git commit failed; fix the git error above, then rerun this same command to resume" >&2
		exit 1
	}
fi
echo "Created $name at $(pwd)"
if [ "$tools" = 1 ]; then
	bash "$kit/scripts/setup-tools.sh" || { echo "error: tool setup failed; the project is created; fix the error above, then rerun this same command" >&2; exit 1; }
fi
