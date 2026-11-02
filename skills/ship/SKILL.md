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
- [ ] **No local-only assets.** `grep -rnE "usePreview|rbxasset://(textures|sounds)/moonbrick" src`: any hit is a no-go. Those files exist only on this PC, so players get broken effects and silence. Upload them (owner's account, ask first) and use `Tex.useFiles` and uploaded sound ids.
- [ ] **Mesh & Image APIs.** If `src/` uses `Geo`, `GeoShapes` or runtime `Tex` images, the owner must turn on Game Settings → Security → "Allow Mesh & Image APIs". Tools can't read this setting, so ask them to confirm it; without it those meshes and images don't appear for players.
- [ ] Rojo is connected and synced: read a recently changed script in Studio with `K.src` and compare it with its file. The place is saved (ask the user): publishing publishes the place, not the files.

**Should pass (warn)**
- [ ] Every interaction works on gamepad (ProximityPrompt/GUI selection) and touch (buttons ≥ 48 px).
- [ ] `K.perf()`: part counts reasonable for phones; `StreamingEnabled` on for large maps.
- [ ] First-time experience: goal visible within 10 s of spawning.
- [ ] No leftover test objects, disabled scripts, or "Button"-labelled UI (audit lists them).

**Release**
- [ ] Commit, then `git tag v<version>` (ask the user for the version; suggest semver from the changes).
- [ ] Summarize the release notes for the user (player-facing changes first).
