# V1 stable — waivers (approved, deferred to v1.1)

**Status: APPROVED by the repository owner (TanaTTV) on 2026-10-19: all nine pending gates are deferred to v1.1.** Each is recorded in [gates.json](gates.json) as `waived` with `approved_by`, `reason` and an evidence record pointing here. These are known limitations of 1.0.0, not passes.

As of 2026-10-19: **4 passed** (Blender static/PBR, Blender rig/animation, terrain import, forced disconnect), **9 pending**. Each pending gate needs either the owner's hands (a device, a controller, a new private test experience, an interactive Claude session) or something that can't be produced safely at all (a real Roblox outage).

| Gate | What exists | What is missing | Risk if waived | Proposed handling |
|---|---|---|---|---|
| `device-emulator-touch` | Pure HUD layout suite (CI), UI library 48 px touch minimum, `DeviceSafeInsets`; Element Brawl moves its HUD for touch and has touch buttons | Device Emulator run: presets, rotation, notch, 44 px prompt measurement | Layout glitches on small phones in the **examples** (the library is unaffected) | Waive for 1.0; listed as a known gap in the release notes. Or ~10 min in the emulator. |
| `device-gamepad` | Keyboard E path passed; synthetic ButtonX awarded +1 ([evidence](evidence/2026-10-15-studio-input-partial.md)); ContextActionService bindings for ButtonX/R2 | A real controller with `LastInputType = Gamepad1` | Controller-only players could hit an input edge case | Waive for 1.0, or ~5 min with a controller. |
| `device-physical-performance` | Small parts-only example maps; light counts budgeted | FPS/frame time on a real phone | Unknown frame rate on low-end phones | Waive for 1.0. |
| `streaming-streamout` | Solo: real stream-out/in, HUD without crystals, late claimed and reset state, distant/duplicate/teleport denial all passed ([evidence](evidence/2026-10-18-streaming-solo.md)) | Local Server + 2 Players: shared countdown, a crystal claimed by the *other* player arriving hidden | Low: the same server-owned replication path was exercised solo | Waive the 2-player part, or ~5 min: Test → Clients and Servers → 2 players. |
| `datastore-engine-shutdown-restart` | Beta live suite: shutdown flush 7/7; Studio engine shutdown during load, save and a persistent outage, bounded at 25 s ([evidence](evidence/2026-10-18-lifecycle-faults.md)) | A real *live* server stop and a fresh server restart reading the data back | Low–medium: the shutdown path is shared, the provider is not | Waive for 1.0, or run with a new private test experience. |
| `datastore-natural-lock-expiry` | Stale-lock takeover passed live (aged fixture) and headless | Waiting ≥601 real seconds against the live provider | Low: lock expiry is a timestamp comparison already tested | Waive for 1.0. |
| `datastore-independent-servers` | Session-lock contention passed live in one Studio process; ownership tokens and fenced writes unit tested | Two separate Studio server processes, same key | Low–medium | Waive for 1.0, or run with a new private test experience. |
| `datastore-provider-failures` | Injected throttling/outage retries in the shipped Luau suite, the live budget scenario and the Studio lifecycle harness; real request budgets observed | A *real* Roblox throttle or outage | Real failure modes may differ from injected ones | Waive: a real outage can't be produced safely, and deliberately throttling is not allowed. |
| `plugin-interactive-reload` | Isolated install/upgrade test (CI), remote marketplace install verified | Fresh interactive Claude Code session running `/reload-plugins` and the commands | Low: the files and hooks are verified; only the interactive reload is unobserved | Waive for 1.0, or ~5 min in a fresh session. |

## v1.1

Each row above is a v1.1 task: run the missing check and replace the waiver with pass evidence (or a fix plus pass evidence). The DataStore rows need a new private disposable test experience under the existing [runbook](../datastore/README.md).
