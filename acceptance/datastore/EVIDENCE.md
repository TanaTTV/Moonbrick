# Local validation evidence

Captured 2026-10-13 in `C:\Users\Admin\Moonbrick-wt\datastore`, branch `dev/v1-beta-datastore`. These are local CLI/memory results, not Studio/Roblox/provider results. No Studio, Studio MCP, Roblox web API, real DataStore, publication, push or PR was used.

Setup: ran `python scripts/fetch-luau.py` successfully (pinned Luau 0.742, verified by that script). Rokit already had Rojo 7.7.1, luau-lsp 1.70.1, Selene 0.32.0 and StyLua 2.6.0. Root has no Rokit manifest, so the exact pinned underlying Rojo executable was used for the root build command. Analyze/lint were run from `acceptance/datastore` using its pinned manifest, strict `.luaurc`, generated sourcemap, and public Roblox definitions copied from the existing local `.artifacts/crystal-rush/globalTypes.d.luau`. Both `src` and `tests` were analyzed/linted. No checker diagnostics were filtered. The watched-files warning is the CLI's registration warning; Selene reports zero source warnings.

`EXPECTED EARLY REFUSAL FIXTURE` intentionally runs verification before lock expiry and asserts it fails without deleting the key. The final injected RemoveAsync outage likewise asserts exact leftover reporting then a successful retry. Neither is an unexpected harness failure. Natural time is advanced only by aging an in-memory fixture; real wall-clock/engine/provider proof remains pending.

## Acceptance headless runner

Command (PowerShell):

```powershell
python acceptance/datastore/run-headless.py --luau .artifacts/tools/luau/luau.exe
```

Exit: `0`. Raw captured output:

```text
DATASTORE ACCEPTANCE REFUSED: manually set ServerScriptService.MoonbrickAcceptanceConfirmed = true; no DataStore acquired
DATASTORE ACCEPTANCE REFUSED: place/universe ID pair is absent from Config.allowedPlaces (empty by default); no DataStore acquired
PASS Main-default-refusal: actual entry script stopped before store/service/factory acquisition
PASS refusal-confirmation: DATASTORE ACCEPTANCE REFUSED: manually set ServerScriptService.MoonbrickAcceptanceConfirmed = true; no DataStore acquired
PASS refusal-allowlist: DATASTORE ACCEPTANCE REFUSED: place/universe ID pair is absent from Config.allowedPlaces (empty by default); no DataStore acquired
PASS refusal-unpublished: DATASTORE ACCEPTANCE REFUSED: publish a NEW private disposable experience first (PlaceId/GameId must be nonzero); no DataStore acquired
PASS refusal-universe: DATASTORE ACCEPTANCE REFUSED: place/universe ID pair is absent from Config.allowedPlaces (empty by default); no DataStore acquired
PASS refusal-live-server: DATASTORE ACCEPTANCE REFUSED: Studio server only; live game servers and clients are refused; no DataStore acquired
PASS refusal-client: DATASTORE ACCEPTANCE REFUSED: Studio server only; live game servers and clients are refused; no DataStore acquired
PASS refusal-run-id: DATASTORE ACCEPTANCE REFUSED: Config.runId must contain 1..12 ASCII letters/digits; no DataStore acquired
PASS roundtrip: fresh token loaded Coins=42 after release
PASS contention: second token refused while held; succeeds after release (same job ID)
PASS stale: seeded 601-second-old lock taken over; fixed expiry=600s, no configurable timeout
PASS shutdown: shipped BindToClose body waited for in-flight Player API save, flushed Coins=91, released lock; engine shutdown still manual
LOAD REFUSED: saved data is invalid (C:/Users/Admin/AppData/Local/Temp/moonbrick-datastore-jsnxkvfk/acceptance.luau:128: data contains a non-finite number); not loaded or overwritten. Set onInvalidData to recover
PASS invalid: default refused once without writing; onInvalidData=sanitize recovered defaults/Gems and retained original backup
PASS budget: UpdateAsync budget before=100, after=100; 2 injected throttles, waits=0.05s/0.10s, then success; real throttling unproven
LEFTOVERS: none
PASS cleanup: 6 keys removed; verified absent via uncached UpdateAsync
DATASTORE ACCEPTANCE: 7 passed, 0 failed
REQUESTS: 44/60 (includes read-through UpdateAsync and cleanup)
PASS foreign-key-rails: UpdateAsync/read/RemoveAsync refused before provider calls
ARMED shutdown: Stop this server promptly; keep key for restart verification, runId=ShutdownRun
PASS engine-shutdown: engine invoked shipped BindToClose body; restart in shutdown-verify mode
DATASTORE ACCEPTANCE: 1 passed, 0 failed
REQUESTS: 4/60 (includes read-through UpdateAsync and cleanup)
PASS engine-shutdown-restart: persisted Coins=91, no lock, fresh session restored data
LEFTOVERS: none
PASS cleanup: 7 keys removed; verified absent via uncached UpdateAsync
DATASTORE ACCEPTANCE: 2 passed, 0 failed
REQUESTS: 17/60 (includes read-through UpdateAsync and cleanup)
A HOLDING: start B now with same run ID (20-second window)
B REFUSED live A lock
PASS two-server-b: coordinator observed refusal, release and B load of Coins=77
DATASTORE ACCEPTANCE: 1 passed, 0 failed
REQUESTS: 8/60 (includes read-through UpdateAsync and cleanup)
PASS two-server-a: coordinator observed refusal, release and B load of Coins=77
LEFTOVERS: none
PASS cleanup: 2 keys removed; verified absent via uncached UpdateAsync
DATASTORE ACCEPTANCE: 2 passed, 0 failed
REQUESTS: 14/60 (includes read-through UpdateAsync and cleanup)
PASS two-server-workflow: both roles/coordination/cleanup passed against shared memory (not real servers)
ARMED stale: lock written now; Stop server, wait at least 601 seconds, then stale-verify with runId=TimedStale
EXPECTED EARLY REFUSAL FIXTURE: FAIL natural-lock-expiry: C:/Users/Admin/AppData/Local/Temp/moonbrick-datastore-jsnxkvfk/acceptance.luau:1309: lock is only 0s old; wait until at least 601s after arming
EXPECTED EARLY REFUSAL FIXTURE: LEFTOVERS: retained stale fixture; retry after 601s or cleanup with runId=TimedStale
EXPECTED EARLY REFUSAL FIXTURE: DATASTORE ACCEPTANCE: 0 passed, 1 failed
EXPECTED EARLY REFUSAL FIXTURE: REQUESTS: 1/60 (includes read-through UpdateAsync and cleanup)
PASS natural-lock-expiry: naturally aged 601s lock taken over and released
LEFTOVERS: none
PASS cleanup: 1 keys removed; verified absent via uncached UpdateAsync
DATASTORE ACCEPTANCE: 2 passed, 0 failed
REQUESTS: 5/60 (includes read-through UpdateAsync and cleanup)
PASS timed-expiry-workflow: arm did not backdate; early verification retained fixture; aged memory fixture recovered
PASS zero-budget: bounded 8-second wait refused without provider request
PASS request-ceiling: regular=40, reserved cleanup=20, request 61 refused
PASS budget-wait-race: two waiting workers shared one remaining allowance; excess worker refused
LEFTOVERS: AcceptanceTest_roundtrip_Leftovers (C:/Users/Admin/AppData/Local/Temp/moonbrick-datastore-jsnxkvfk/acceptance.luau:1725: injected RemoveAsync outage)
LEFTOVERS: none
PASS leftover-reporting: failed RemoveAsync reported exact key; subsequent cleanup succeeded
HEADLESS ACCEPTANCE: all checks PASS, 0 worker errors (memory only; no live provider proof)
```

## Rojo build

Command (PowerShell):

```powershell
& C:\Users\Admin\.rokit\tool-storage\rojo-rbx\rojo\7.7.1\rojo.exe build acceptance/datastore/default.project.json -o .artifacts/ds-acceptance.rbxlx
```

Exit: `0`. Raw captured output:

```text
Building project 'Moonbrick DataStore Acceptance'
Built project to ds-acceptance.rbxlx
```

## Strict analysis and Selene

Command (PowerShell):

```powershell
& C:\Users\Admin\.rokit\bin\rojo.exe sourcemap default.project.json -o sourcemap.json; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & C:\Users\Admin\.rokit\bin\luau-lsp.exe analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --formatter=plain src tests; $typeStatus = $LASTEXITCODE; & C:\Users\Admin\.rokit\bin\selene.exe --display-style=quiet src tests; $lintStatus = $LASTEXITCODE; Write-Output "luau-lsp exit=$typeStatus; selene exit=$lintStatus"; if ($typeStatus -ne 0 -or $lintStatus -ne 0) { exit 1 }
```

Exit: `0`. Raw captured output:

```text
Created sourcemap at sourcemap.json
[INFO] Loading definitions file: @roblox - globalTypes.d.luau
[WARN] client does not allow didChangeWatchedFiles registration - automatic updating on sourcemap changes disabled
[INFO] Loading Luau configuration from c:\Users\Admin\Moonbrick-wt\datastore\acceptance\datastore\.luaurc
Results:
0 errors
0 warnings
0 parse errors
luau-lsp exit=0; selene exit=0
```

## Host regression suite

Command (PowerShell):

```powershell
python -m unittest discover -s tests
```

Exit: `0`. Raw captured output:

```text
...................................
----------------------------------------------------------------------
Ran 35 tests in 9.230s

OK
moonbrick: another Rojo startup for this project is in progress; retry in a few seconds.
moonbrick: :34872 serves 'same'; ownership for this folder is unverified. Choose another servePort or inspect the existing server.
moonbrick: owned startup process PID 12345 may still be running; inspect .rojo.log before retrying.
moonbrick: removed a stale startup lock left by an interrupted Rojo launch.
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 0 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
Imported place.rbxl; review the Rojo connection diff before accepting. Backup: C:\Users\Admin\AppData\Local\Temp\tmp64tx4slf\game\.moonbrick\backups\import-ed62ba97f8fe4805b8b299ce4cbf33ad
Advisory import scan: 1 scripts, 0 findings; review .moonbrick/import-report.json before play/publish.
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
Imported place.rbxl; review the Rojo connection diff before accepting. Backup: C:\Users\Admin\AppData\Local\Temp\tmpkw2k4mbu\game\.moonbrick\backups\import-b215d2d6ec004838a45523d1cf0767e9
Advisory import scan: 1 scripts, 0 findings; review .moonbrick/import-report.json before play/publish.
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 2 managed files updated; game files preserved
Previous files: C:\Users\Admin\AppData\Local\Temp\tmpeg4rvkqo\game\.moonbrick\backups\20261013T185257Z-813e4231
moonbrick 0.1.0: 0 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 1 managed files updated; game files preserved
Previous files: C:\Users\Admin\AppData\Local\Temp\tmpu98l9cil\game\.moonbrick\backups\20261013T185258Z-1a163381
moonbrick 0.1.0: 14 managed files updated; game files preserved
moonbrick 0.1.0: 14 managed files updated; game files preserved
```

## Shipped Luau regressions

Command (PowerShell):

```powershell
python scripts/test-luau.py --luau .artifacts/tools/luau/luau.exe
```

Exit: `0`. Raw captured output:

```text
43 passed, 0 failed, 0 worker errors (headless)
```

## Built-place inspection

Parsed `.artifacts/ds-acceptance.rbxlx` locally as XML. It contains exactly five ModuleScripts (`Config`, `Lifecycle`, `PlayerDataFactory`, `Safety`, `Scenarios`) and one server Script (`Main`), with no LocalScript. SHA256: `c1926db407a47d63fbf4618aed65ac69d81d150cd487924c168c97c41d9e67d0`. The project's confirmation attribute is false and the allowlist module is empty by default. `git diff --check` passed. Commit and clean-worktree evidence is returned in the final handoff, because embedding a commit's own hash in its files would change that hash.
