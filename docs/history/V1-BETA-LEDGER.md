# V1 beta acceptance ledger

> Historical (1.0.0-beta.1). Stable 1.0 gates and evidence are in [acceptance/v1-stable](../../acceptance/v1-stable/).

Integration branch: `dev/v1-beta` (from `main` @ `dd513cb`). Worker branches: `dev/v1-beta-<topic>`; the orchestrator reviews and merges them here. Nothing is published, released or merged to `main` without owner approval.

Status: PASS · FAIL · BLOCKED · NOT TESTED · IN PROGRESS. Evidence kinds: **host** (Python fixtures), **headless** (Luau + mock services), **Studio** (real engine, disposable place), **multiplayer** (Studio Local Server + clients), **live** (published test experience / real DataStore).

| # | Requirement | Status | Evidence / owner |
|---|---|---|---|
| 1 | Core workflows: new project, check, build, import, upgrade, dev server | PASS (PR #1) | host 35, headless 43, Studio 54, integration/upgrade scripts, CI run 38445802422 |
| 2 | Fresh plugin install with empty caches + 0.1.0 → current upgrade | PASS (Windows local full mode; CI Ubuntu/Windows) | `scripts/test-install.py` 9/9 incl. real `settings.json` + plugins guards; version 1.0.0-beta.1 makes plain `claude plugin update` refresh 0.1.0 (verified, no stale files). Remote GitHub marketplace install (`https://github.com/TanaTTV/Moonbrick.git#dev/v1-beta`, isolated config) PASS: enabled 1.0.0-beta.1, installed skills/hooks/libs byte-identical (2026-10-14). In-session `/reload-plugins` NOT TESTED (interactive) |
| 3 | Touch / gamepad / small-screen (Crystal Rush HUD, prompts) | PARTIAL | Studio: HUD inside safe area, centred, below top bar (998×576); layout math PASS for 320×568…1920×1080 (computed, headless + Studio); E/ButtonX prompts set. NOT TESTED: real Device Emulator insets/touch, physical gamepad, target-device performance |
| 4 | Crystal Rush: StreamingEnabled + amethyst art pass | PASS (Studio rendered) / stream-out NOT TESTED | Crystals render purple glass, bloom subtle; pickup +1 coin, light/prompt disabled; 0 game errors. Radii non-scriptable (set via built place). Stream-out impossible to observe on 80-stud map with 128-stud target radius |
| 5 | Blender: `use_nodes` deprecation | PASS on 5.2.2 (Blender 6 not installed) | W2, test-blender.py PASS |
| 5b | Blender rig/animation/PBR fixtures | PASS (Blender 5.2.2 headless) | PBR 4 maps + manifest, 3-bone skinned rig, 25-frame action, 6 refusal cases, non-PBR NPOT allowed. Roblox import/render NOT TESTED; Blender 6 not installed |
| 6 | Net rejection counters / persistent-abuse summary | PASS (headless) | 63 headless Luau specs; reviewed twice (R1, R2), fixes merged |
| 7 | StyLua format + CI format check | PASS (CI) | CI run 38449394466 |
| 8 | Real DataStore acceptance (published *test* experience only) | PASS (live suite; extras NOT TESTED) | 2026-10-15, new private disposable experience, Studio server, run b579eaf71c85: roundtrip, contention, stale (seeded), shutdown (library callback), invalid + sanitize, budget (injected throttles) = 7 passed, 0 failed; `LEFTOVERS: none`; 51/60 requests; cleanup verified via uncached reads. Confirmation switch reset to false. NOT TESTED: real engine shutdown/restart, natural 600 s lock expiry, two-server contention, real provider throttling/outage. IDs deliberately not recorded in the repo |
| 9 | Import fidelity (large/UI/rig/terrain) | PASS (real Rojo, synthetic places) | `scripts/test-import-fidelity.py`: 2,369 instances / 332 scripts, .rbxlx + .rbxl, full property + sibling-order diff, 0 unexpected differences; import 1.6 s. Terrain voxels + live Studio connection NOT TESTED |
| 10 | Performance + token-efficiency benchmark (measured, no invented numbers) | PASS (measured; result is not a saving) | `docs/BENCHMARK.md`, Sonnet, n=3/condition: plugin merely installed → skills never invoked, cost ≈ baseline ($0.147 vs $0.156 median); told to use Moonbrick → 3/3 used it, session-locked PlayerData in 3/3 vs naive DataStore in 6/6 baseline, ≈1.9× median cost ($0.293). All 9 runs pass headless/static checks. Studio tree benchmark: fewer chars, higher latency |
| 11 | Representative end-to-end workflow demonstration | PASS (headless + Studio, separate) | Benchmark E runs: Claude Code + Moonbrick from empty dir → scaffold → feature → strict check/lint/build (3/3). Crystal Rush: built, synced to Studio, played (pickup, HUD, multiplayer in PR #1 QA). Not one continuous session |
| 12 | Independent security/persistence review of all V1-beta changes | PASS (2 rounds) | R1 + R2 (Claude Sonnet, read-only); all MED findings fixed (F1, F2a, F2b) |
| 13 | GitHub CI green on integration branch | PASS @ 55622d8 | stability ×3 (ubuntu/windows/macos), install ×2, plugin; runs 38693414155, 38693410354. Earlier red @ 252d51e was a bench path-resolution bug, fixed in 55622d8 |
| 14 | Release version/tag/publication | PASS (owner approved 2026-10-15) | PR #2 merged to `main` @ 1862e39; tag `v1.0.0-beta.1`; published as a GitHub pre-release. Not a stable 1.0 |

## Known limitations found during V1 beta

- Moonbrick skills are not invoked automatically for a terse, constraint-heavy headless prompt; users should start with `/moonbrick:new` (documented in README). Measured in `docs/BENCHMARK.md`.
- Explicit Moonbrick use costs more tokens on a small task (≈1.9× median) in exchange for session-locked saves and validated remotes; no token saving is claimed. *Superseded in 1.0:* with the API card and recipes, a same-batch run cost the same as the baseline ($0.217 vs $0.220 median); see [BENCHMARK-SUMMARY](../BENCHMARK-SUMMARY.md).
