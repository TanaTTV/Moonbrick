# V1 beta acceptance ledger

Integration branch: `dev/v1-beta` (from `main` @ `dd513cb`). Worker branches: `dev/v1-beta-<topic>`; the orchestrator reviews and merges them here. Nothing is published, released or merged to `main` without owner approval.

Status: PASS · FAIL · BLOCKED · NOT TESTED · IN PROGRESS. Evidence kinds: **host** (Python fixtures), **headless** (Luau + mock services), **Studio** (real engine, disposable place), **multiplayer** (Studio Local Server + clients), **live** (published test experience / real DataStore).

| # | Requirement | Status | Evidence / owner |
|---|---|---|---|
| 1 | Core workflows: new project, check, build, import, upgrade, dev server | PASS (PR #1) | host 35, headless 43, Studio 54, integration/upgrade scripts, CI run 38445802422 |
| 2 | Fresh plugin install with empty caches + 0.1.0 → current upgrade | IN PROGRESS | W1 `dev/v1-beta-install` |
| 3 | Touch / gamepad / small-screen (Crystal Rush HUD, prompts) | IN PROGRESS | W3 code; orchestrator Device Emulator check in Studio |
| 4 | Crystal Rush: StreamingEnabled + amethyst art pass | IN PROGRESS | W3 code; orchestrator rendered review |
| 5 | Blender: `use_nodes` deprecation | IN PROGRESS | W2 |
| 5b | Blender rig/animation/PBR fixtures | NOT TESTED | next wave |
| 6 | Net rejection counters / persistent-abuse summary | IN PROGRESS | W2 |
| 7 | StyLua format + CI format check | IN PROGRESS | W2 |
| 8 | Real DataStore acceptance (published *test* experience only) | BLOCKED (owner approval to publish a test place) | harness to be prepared next wave |
| 9 | Import fidelity (large/UI/rig/terrain) | NOT TESTED | next wave |
| 10 | Performance + token-efficiency benchmark (measured, no invented numbers) | NOT TESTED | next wave |
| 11 | Representative end-to-end workflow demonstration | NOT TESTED | orchestrator, after integration |
| 12 | Independent security/persistence review of all V1-beta changes | NOT TESTED | after integration |
| 13 | GitHub CI green on integration branch | NOT TESTED | after first integration push |
| 14 | Release version/tag/publication | BLOCKED (owner decision) | — |
