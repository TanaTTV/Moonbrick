# Changelog

## Unreleased (V1 development)
- Use automatic Blender material node trees on 5+ without accessing the deprecated `use_nodes` toggle; preserve legacy behavior before 5.0.
- Format the headless harness and PlayerData with the template StyLua rules; check shipped Luau, the harness and examples in CI.
- Add bounded Net rejection counters with isolated snapshots, active-player cleanup and per-remote summaries limited to once per minute.
- Fix false-success checking, failed/stale sourcemaps, partial type downloads and formatter failure handling; include dynamic MCPKit in checking/linting.
- Replace destructive import with staged validation/promotion, backups, reserved-name refusal, advisory script scan and no automatic git staging. Preserve non-imported world content and explicit project settings.
- Add transactional/idempotent managed updates with backups, missing service-preservation settings and safe ignore migration. Project scripts require Python 3.10+.
- Fence PlayerData with per-session tokens, serialized snapshot writes and DataStore metadata preservation. Retain failed leave saves for shutdown/retry; reject corrupt/unserializable data; cancel failed/yielding update callbacks. Lost sessions reject access and kick by default.
- Studio defaults to memory even with API access. Explicit `studioStore = "live"` is for a separate test experience; no provider-error memory fallback. Deprecated lock bypass is ignored.
- Harden Net validators, remote class/name checks, duplicate registrations, finite rate limits, client timeouts and yielding request concurrency.
- Fix Rojo MessagePack identity handling, loopback-only startup and foreign-listener preservation. Pin/checksum Rokit and Luau bootstraps.
- Bound/cancel MCPKit recordings, fix typed Rojo attributes, reject empty all-replace edits and complex lossy exports. Fix stale UI visibility tweens and idle camera-shake callbacks.
- Add optional native Blender FBX workflow, shared art manifests, static-prop native round-trip tests and source/budget/overwrite safety.
- Add server Cooldown/Round/Economy libraries and a complete buildable Crystal Rush example with server-fed HUD, shared rounds and validated pickups.
- Add cross-platform CI, host/headless/isolated Studio regressions, actual 0.1 upgrade checks, real Rojo integration and measured output benchmark.
- QA fixes: `PlayerData.set`/`increment` reject non-finite/unserializable values; a final save with invalid data still releases the lock (keeping the last good save) instead of locking the player out for 10 minutes; failed manual saves warn. `K.logs()` no longer misses warnings raised in the same call. `K.audit()` reports its true total and refuses to run in playtests (engine scripts produced hundreds of false positives). Crystal Rush HUD label reads "Crystals".
- Stability follow-ups: saved data that fails validation is refused once (no retry storm), never overwritten, and can be recovered with the opt-in `onInvalidData` callback (`PlayerData.sanitize` provided); the original is kept in a bounded `backups` list and recovery refuses rather than discarding a backup. Crystal Rush checks movement against a server-trusted position, pulling back teleports/speed hacks before the pickup distance check. Project sync/import only rejects links in the paths it manages (`src`, `tools`, `tests`, `.moonbrick`, project files), so `node_modules` links no longer block upgrades. A `serve.lock` left by a killed launch is reclaimed after 60 s; a live one reports "startup in progress" instead of "File exists". CI authenticates Rokit to avoid GitHub API rate-limit failures. The Windows listener-ownership check allows for slow WMI startup (3 s → 20 s timeout).
- V1 release gates remain open; no 1.0 version/tag/publication is implied by these changes.

## 0.1.0
First release.
- Skills: studio, game-systems, game-design, new, import, update, playtest, review, ship.
- Project template with Rojo, luau-lsp (strict), selene, StyLua, tests and debug hooks; SessionStart hook keeps `rojo serve` running.
- Kit libraries: VFX, UI, Net, PlayerData, DebugHooks (+ 18 unit tests).
- MCPKit v3: tree/props/find/set, script tools, test runner, recorder, logs, screen coords, perf, audit, model export.
