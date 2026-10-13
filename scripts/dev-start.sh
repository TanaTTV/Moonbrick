#!/usr/bin/env bash
# SessionStart hook: in a moonbrick project, make sure `rojo serve` is running for it.
# Prints one short status line (added to Claude's context). Silent outside moonbrick projects.
set -u
cat >/dev/null # hook event JSON on stdin; not needed
dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$dir" 2>/dev/null || exit 0
[ -f default.project.json ] && [ -f tools/MCPKit.luau ] || exit 0

export PATH="$HOME/.rokit/bin:$PATH"
# Rojo's optional "servePort" project setting lets two games sync at once (the Studio plugin must use the same port).
port="$(sed -n 's/.*"servePort"[^0-9]*\([0-9][0-9]*\).*/\1/p' default.project.json | head -1)"
port="${port:-34872}"
name="$(grep -m1 '"name"' default.project.json | sed 's/.*"name"[^"]*"\([^"]*\)".*/\1/')"

status="$(curl -s --max-time 1 "http://localhost:$port/api/rojo" 2>/dev/null | tr -c '[:print:]' '\n')"
if [ -n "$status" ]; then
	if printf '%s\n' "$status" | grep -qx "$name"; then
		echo "moonbrick: rojo already serving '$name' on :$port."
	else
		other="$(printf '%s\n' "$status" | grep -A1 -x 'projectName' | tail -1)"
		echo "moonbrick: port $port is serving Rojo project '$other', not '$name', so this project may NOT be syncing (a server started before a project rename keeps its old name). Ask the user before stopping that server; it may be another open game. Setting \"servePort\" in default.project.json lets both run."
	fi
	exit 0
fi

if ! command -v rojo >/dev/null 2>&1; then
	echo "moonbrick: rojo is not installed; run /moonbrick:new's setup step (rokit install) before syncing."
	exit 0
fi

nohup rojo serve default.project.json --port "$port" >.rojo.log 2>&1 &
disown 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
	sleep 0.5
	curl -s --max-time 1 "http://localhost:$port/api/rojo" >/dev/null 2>&1 && break
done
if curl -s --max-time 1 "http://localhost:$port/api/rojo" >/dev/null 2>&1; then
	echo "moonbrick: started rojo for '$name' on :$port. If Studio shows stale code, the user must click Connect in the Rojo plugin."
else
	echo "moonbrick: rojo failed to start; see .rojo.log."
fi
