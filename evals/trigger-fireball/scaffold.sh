#!/usr/bin/env bash
# A plain Rojo game with no Kit, so the Moonbrick SessionStart hook stays out of the run.
mkdir -p src/server src/client
echo '{"name":"game","tree":{"$className":"DataModel","ServerScriptService":{"Server":{"$path":"src/server"}}}}' >default.project.json
echo 'print("game")' >src/server/Main.server.luau
