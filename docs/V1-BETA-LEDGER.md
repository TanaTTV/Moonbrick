# V1 beta acceptance ledger

Integration branch: `dev/v1-beta` (from `main` @ `dd513cb`). Worker branches: `dev/v1-beta-<topic>`; the orchestrator reviews and merges them here. Nothing is published, released or merged to `main` without owner approval.

Status: PASS · FAIL · BLOCKED · NOT TESTED · IN PROGRESS. Evidence kinds: **host** (Python fixtures), **headless** (Luau + mock services), **Studio** (real engine, disposable place), **multiplayer** (Studio Local Server + clients), **live** (published test experience / real DataStore).

| # | Requirement | Status | Evidence / owner |
|---|---|---|---|
| 1 | Core workflows: new project, check, build, import, upgrade, dev server | PASS (PR #1) | host 35, headless 43, Studio 54, integration/upgrade scripts, CI run 38445802422 |
| 2 | Fresh plugin install with empty caches + 0.1.0 → current upgrade | PASS (Windows local full mode; CI Ubuntu/Windows) | `scripts/test-install.py` 9/9 incl. real `settings.json` + plugins guards; version 1.0.0-beta.1 makes plain `claude plugin update` refresh 0.1.0 (verified, no stale files). Remote marketplace + in-session `/reload-plugins` NOT TESTED |
| 3 | Touch / gamepad / small-screen (Crystal Rush HUD, prompts) | PARTIAL | Studio: HUD inside safe area, centred, below top bar (998×576); layout math PASS for 320×568…1920×1080 (computed, headless + Studio); E/ButtonX prompts set. NOT TESTED: real Device Emulator insets/touch, physical gamepad, target-device performance |
| 4 | Crystal Rush: StreamingEnabled + amethyst art pass | PASS (Studio rendered) / stream-out NOT TESTED | Crystals render purple glass, bloom subtle; pickup +1 coin, light/prompt disabled; 0 game errors. Radii non-scriptable (set via built place). Stream-out impossible to observe on 80-stud map with 128-stud target radius |
| 5 | Blender: `use_nodes` deprecation | PASS on 5.2.2 (Blender 6 not installed) | W2, test-blender.py PASS |
| 5b | Blender rig/animation/PBR fixtures | PASS (Blender 5.2.2 headless) | PBR 4 maps + manifest, 3-bone skinned rig, 25-frame action, 6 refusal cases, non-PBR NPOT allowed. Roblox import/render NOT TESTED; Blender 6 not installed |
| 6 | Net rejection counters / persistent-abuse summary | PASS (headless) | 63 headless Luau specs; reviewed twice (R1, R2), fixes merged |
| 7 | StyLua format + CI format check | PASS (CI) | CI run 38449394466 |
| 8 | Real DataStore acceptance (published *test* experience only) | BLOCKED (owner publishing step) | Owner approved 2026-10-13. Harness: allowlist + confirmation + Studio-server gates, universe must contain no other DataStore, run-authored writes/cleanup, 40+20 request cap; headless PASS; R2 verdict: safe to run |
| 9 | Import fidelity (large/UI/rig/terrain) | PASS (real Rojo, synthetic places) | `scripts/test-import-fidelity.py`: 2,369 instances / 332 scripts, .rbxlx + .rbxl, full property + sibling-order diff, 0 unexpected differences; import 1.6 s. Terrain voxels + live Studio connection NOT TESTED |
| 10 | Performance + token-efficiency benchmark (measured, no invented numbers) | PASS (measured; result is not a saving) | `docs/BENCHMARK.md`, Sonnet, n=3/condition: plugin merely installed → skills never invoked, cost ≈ baseline ($0.147 vs $0.156 median); told to use Moonbrick → 3/3 used it, session-locked PlayerData in 3/3 vs naive DataStore in 6/6 baseline, ≈1.9× median cost ($0.293). All 9 runs pass headless/static checks. Studio tree benchmark: fewer chars, higher latency |
| 11 | Representative end-to-end workflow demonstration | PASS (headless + Studio, separate) | Benchmark E runs: Claude Code + Moonbrick from empty dir → scaffold → feature → strict check/lint/build (3/3). Crystal Rush: built, synced to Studio, played (pickup, HUD, multiplayer in PR #1 QA). Not one continuous session |
| 12 | Independent security/persistence review of all V1-beta changes | PASS (2 rounds) | R1 + R2 (Claude Sonnet, read-only); all MED findings fixed (F1, F2a, F2b) |
| 13 | GitHub CI green on integration branch | PASS @ a979997 (latest push pending) | stability ×3, install ×2, plugin |
| 14 | Release version/tag/publication | BLOCKED (owner decision) | — |

## Known limitations found during V1 beta

- Moonbrick skills are not invoked automatically for a terse, constraint-heavy headless prompt; users should start with `/moonbrick:new` (documented in README). Measured in `docs/BENCHMARK.md`.
- Explicit Moonbrick use costs more tokens on a small task (≈1.9× median) in exchange for session-locked saves and validated remotes; no token saving is claimed.
