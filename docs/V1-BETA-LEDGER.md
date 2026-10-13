# V1 beta acceptance ledger

Integration branch: `dev/v1-beta` (from `main` @ `dd513cb`). Worker branches: `dev/v1-beta-<topic>`; the orchestrator reviews and merges them here. Nothing is published, released or merged to `main` without owner approval.

Status: PASS · FAIL · BLOCKED · NOT TESTED · IN PROGRESS. Evidence kinds: **host** (Python fixtures), **headless** (Luau + mock services), **Studio** (real engine, disposable place), **multiplayer** (Studio Local Server + clients), **live** (published test experience / real DataStore).

| # | Requirement | Status | Evidence / owner |
|---|---|---|---|
| 1 | Core workflows: new project, check, build, import, upgrade, dev server | PASS (PR #1) | host 35, headless 43, Studio 54, integration/upgrade scripts, CI run 38445802422 |
| 2 | Fresh plugin install with empty caches + 0.1.0 → current upgrade | PASS (host, Windows local + CI Ubuntu/Windows) | `scripts/test-install.py` 8/8; real `~/.claude/plugins` hash unchanged; CI run 38449394466. Finding: same-version `plugin update` keeps stale cache → reinstall documented; version bump needed before release (owner) |
| 3 | Touch / gamepad / small-screen (Crystal Rush HUD, prompts) | PARTIAL | Studio: HUD inside safe area, centred, below top bar (998×576); layout math PASS for 320×568…1920×1080 (computed, headless + Studio); E/ButtonX prompts set. NOT TESTED: real Device Emulator insets/touch, physical gamepad, target-device performance |
| 4 | Crystal Rush: StreamingEnabled + amethyst art pass | PASS (Studio rendered) / stream-out NOT TESTED | Crystals render purple glass, bloom subtle; pickup +1 coin, light/prompt disabled; 0 game errors. Radii non-scriptable (set via built place). Stream-out impossible to observe on 80-stud map with 128-stud target radius |
| 5 | Blender: `use_nodes` deprecation | PASS on 5.2.2 (Blender 6 not installed) | W2, test-blender.py PASS |
| 5b | Blender rig/animation/PBR fixtures | IN PROGRESS | W6 |
| 6 | Net rejection counters / persistent-abuse summary | PASS (headless) | 6 new Net specs; independent review R1 in progress |
| 7 | StyLua format + CI format check | PASS (CI) | CI run 38449394466 |
| 8 | Real DataStore acceptance (published *test* experience only) | BLOCKED (owner approval to publish a test place) | W4 preparing harness (no publishing) |
| 9 | Import fidelity (large/UI/rig/terrain) | NOT TESTED | next wave |
| 10 | Performance + token-efficiency benchmark (measured, no invented numbers) | NOT TESTED | next wave |
| 11 | Representative end-to-end workflow demonstration | NOT TESTED | orchestrator, after integration |
| 12 | Independent security/persistence review of all V1-beta changes | IN PROGRESS | R1 (Claude Sonnet, read-only) |
| 13 | GitHub CI green on integration branch | PASS @ 410888c | run 38449394466: stability ×3, install ×2, plugin |
| 14 | Release version/tag/publication | BLOCKED (owner decision) | — |
