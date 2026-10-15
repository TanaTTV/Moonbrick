# 2026-10-15 — Studio input checks (partial, does not close a gate)

- **Repo commit:** d45f9f5 (`qa/v1-stable-acceptance-gates`)
- **Studio:** 0.743.0.7431133, Windows 11
- **Place:** fresh `python scripts/create-example.py` → `bash tools/check.sh` (OK) → `rojo build`; local unpublished file (PlaceId 0), memory-only persistence
- **Driver:** Claude Code orchestrator through the Roblox Studio MCP, Play Solo (1 player), **no Device Emulator / Controller Emulator preset**

## Observed

| Check | Expected | Observed | Result |
|---|---|---|---|
| Edit-mode `K.test()` | all pass | 59/60; `VFX_UI` server-refusal spec failed with a stale nested require (documented edit-mode caveat) | n/a |
| Playtest `K.test()` | all pass | 60 passed, 0 failed | pass |
| Workspace streaming | enabled | `StreamingEnabled=true` (radii are not scriptable, not read) | pass |
| Lighting post effects | only `CrystalBloom` | `CrystalBloom` **and** `ColorGrading` (ColorGradingEffect, enabled); absent from the built `.rbxlx` (only `BloomEffect`), so Studio added it on open | expected (README updated) |
| Keyboard **E** collection | prompt shows `E / Collect / Amethyst`, +1 crystal, +1 coin, shard hidden | walked with `Humanoid:MoveTo`, `PromptShown` fired, real `E` keypress → HUD `Crystals: 1 Coins: 1`, prompt disabled, light off, Transparency 1, logs clean | pass |
| **ButtonX** collection | +1 | synthetic `ButtonX` keypress → HUD `Crystals: 2 Coins: 2`, logs clean; `UserInputService:GetLastInputType()` stayed `Keyboard`, so this was not a real gamepad input path | inconclusive |

## Not covered (gates stay pending)

- `device-emulator-touch`: no emulator preset, touch thumbstick, safe-area, notch, rotation or 44px measurement was exercised. Needs the Studio Device Emulator selected by a human (the MCP cannot switch presets or send touch).
- `device-gamepad`: needs Controller Emulator or a physical pad (movement, jump, X) with `LastInputType=Gamepad1`.
- `ColorGrading` is a Studio default, not a Moonbrick defect; the Crystal Rush README check now says so.
