# V1 development ledger

Branch: `dev/v1-stability`. Base: `c451028`. No release, merge, asset upload or production DataStore writes authorized/performed.

## Architecture audit

Moonbrick 0.1.0 comprises nine Claude skills, a SessionStart hook, five shell entry points, a Rojo project template, MCPKit, four gameplay libraries and three Luau spec suites. There is no hosted service or runtime plugin dependency: managed libraries are copied into each game. Preserve this architecture; add narrow, optional native-tool adapters rather than a second MCP server.

Highest priority: `tools/check.sh` erased failure exit codes and could print `OK` after failed analysis. Other critical issues: destructive import before successful syncback, wildcard deletion of imported `Kit*`/`Tests*` names, default Studio lock bypass, concurrent saves, stale sessions saving without a lock, loss of pending leave operations from shutdown tracking, and a text parser applied to Rojo 7.7.1 MessagePack responses.

## Phase 1 implemented

- [x] Checker fails closed on tool, formatter, sourcemap and download failures; checks MCPKit too.
- [x] Import stages each attempt independently, validates before promotion, keeps backups, refuses existing game code and reserved-name collisions, never stages unrelated git changes or deletes template folders.
- [x] Explicit service boundary preservation in new/imported Rojo mappings.
- [x] Structured names, preserved project settings, symlink/junction refusal, managed-file upgrade backups.
- [x] Unique session ownership tokens, serialized snapshot writes, callback-rerun handling, lost-lock fencing, serializable-value validation, failed leave-save retention and shutdown operation tracking.
- [x] Nonyielding data update transactions, ambiguous-success retry regression, metadata/user-ID preservation and lost-session kick behavior.
- [x] Studio defaults to memory. Live opt-in never silently switches an acquired persistent session to memory.
- [x] Net rejects throwing validators, duplicate handlers and class conflicts; finite rate options; bounded in-flight request handlers; bounded client lookup.
- [x] Rojo loopback listener, MessagePack/JSON handshake, folder/session identity, foreign server preservation, bounded startup.
- [x] Checksum-verified pinned Rokit/Luau bootstraps. No piping remote installers into a shell.
- [x] MCPKit rejects empty all-replace edits, bounds recorder rows/text, supports cancellation, emits correctly typed attributes, and refuses complex exports that would silently lose important asset data.
- [x] Cross-platform GitHub Actions configuration with read-only repository permissions and pinned action revisions.
- [x] Read-only advisory import scan; imported scripts/models require review before execution.

## Phase 2 implemented

- [x] Optional native Blender FBX exporter with shared art manifest, explicit meter units, selected hierarchies, geometry/material/texture budgets, source hashes, disabled embedded-script autoexecution and new-output-only promotion.
- [x] Blender 5.2.2 static-prop export/native reimport regression including geometry/scale/source fidelity and refusal of over-budget/overwrite operations.
- [x] Strict server Cooldown/Round/Economy modules and gameplay specs; no paid-receipt/durable-save claims.
- [x] Buildable Crystal Rush example with server authority, prompt/distance validation, shared rounds, data-backed HUD and debug hooks.
- [x] Stale UI show/hide tween cancellation and cleanup of idle camera-shake callbacks.

## Phase 3 prepared

- [x] Actual 0.1 scaffold upgrade, preserved game files/settings, backed-up prior code, real checker and Rojo build.
- [x] Claude Code 2.1.296 strict marketplace/plugin/component validation.
- [x] Measured standard-MCP vs compact-tree benchmark with raw results and adverse latency finding.
- [x] Cross-platform CI, example build and release acceptance ledger. Hosted results pending development PR checks.

## Validation evidence (2026-10-13)

| Check | Result | Scope |
|---|---|---|
| `python -m unittest discover -s tests -v` | 32 passed | Host regression fixtures; controlled tool subprocesses and filesystem operations |
| `python scripts/test-luau.py --luau .artifacts/tools/luau/luau.exe` | 34 passed, 0 worker errors | Shipped session/gameplay/example specs and lifecycle code under a deterministic scheduler and mock services |
| `python scripts/test-studio.py .artifacts/studio-test-bundle.luau`, then `execute_luau` | 45 passed | Actual Luau and engine Instances/TweenService in Studio Edit; unparented containers, simulated server context, memory stores |
| Generated project's `bash tools/check.sh` | OK | Actual pinned luau-lsp, Selene, Rojo; game libraries strict; dynamic inspection helper explicitly nonstrict |
| `python scripts/test-integration.py` | PASS | Actual Rojo 7.7.1 build, missing-service syncback, quoted names, prefix preservation, unchanged input place, MessagePack handshake, listener reuse |
| `python scripts/test-upgrade.py` | PASS | Actual 0.1 scaffold, preserved game files/ports/place IDs, old code backup, checker and Rojo build |
| `python scripts/prove-checker-fix.py` | PASS | Original checker returns `OK`/exit 0 when analyzer exits 42; current checker returns exit 1 |
| `python scripts/test-blender.py --blender <installed 5.2.2>` | PASS | Native static FBX export/reimport/scale, budget enforcement, source fidelity, output refusal; no Roblox upload/import |
| Crystal Rush scaffold | Check/build passed | Real Rojo .rbxlx generation and strict checking; rendered gameplay acceptance still pending |
| Claude Code 2.1.296 plugin validation | PASS | Strict marketplace, plugin manifest and skills; no model session |
| GitHub Actions | Pending hosted checks | Local validation above is separate; record the hosted run result after the development PR completes |

The Studio test bundle never parents instances to the user's place, installs game scripts, changes Play/Edit mode, or calls a persistent store. It does **not** prove a Rojo-connected game's Players lifecycle, real network traffic, physics, rendering, or live DataStore behavior.

## Required gates before calling V1 stable

- [ ] Run CI on Windows/macOS/Linux and validate the plugin in supported Claude Code versions.
- [ ] Fresh installation with empty tool caches and plugin install/reload; tool-bootstrap binaries and actual 0.1 upgrade were tested, full installation/reload still needs acceptance.
- [ ] Dedicated disposable Studio place: connect Rojo, start actual server/client and multi-client playtests, exercise DebugHooks and all libraries.
- [ ] Dedicated test experience/DataStore: two real servers contend for one player key, forced disconnect, throttling/outage, shutdown during load/save, restart round-trip. Never use production player keys.
- [ ] Validate large/UI/rig/terrain import fidelity and connection diff against original saved places; Workspace/Lighting remain owned by the original place.
- [ ] Blender rigs/animation/PBR fixtures and Studio reimport; local static-prop Blender round-trip already passed.
- [ ] Validate rendered example gameplay, touch/gamepad, server authority under adversarial network requests and target-device performance.
- [x] Controlled tree benchmark: 22,883 vs 2,480 output chars; medians 34 vs 81 ms. Compact output reduced characters but increased call latency. Exact Claude tokens/cost were not measured.
- [ ] Broader equivalent-outcome game-development benchmark and exact provider token accounting.
- [ ] Approval for release version/tag, merge and publication.

## Remaining implementation priorities

1. Dedicated multi-client, provider-failure and target-device acceptance, plus full plugin install/reload verification.
2. Native Creator Store quarantine/review integration; the advisory file import scan is not a full asset quarantine or proof of safety.
3. Versioned migrations and durable developer-product receipt handling require separate design and provider tests; generic in-game Economy helpers must not replace receipt processing.
4. Animation/PBR/Roblox mesh import round-trips, rendered art review and broader measured workflow benchmarks.

## Review ownership

| Worker | Role | Writable paths | Branch | State |
|---|---|---|---|---|
| Codex root | implement/integrate/verify | authorized repo changes | dev/v1-stability | active |
| Codex stability_review | bounded independent boundary review | none | dev/v1-stability (read-only) | complete; follow-up found no unresolved objections |

No Claude model worker was launched. Root remains responsible for reviewing raw findings and verification; the audit is not a live-provider certification.

Independent review found three concrete gaps: failed release after leaving during load was discarded; a false stored record became a fresh template; a same-name startup response could be attributed to the wrong process. All three were fixed with regression coverage. Root reran headless/host checks and actual Rojo integration; the follow-up review found no concrete unresolved objections within those three boundaries.

Every implementation result must retain its scope: a headless pass is not a live provider pass; a successful file export is not a published or visually reviewed asset.
