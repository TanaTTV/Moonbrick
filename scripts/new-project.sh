#!/usr/bin/env bash
# Create a moonbrick game project.
# Usage: bash new-project.sh <target-dir> [project-name] [--no-tools]
set -euo pipefail
kit="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:?usage: new-project.sh <target-dir> [project-name] [--no-tools]}"
name="${2:-$(basename "$target")}"
[ "$name" = "--no-tools" ] && name="$(basename "$target")"
case " $* " in *" --no-tools "*) tools=0 ;; *) tools=1 ;; esac

if [ -d "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
	echo "error: $target already exists and is not empty"
	exit 1
fi
mkdir -p "$target"
cp -R "$kit/template/." "$target/"
bash "$kit/scripts/sync-kit.sh" "$target" >/dev/null

# Fill in the project name.
for f in default.project.json CLAUDE.md; do
	sed "s/__PROJECT_NAME__/$name/g" "$target/$f" >"$target/$f.tmp" && mv "$target/$f.tmp" "$target/$f"
done

cd "$target"
[ "$tools" = 1 ] && bash "$kit/scripts/setup-tools.sh"
git init -q
git add -A
git commit -q -m "New moonbrick project: $name"
echo "Created $name at $(pwd)"
