---
name: ship
description: 'Pre-publish checklist for a Roblox game: tests, audit, data safety, local-only assets, platforms, then a tagged release. Use for "publish my game", "ship it", "release an update", "is this ready to go live".'
disable-model-invocation: true
---

# Ship checklist

Run everything, then give a go / no-go with reasons. Publishing itself is the user's action in Studio (File → Publish to Roblox).

**Must pass (no-go otherwise)**
- [ ] `bash tools/check.sh` → `OK`.
- [ ] Playtest: `K.test()` all passing; every feature's debug hooks run with `K.logs()` clean.
- [ ] `K.audit()` (Edit mode): no unvalidated remotes, no deprecated APIs in game code.
- [ ] **Data safety:** review template diff, changed store name and migrations. Studio uses memory by default; test persistent saves only with `studioStore = "live"` in a separate disposable test experience/store. Prove two-server locking, disconnect/rejoin, provider failures and shutdown round-trip; projects ship no harness for these, so report anything unproved as unproved, never as passing. Never enable API access against production keys for testing. Developer-product receipt processing needs durable idempotence, not just an in-game purchase helper.
- [ ] `python "${CLAUDE_PLUGIN_ROOT}/scripts/ship-check.py" .` exits 0. A blocker means a texture or sound exists only on this PC: upload it (owner's account, ask first), then use `Tex.useFiles` or the uploaded sound id.
- [ ] **Mesh & Image APIs.** If ship-check lists runtime mesh or image use, or `src/` uses `GeoShapes` or `Geo.watch`, the owner must turn on Game Settings → Security → "Allow Mesh & Image APIs". Tools can't read this setting, so ask them to confirm it; without it those meshes and images don't appear for players.
- [ ] Rojo is connected and synced: read a recently changed script in Studio with `K.src` and compare it with its file. The place is saved (ask the user): publishing publishes the place, not the files.

**Should pass (warn)**
- [ ] Every interaction works on gamepad (ProximityPrompt/GUI selection) and touch (buttons ≥ 48 px).
- [ ] `K.perf()`: part counts reasonable for phones; `StreamingEnabled` on for large maps.
- [ ] First-time experience: goal visible within 10 s of spawning.
- [ ] `python "${CLAUDE_PLUGIN_ROOT}/scripts/stylecheck.py" .`: hardcoded colours and fonts that bypass `ArtStyle`.
- [ ] No leftover test objects, disabled scripts, or "Button"-labelled UI (audit lists them).

**Release**
- [ ] Commit, then `git tag v<version>` (ask the user for the version; suggest semver from the changes).
- [ ] Summarize the release notes for the user (player-facing changes first).
