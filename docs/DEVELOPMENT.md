# Development and validation

Use a development branch. Python 3.10+ and Bash are required for project safety operations; Windows uses Git Bash and `py -3` can replace `python`. Blender is optional; there is no new runtime game dependency.

Fast regressions:

```bash
python -m unittest discover -s tests -v
python scripts/fetch-luau.py
python scripts/test-luau.py --luau .artifacts/tools/luau/luau # append .exe on Windows
python scripts/prove-checker-fix.py
```

The original 0.1 checker reproducer prints `exit=0, output='OK'` after an analyzer exits 42. The fixed checker returns exit 1. Tests use controlled executable processes; they do not rely on diagnostic strings alone.

With pinned Rokit tools installed (read `scripts/setup-tools.sh` before installing):

```bash
bash scripts/new-project.sh .artifacts/sandbox sandbox --no-tools
cd .artifacts/sandbox
bash tools/check.sh
rojo build default.project.json -o sandbox.rbxlx
```

From the repository root: `python scripts/test-integration.py` validates real Rojo import/startup without touching an existing game; `python scripts/test-upgrade.py` uses the actual 0.1 git snapshot and checks game/settings fidelity and backups. It needs the original commit in local history; CI fetches full history. `python scripts/create-example.py <new-folder>` builds a playable Crystal Rush project.

Studio engine tests: `python scripts/test-studio.py .artifacts/studio-tests.luau`, then execute that **trusted generated source** through Studio MCP in the current datamodel. It uses unparented containers, simulated server services and memory stores; does not install scripts, change mode, call live stores or render a playable game. Lifecycle tests in `test-luau.py` use mock Players/BindToClose; real lifecycle/network/physics tests remain separate.

Optional native Blender test:

```bash
python scripts/test-blender.py --blender "<Blender executable>"
```

Blender 5.2.2 LTS was run locally. Static props, FBX native reimport/scale, budget refusal, source preservation and output refusal passed. Rig animation, PBR texture import and Roblox mesh round-trip remain unproven. CLI launches use `--factory-startup --disable-autoexec` and pass arguments separately; input scenes are never saved by the exporter. The fixture generator writes a new, explicitly named scene.

Plugin checks (no model session involved):

```bash
claude plugin validate --strict .
claude plugin validate --strict .claude-plugin/plugin.json
claude plugin validate --strict skills
```

CI checks the host regressions, pinned Luau session/game rules, actual tool checking/building, real Rojo integration, 0.1 upgrade, example build and plugin manifests/components. It does not install Studio, publish assets or access DataStores. Remote CI results are unavailable until this development branch is pushed; do not describe authored YAML as a passing hosted run.

Rojo startup proves its listener belongs to the launched process or a child before recording ownership. It uses native `netstat`/PowerShell on Windows and `lsof`/`ps` on macOS/Linux. Missing inspection tools fail closed with a status message; existing foreign servers are never stopped or claimed.

## Upgrading existing projects

`sync-kit.sh` updates helpers/libraries/tests, fills **missing** service preservation settings, adds `.moonbrick/` to ignores and copies old changed files to `.moonbrick/backups/<id>`. It preserves explicit user settings and game code, rolls back partial managed-file failures, and does nothing for identical inputs. Review local modifications before upgrading and do not stage unrelated work.

Changes requiring attention: Studio now defaults to memory; real test-store access is explicit. Session lock records gain an additive `token` field; legacy `{data, lock={job,time}}` data is preserved/reconciled. Never run two kit versions inside one server. `Session.ignoreLocks` cannot bypass ownership. `PlayerData.update` callbacks must not yield, and failure returns false without partial data mutation. Net rejects duplicate server handlers and wrong-class remotes. Basic model export refuses complex classes/references rather than discarding them.

Imports require a fresh scaffold, preserve the saved place and refuse reserved-name collisions. Read `.moonbrick/import-report.json` and all imported scripts before running them; a static scan can miss malicious code. Native Rojo syncback preserves imported service data; Workspace/Lighting remain in the original saved place. A build of the code-only imported project is not a replacement for that original place. Always review the Studio connection diff.

Primary references: [Roblox UpdateAsync](https://create.roblox.com/docs/reference/engine/classes/GlobalDataStore#UpdateAsync), [Roblox player data patterns](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing), [Rojo project boundaries](https://rojo.space/docs/v7/project-format/), [typed Rojo attributes](https://rojo.space/docs/v7/properties/#attributes), [Roblox native importer](https://create.roblox.com/docs/studio/importer). Blender export options were also inspected directly on the installed native operator.
