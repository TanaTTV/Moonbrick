# Changelog

## Unreleased (V1 development)
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
- V1 release gates remain open; no 1.0 version/tag/publication is implied by these changes.

## 0.1.0
First release.
- Skills: studio, game-systems, game-design, new, import, update, playtest, review, ship.
- Project template with Rojo, luau-lsp (strict), selene, StyLua, tests and debug hooks; SessionStart hook keeps `rojo serve` running.
- Kit libraries: VFX, UI, Net, PlayerData, DebugHooks (+ 18 unit tests).
- MCPKit v3: tree/props/find/set, script tools, test runner, recorder, logs, screen coords, perf, audit, model export.
