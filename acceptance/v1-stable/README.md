# V1 stable acceptance — execution and evidence

**Baseline:** [v1.0.0-beta.1](../../docs/V1-BETA-LEDGER.md) is released, not stable 1.0. This folder records additional release gates; its existence is **not evidence** that the tests ran.

## Check current readiness (offline, no Roblox access)

    python scripts/check-stable-acceptance.py
    python scripts/check-stable-acceptance.py --release
    python -m unittest discover -s tests -p test_stable_acceptance.py -v

The report command exits 0 for a *valid* pending ledger. The optional release check exits nonzero while any of the 13 required gates remain pending or failed. It only checks that evidence records exist and are well-shaped, **not** that screenshots or test logs are authentic. It is not permission to publish, change player data, or waive testing.

## Run the tests in this order

1. **Crystal Rush touch and gamepad** — Build a fresh example with the [Crystal Rush README](../../examples/crystal-rush/README.md#device-support). Open only the newly built **local disposable place**. Leave Studio persistence in its memory-only default. In Device Emulator check 320×568 portrait, 568×320 landscape, notched phone orientations and 768×1024 / 1024×768 tablet; try walking, jumping, native prompt collection, mid-notice rotation, top-bar/notch safe area, at least 44px prompt target and exact +1 reward. For controller, check movement/jump and X; regress keyboard E. Capture before/after screenshots and server Output; layout calculations alone do not pass this test.
2. **Physical device and streaming** — Record target phone model, Roblox version, FPS/frame time and visible controls at low/high graphics. On an **extended disposable map**, observe real stream-out and return/stream-in, late crystal claims, and 2-player rewards, including duplicate/distant-request denial. If stream-out never happens, record it as **inconclusive** rather than passing. The Device Emulator is not a hardware performance test.
3. **Blender to Studio** — Run the existing offline native fixture (python scripts/test-blender.py --blender PATH), then follow the [assets skill](../../skills/assets/SKILL.md). Import the generated static FBX in an isolated Studio review container; check rendered mesh normals, scale, UV and all four manually assigned SurfaceAppearance textures. Separately import the rig/animation FBX via 3D Importer and Animation Editor, and observe correct bones, clip, scale and playback deformation. Do not upload/publish assets without explicit approval.
4. **Terrain/original-place import** — Make a disposable terrain-containing place with varied materials and voxels. Save the original; use /moonbrick:import only into a new destination, inspect the Rojo connection diff and compare the rendering/materials/collision in Studio. Preserve the original saved place. The completed 2,369-instance synthetic import test does not establish live terrain fidelity.
5. **Live DataStore extras** — The [existing safety runbook](../datastore/README.md) is authoritative. Its beta suite already passed 7/7, but **not** natural 601-second lock expiry, real engine shutdown/restart, two independent Studio server processes, real provider outage or forced disconnect. A *new private disposable experience*, explicit owner approval, exact place/universe allowlist, manual confirmation attribute, bounded calls and verified key cleanup are prerequisites. Use shutdown-arm/shutdown-verify; stale-arm/stale-verify after >=601 real seconds; contender-a/contender-b from **two separate Studio server environments**, saving both Outputs. Never use production data or intentionally cause provider throttling. Actual outage/forced-disconnect/early-shutdown scenarios need separate safe evidence or an explicit risk-reviewed owner waiver.
6. **Interactive plugin reload** — In a fresh Claude Code session with an isolated profile, install published beta, run /reload-plugins, then /moonbrick:new into an empty directory. Record version, available skills, hook behavior and check/build; the already-passed non-model install fixture does not prove this interactive scenario.

## Recording evidence

Update [gates.json](gates.json) one gate at a time only **after** observing and documenting it. Every gate begins as pending. Status values: pending, passed, failed, waived. Each passed gate needs evidence with all four string fields:

- **reference** — GitHub issue/PR comment or checked-in sanitized report/screenshots
- **environment** — Studio/build version, device profile, local/test place context
- **result** — pass, fail, or inconclusive
- **date** — YYYY-MM-DD

Example *format only*, **not test proof**:

    {
      "id": "device-emulator-touch",
      "status": "passed",
      "evidence": [{
        "reference": "https://github.com/TanaTTV/Moonbrick/issues/NUMBER#issuecomment-NUMBER",
        "environment": "Roblox Studio build X; phone preset Y; local Crystal Rush",
        "result": "pass",
        "date": "2026-10-15"
      }],
      "notes": "Observed behavior and remaining limitations"
    }

A waiver requires an **approved_by** person, **reason**, and evidence recording the review. The validator checks that fields exist; a human must verify that approval actually happened. Treat missing, mixed or contradictory case coverage as still pending/failed. Link the exact repo commit, versions, expected versus actual behavior and reproducible steps. **Never put live place/universe IDs, credentials, private player data or sensitive DataStore logs in a public issue.**

## Stable 1.0 exit criteria

The 13 gates encompass touch, gamepad, physical performance, streaming, Studio Blender PBR and rig import, terrain fidelity, engine shutdown/restart, natural lock expiry, independent servers, provider failures, forced disconnect and interactive plugin reload. These gates are maintained explicitly by the checker so deleting an untested row cannot produce a false ready result.

Require source evidence, review each waiver, add regressions for real defects, and obtain **explicit owner approval** before changing the stable release version/tag. Beta CI stays green while evidence is gathered; this tracker does not claim that Studio, live servers or real devices have been exercised.
