# Troubleshooting

Rojo startup messages begin with `moonbrick:` and come from the SessionStart hook (`hooks/hooks.json` → `scripts/dev-start.sh` → `scripts/dev-server.py`). The hook only acts in a Moonbrick project (a folder with `default.project.json` and `tools/MCPKit.luau`); elsewhere it exits silently. To rerun it by hand, ask Claude to run the plugin's `scripts/dev-start.sh` from the project folder, or run `CLAUDE_PROJECT_DIR="<project>" bash "<plugin>/scripts/dev-start.sh" </dev/null`.

## Claude can't see Studio

The Studio MCP is part of Roblox Studio, not Moonbrick. Enable it in Studio → Assistant settings, keep Studio open, and check that Claude Code lists the `Roblox_Studio` MCP server (`/mcp`). Claude checks with `list_roblox_studios`; if that tool is missing, the server isn't connected.

## No Rojo button in Studio

Project setup installs the Rojo Studio plugin (`rojo plugin install`). Studio only loads plugins at startup, so restart Studio if it was open during setup. Then Plugins → Rojo → **Connect**.

## "port … is occupied by an unrecognized service" / "ownership for this folder is unverified"

Something already listens on the project's `servePort` (default 34872, in `default.project.json`):

- *unrecognized service*: it isn't Rojo. Stop that program or set another `servePort`.
- *serves '<name>'; ownership … unverified*: a Rojo server that this project's session didn't start (another project, or an old `rojo serve` you ran yourself). Moonbrick never stops or claims a server it didn't start. Stop it yourself, or give this project its own `servePort`, then start a new session.
- *Rojo already serving …*: this project's own server is still running; just Connect in Studio.

A launch that fails stops its own Rojo before exiting; check `.rojo.log` in the project for the reason.

## SessionStart hook timed out

The hook has a 20 s budget; Rojo startup itself waits at most 5 s. Rerun the hook by hand (see the top) to see its message, and check `.rojo.log`. If the timeout cut a launch short, its Rojo can keep running unowned and the next session reports "ownership unverified": stop that `rojo` process, then start a new session. On Linux, ownership checks need `lsof` or `/proc`; on macOS, `lsof`. Missing tools fail closed with a message.

## Windows: `bash` not found

The hook, the scaffold and `tools/check.sh` all run through `bash`. Install [Git for Windows](https://git-scm.com/download/win) and make sure `bash --version` works in a new terminal (add Git's `bin` folder, e.g. `C:\Program Files\Git\bin`, to PATH if not), then restart Claude Code.

## "another Rojo startup for this project is in progress"

`.moonbrick/serve.lock` exists because another session is starting Rojo for the same project. Retry in a few seconds. A lock older than 60 s is treated as left over from a killed launch and removed automatically on the next start.

## Studio shows old code after an edit

Files sync only while Rojo is connected. In Studio, Plugins → Rojo → **Connect** again and review the diff. Edits made to synced scripts inside Studio are overwritten by the files.

## A module change doesn't take effect in Edit mode

Studio caches `require` in Edit mode until it restarts. Test in a playtest (fresh VM), or require a clone: `_G.K=require(game.ServerStorage.MCPKit:Clone())`.

## The skills didn't kick in

For a short request like "make a Roblox game", Claude may not pick up the skills on its own (see the [benchmark](BENCHMARK-SUMMARY.md)). Start with `/moonbrick:new`, or say "use Moonbrick". Inside a project, start Claude Code in the project folder so its `CLAUDE.md` loads.

## "Moonbrick project safety tools require Python 3.10+"

`scripts/python.sh` tries `py -3`, `python3`, then `python`, and uses the first that is 3.10 or newer. Install Python 3.10+ and make sure one of those commands finds it in a new terminal. On macOS, a stub `python3` from missing Xcode command-line tools is skipped.
