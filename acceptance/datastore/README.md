# Disposable DataStore acceptance

Prepared harness only. Do not run against persistent stores until the owner approves publishing a **new private disposable experience**. Never open, republish, allowlist, or enable API access for **Reyna Leer**, an existing game, or any production universe. Local/headless success does not close the live DataStore release gate.

## Build and check without Roblox

From the repository root (Python 3.10+):

```powershell
python scripts/fetch-luau.py # only if the pinned CLI is missing
python acceptance/datastore/run-headless.py --luau .artifacts/tools/luau/luau.exe
python -m unittest discover -s tests
python scripts/test-luau.py --luau .artifacts/tools/luau/luau.exe
```

The headless runner embeds `tests/headless.luau`'s deterministic coroutine scheduler and executes the same `Scenarios` functions over the shipped `PlayerData.memoryStore()`. It adds copy-safe `UpdateAsync`, `RemoveAsync`, and budget/service adapters. No credentials, Roblox connection, Studio or Roblox web API is involved. Test IDs 123/456 are memory-only gate fixtures, never a live allowlist.

All scripts are strict. Use the pinned Rokit tools from the new folder's manifest (install with `rokit install --no-trust-check` if needed, as in CI). From `acceptance/datastore`:

```powershell
$env:PATH = "$env:USERPROFILE\.rokit\bin;$env:PATH"
rojo build default.project.json -o ../../.artifacts/ds-acceptance.rbxlx
rojo sourcemap default.project.json -o sourcemap.json
# Download only public type definitions, or copy an existing verified project's definitions:
Invoke-WebRequest https://luau-lsp.pages.dev/type-definitions/globalTypes.PluginSecurity.d.luau -OutFile globalTypes.d.luau
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --formatter=plain src tests
selene --display-style=quiet src tests
```

Require both exits to be zero and no source diagnostics. The analyzer's watched-files-registration warning in CLI mode is tool infrastructure, not a source warning. `globalTypes.d.luau` and `sourcemap.json` are ignored local artifacts. The test spec is checked as well as the project scripts.

`PlayerDataFactory.luau` vendors the unchanged shipped PlayerData body inside a factory with injected lexical `game`, `task`, and `Instance`. Only its redundant inner strict directive is omitted; the outer file is strict. The runner compares the entire generated file to source every run, failing on drift. After reviewing an upstream change, refresh with:

```powershell
python acceptance/datastore/run-headless.py --refresh-factory --luau .artifacts/tools/luau/luau.exe
```

Do not format or hand-edit the generated factory, and never fix `luau/lib` from this acceptance work. `default.project.json` maps only this folder's `src`; the built place is self-contained and has no game scripts, remotes, production assets or player data integrations.

## Safety design

- Before acquiring a DataStore, require a Studio **server**, nonzero `game.PlaceId` and `game.GameId`, the exact manually set boolean `ServerScriptService.MoonbrickAcceptanceConfirmed = true`, and an allowlisted **place ID plus universe ID pair**. `Config.allowedPlaces` is empty and the Rojo attribute is false by default. Place titles are not trusted as identity; exact numeric IDs meet the allowlist requirement. Published Roblox game servers and clients are refused too.
- The only store name is the fixed `MoonbrickAcceptance_v1`, with default scope. Only `AcceptanceTest_<scenario>_<runId>` keys for `roundtrip`, `contention`, `stale`, `shutdown`, `invalid`, `budget`, `coordinator` can be read, written or removed. Run IDs are 1..12 ASCII alphanumerics, keeping every key below the 50-character limit. No name override or arbitrary cleanup key is accepted.
- Never start PlayerData against actual Players. Persistence scenarios use its public `Session` API with real `UpdateAsync` behind a guarded store. Lifecycle/recovery scenarios load a fresh factory with fake Players and a captured library `BindToClose` callback. The one fake UserId is the **string** `AcceptanceSynthetic`; its logical internal `Player_AcceptanceSynthetic` is accepted only by a mapper that forwards the fixed acceptance key. No `Player_<UserId>` or `Player_…` key ever reaches a DataStore.
- PlayerData's exact Studio opt-in is `studioStore = "live"`. The lifecycle adapter passes it explicitly along with the guarded `store`; direct Session tests receive that store explicitly. Both paths exercise the shipped ownership tokens, validation, retries and `UpdateAsync` callbacks. There is no fallback from persistent store failure to memory.
- Budget is checked before every provider operation. Zero budget waits at most eight seconds then fails without sending a request. Each server process/run has **40 regular requests plus 20 reserved cleanup requests, at most 60 total**, counting attempts, cancelled read-through updates, removals and provider errors. Counters are rechecked after yielding. Provider-internal callback retries are controlled by Roblox and are not separately countable. Two-server mode has a separate ceiling in each process, never an unbounded request loop.
- Inspection uses `UpdateAsync` with a callback returning nil so Roblox's local `GetAsync` cache cannot hide failed cleanup. Every key attempted for writing is tracked before a potentially ambiguous provider commit. Cleanup first closes lifecycle adapters and releases remaining sessions, then removes only tracked keys and reports exact leftovers. Explicit cleanup mode tries all seven fixed scenario keys for one run ID; it never scans or wipes a store.
- A suite preflight refuses a run ID with any existing fixture. Keep all run IDs from Output, especially after a crash. Do not run the suite concurrently with the same run ID. Only the documented contender pair shares an ID. Reset confirmation to false when done; Rojo rebuild/sync also resets the default attribute to false.

## Owner steps after approval

1. Build `.artifacts/ds-acceptance.rbxlx`. Open **that file in a new Studio window**, not an existing game window. Inspect `ServerScriptService.Acceptance` and verify the confirmation attribute is false and `Config.allowedPlaces` is empty.
2. Publish using **Publish to Roblox As… → Create new experience**, named `Moonbrick Acceptance 2026-10-13` (or an owner-approved unique disposable name). Leave access **private**. Verify the account/group and the new place/universe in Creator Hub. Never select an existing experience or an existing place in a production universe: places in a universe share stores.
3. In this new experience only, enable **Enable Studio Access to API Services** in Experience/Game Settings → Security and save. Roblox's UI labels may vary; the setting must be on for this new experience only. Do not enable HTTP requests; they are unnecessary.
4. Read the new numeric place ID and universe ID from Creator Hub. In Studio's **Edit-mode server Command Bar**, print `game.PlaceId, game.GameId` and verify they match. Both must be nonzero. In `ServerScriptService.Acceptance.Config`, set `allowedPlaces = { [YOUR_NEW_PLACE_ID] = YOUR_NEW_UNIVERSE_ID }`. Never copy the headless test IDs or another game's IDs. Do not commit the live IDs.
5. Select ServerScriptService → Attributes. Manually set boolean `MoonbrickAcceptanceConfirmed` to **true** in Edit mode. Set `Config.mode = "suite"`, leave `runId = ""` for a new generated ID, then run **Test → Start / Local Server** with one player (or a normal server Play session). Keep Output on the **server**. Record the opening line's IDs, store name and run ID.
6. Let the suite finish. Require seven PASS lines, `LEFTOVERS: none`, `DATASTORE ACCEPTANCE: 7 passed, 0 failed`. Any FAIL is a failed acceptance; do not call a failed or missing fixture a pass. Stop the server. Continue with the manual shutdown and two-server steps below to gather separate evidence.
7. If anything fails or you interrupt a run, **stop all test servers first**, set `mode = "cleanup"` and `runId` to the exact failed run ID, re-confirm if necessary, then start a fresh server. Require `PASS cleanup`, `LEFTOVERS: none`, and `DATASTORE ACCEPTANCE: 1 passed, 0 failed`. Retry cleanup after budget/outage recovery, at most one bounded run at a time. In Creator Hub's Data Stores Manager, inspect only `MoonbrickAcceptance_v1` and the recorded keys if leftovers remain; no bulk deletion.
8. After successful cleanup for **every recorded run ID**, set confirmation false, clear the allowlist, disable Studio API access on the disposable experience, and archive/delete the disposable experience using the owner's available Creator Hub controls. `RemoveAsync` removes current values, not necessarily historical retained versions; archival is not a claim of complete data erasure. Use Roblox's owner controls/retention policy for those histories. Never delete an unrelated experience.

## What each suite PASS proves

1. **roundtrip:** fresh session with a distinct token restores Coins=42 after a final save/release. The separate shutdown/restart run also checks a new server's restore.
2. **contention:** second same-job session with another token refuses a live lock, then succeeds after release. The two-process variant below adds independent server environments.
3. **stale:** a fixture lock timestamp seeded 601 seconds in the past is taken over without losing Coins=3. The shipped lock timeout is fixed at **600 seconds**, not configurable. Seeded age does not prove a ten-minute wall-clock wait; use the timed variant below.
4. **shutdown:** the exact shipped `BindToClose` body waits for a yielding Player API save, flushes Coins=91 and releases. Startup invokes the captured callback, so this alone does not prove the engine shutdown event; use `shutdown-arm`/`shutdown-verify` below.
5. **invalid:** seed an infinity value through Engine `UpdateAsync`, verify it was preserved, require default refusal after one attempt without adding a lock/backup, then use **`onInvalidData = PlayerData.sanitize`** through the Player API. Require Coins=0, Gems=3, and the original infinity in one backup. If the provider rejects or normalizes infinity, this fixture FAILS; no invalid-record/recovery claim is made. Engine non-finite serialization is described in the official reference below.
6. **budget:** print actual `GetRequestBudgetForRequestType(UpdateAsync)` values before/after; two **injected** throttling errors send no provider calls; verify the shipped Session waits 0.05s then 0.10s and succeeds on its next real store call. This proves retry/backoff under injected faults and observes real budgets, **not actual provider throttling/outage**. Do not exhaust quotas to manufacture that proof. Headless also verifies zero-budget refusal and the request caps.
7. **cleanup:** RemoveAsync every attempted write key (six in a successful suite; coordinator is unused) and verify absence through cancelled read-through updates. Any remaining current value or failed check prints its full key.

Expected abbreviated suite output:

```text
DATASTORE ACCEPTANCE: mode=suite, place=<new ID>, universe=<new ID>, store=MoonbrickAcceptance_v1, runId=<ID>
PASS roundtrip: ...
PASS contention: ...
PASS stale: ...
PASS shutdown: ... engine shutdown still manual
LOAD REFUSED: saved data is invalid (...) ... Set onInvalidData to recover
PASS invalid: ...
PASS budget: ... real throttling unproven
LEFTOVERS: none
PASS cleanup: 6 keys removed; verified absent via uncached UpdateAsync
DATASTORE ACCEPTANCE: 7 passed, 0 failed
REQUESTS: 44/60 (includes read-through UpdateAsync and cleanup)
```

Real provider errors can change attempt counts. Headless expects 44. Refusal examples (no store acquired):

```text
DATASTORE ACCEPTANCE REFUSED: manually set ServerScriptService.MoonbrickAcceptanceConfirmed = true; no DataStore acquired
DATASTORE ACCEPTANCE REFUSED: place/universe ID pair is absent from Config.allowedPlaces (empty by default); no DataStore acquired
```

## Real engine shutdown and restart

1. Choose a fresh explicit ID, e.g. `ShutOct13a`. Set mode `shutdown-arm`, that run ID, allowed IDs, confirmation true. Start one Studio server.
2. Wait for `ARMED shutdown`. **Stop that server promptly**, within 299 seconds so autosave has not independently persisted the change. The registered real engine `BindToClose` handler starts a yielding public save, then invokes PlayerData's captured shipped closure while the save is in flight. Save a copy of server Output before Studio closes it. Require `PASS engine-shutdown` and its summary. The process deliberately leaves one fixture for verification.
3. In Edit mode set `shutdown-verify` with the **same** ID. Start a fresh server. It first reads the record and requires Coins=91 and **no lock**, then acquires a fresh session, restores the value, releases, and cleans all seven possible keys for that ID. Require two PASS lines and `DATASTORE ACCEPTANCE: 2 passed, 0 failed` plus no leftovers.
4. A missing callback line is not proof of engine shutdown even if a later read succeeds. A hard-killed Studio process may never invoke BindToClose; use cleanup after it and record the missing engine evidence.

The library's shutdown body has a 25-second deadline; Roblox may terminate a server during a provider outage. The save pause is an injected 0.25-second delay before a provider call, not a deliberate slow provider. This harness isolates Players and calls the unchanged callback body through an engine wrapper; it does not prove the real Players lifecycle, actual disconnects, or shutdown-during-load. Those release gates remain separate.

## Timed natural lock expiry

1. Set mode `stale-arm`, a fresh explicit ID such as `StaleOct13a`, confirmation/allowlist as above. Start a server, record `ARMED stale`, and stop. It acquired a real Session lock with the current timestamp and intentionally omits release/BindToClose (an abandoned-session fixture, not an actual forced disconnect). The direct Session API has no automatic heartbeat.
2. Wait **at least 601 seconds after arming**. There is no configurable timeout to shorten the shipped 600-second lock rule. Set mode `stale-verify`, same ID, start another server. Require `PASS natural-lock-expiry`, `PASS cleanup`, `LEFTOVERS: none`, and `DATASTORE ACCEPTANCE: 2 passed, 0 failed`.
3. An early attempt prints FAIL with the lock age and retains the fixture so you can retry after expiry. Cleanup mode can remove it if cancelling. Headless checks this early refusal, then ages its memory-only fixture; it does not wait ten real minutes.

## Two independent Studio server processes

Prepare **two Studio windows** of the same new published place, both with the identical allowlisted IDs and explicit fresh run ID, e.g. `PairOct13a`. Keep configuration edits local to each window so publishing one role cannot replace the other.

1. Window A: set `contender-a`, confirmation true. Window B: set `contender-b`, confirmation true. Open both server Output panes before starting.
2. In A choose Test → **Start / Local Server**. As soon as it prints `A HOLDING`, start **another Local Server from window B** within 20 seconds. Starting two clients inside one Local Server is insufficient; they share one server environment. The UI may prevent two sessions from one Studio window, which is why the second window is required.
3. Both use `AcceptanceTest_contention_<ID>` and `AcceptanceTest_coordinator_<ID>`. A loads/holds, then publishes coordinator stage `holding`. B must print `B REFUSED live A lock` before publishing `refused`. A then saves Coins=77 and releases, publishes `released`; B freshly loads Coins=77 and releases, publishes `complete`. A alone cleans both keys after observing completion. Same process IDs are immaterial; the modules generate unique ownership tokens and the harness supplies distinct synthetic job IDs.
4. Require `PASS two-server-a`, `PASS two-server-b`; A's summary is **2 passed, 0 failed** (includes cleanup), B's **1 passed, 0 failed**. A must print `LEFTOVERS: none`. Save Output from both server processes. If a stage times out, stop **both** servers and run cleanup mode with the pair ID. B intentionally does not remove A's held key.
5. Team Test with multiple clients usually remains one server and does not alone establish two-server contention. Use it only if the operator can demonstrate two independent Studio server environments with the same place/universe; otherwise use the two-window Local Server method. Public/private published game-server sessions are refused by these Studio-only rails; this is not proof of production fleet contention or actual player hopping.

## Remaining owner decisions and evidence boundaries

The owner must approve the disposable name, account/group, new private universe, Studio API access and transient fixture writes. The operator must fill exact live IDs manually and retain all run IDs/Output. Live suite, natural expiry, engine shutdown/restart, and two-server runs remain unrun until that approval. Real throttling/outage, forced player disconnect and shutdown-during-load are not implemented as live fault generation here and remain separate release requirements. No PlayerData defect was reproduced by this harness; report any future defect with a failing memory fixture before changing the library.

Official references (documentation only, no Roblox API calls): [Studio DataStore access](https://create.roblox.com/docs/cloud-services/data-stores), [serialization and retained versions](https://create.roblox.com/docs/cloud-services/data-stores/versioning-listing-and-caching), [Engine non-finite values](https://create.roblox.com/docs/cloud/guides/data-stores#non-finite-numbers), [key limits and budgets](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).

## Exact approval request for the orchestrator

> Do you approve creating and publishing the built Moonbrick DataStore acceptance place (`.artifacts/ds-acceptance.rbxlx`) as ONE NEW private disposable experience named **Moonbrick Acceptance 2026-10-13** under your chosen Roblox account/group, never Reyna Leer or any existing/production universe; enabling Studio Access to API Services only there; manually allowlisting its new place/universe IDs and setting the confirmation attribute; and running the suite, timed expiry, shutdown/restart and two independent Studio-server variants? The only persistent data will be synthetic counters, test lock tokens/timestamps, an intentional invalid infinity value with its recovery backup, and coordinator stages in **MoonbrickAcceptance_v1**, on **AcceptanceTest_<scenario>_<runId>** keys, with no real player keys or personal data. Each server run is capped at 60 provider requests and no real throttling will be induced. After recording Output we will stop all test servers, RemoveAsync and verify every recorded run's seven possible keys, report any leftovers, reset confirmation/allowlist, disable API access, and archive/delete only that disposable experience using your owner controls. Historical key versions may remain subject to Roblox retention. Please confirm the account/group and disposable name; this approval covers only these tests, not production changes or V1 release/publication.
