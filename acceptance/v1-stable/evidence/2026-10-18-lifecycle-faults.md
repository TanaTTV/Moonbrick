# 2026-10-18 — Forced disconnect and shutdown during load/save (Studio, injected provider faults)

- **Repo commit:** 947fd53 (`qa/v1-stable-evidence`) + [`lifecycle/Lifecycle.server.luau`](../lifecycle/Lifecycle.server.luau)
- **Studio:** 0.743.0.7431133, Windows 11
- **Place:** fresh `scripts/new-project.sh … --no-tools` + the harness script → `tools/check.sh` (OK) → `rojo build`; new local unpublished file (PlaceId 0), opened in its own Studio window. The harness asserts Studio + PlaceId 0.
- **What is real:** the shipped, unchanged `PlayerData` library; the real Roblox `Players` lifecycle (`Player:Kick` → `PlayerRemoving`); real engine shutdown (`BindToClose`), either from Studio Stop or from the last player leaving.
- **What is injected (test faults, not real provider behaviour):** the store is `PlayerData.memoryStore()` behind the library's own `store` option, wrapped to add a delay before each `UpdateAsync` and/or to throw `INJECTED provider outage`. No DataStore was acquired. A separate `BindToClose` in the harness only prints how long the engine keeps the server alive.
- **Seed:** each run starts from an existing save with Coins=37. Player IDs are redacted from this report.

## Results

| # | Scenario | Store log (abridged) | Outcome | Result |
|---|---|---|---|---|
| 1 | **Kick during load** (15 s injected load delay) | kick logged before the load returned; `#1 lock=held Coins=37` then `#2 lock=none Coins=37` | Load completed after the player left and was released immediately; data unchanged, no overwrite, no warnings. The last player leaving shut the server down and shutdown waited for the release | pass |
| 2 | **Kick during save + 1 injected outage** (in-memory 37→42, 2 s delay) | `#2 INJECTED outage` → 2 s retry → `#3 lock=none Coins=42`; `closing +4.6s` | Final save retried inside the bounded loop and released the lock with the new value; shutdown kept the server alive until it finished | pass |
| 3 | **Studio Stop with a persistent outage** (autosave wrote 42; then +3 unsaved; every call fails) | `#3…#10 INJECTED outage`, two `final save … failed` warnings, then `shutdown ended with unsaved data operations after bounded retries` at `closing +25.0s` | Bounded: 3 tries per final save, 2 shutdown re-attempts, stopped at the 25 s deadline. The record keeps the last good save (42) and its lock, which expires after 600 s; only the 3 coins since the last autosave are lost. Nothing corrupted, clear warning | pass (expected safe failure) |
| 4 | **Studio Stop during load** (8 s injected load delay) | `closing +0.0s` before `#1 lock=held Coins=37`, then `#2 lock=none Coins=37` at ≈12.6 s | Shutdown waited for the in-flight load, then released it; data unchanged | pass |
| 2a | First attempt at #2 (without an in-game coin change) | `#3 INJECTED outage` → `#4 lock=none Coins=37` | Same retry path; the coin change failed because MCP-executed code has its own `require` cache, so the harness now exposes `increment`/`kick` | supporting |

Studio Output was read after the play session ended; it lags several seconds behind the server, so a read taken immediately looks truncated. Only Studio CorePackages UIBlox warnings and an unrelated core `rbxassetid://203785492` warning appeared besides the harness and PlayerData lines.

## Boundaries

- Covers the `datastore-forced-disconnect` gate: real disconnect and shutdown lifecycle during load and save in a disposable context, with every provider fault labelled as injected.
- Does **not** show real Roblox DataStore throttling or outages (`datastore-provider-failures`), a published server's shutdown timing, or a network-level client crash. Kick and crash both reach the same server `PlayerRemoving` path, but the client side differs.
- Recovery after scenario 3 (rejoin after the 600 s lock expiry) is covered by the shipped Luau suite and the beta live suite, not re-run here.
