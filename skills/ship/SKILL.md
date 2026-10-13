---
name: ship
description: Pre-publish checklist for a Roblox game — tests, type/lint check, audit, data-store safety, platform support, performance, and a tagged git release — so updates don't break live servers or lose player data. Use when the user is about to publish or update their game.
disable-model-invocation: true
---

# Ship checklist

Run everything, then give a go / no-go with reasons. Publishing itself is the user's action in Studio (File → Publish to Roblox).

**Must pass (no-go otherwise)**
- [ ] `bash tools/check.sh` → `OK`.
- [ ] Playtest: `K.test()` all passing; every feature's debug hooks run with `K.logs()` clean.
- [ ] `K.audit()` (Edit mode): no unvalidated remotes, no deprecated APIs in game code.
- [ ] **Data safety:** review template diff, changed store name and migrations. Studio uses memory by default; test persistent saves only with `studioStore = "live"` in a separate disposable test experience/store. Prove two-server locking, disconnect/rejoin, provider failures and shutdown round-trip. Never enable API access against production keys for testing. Developer-product receipt processing needs durable idempotence, not just an in-game purchase helper.
- [ ] Rojo is connected and synced (Studio shows the current code), and the place is saved — publishing publishes the place, not the files.

**Should pass (warn)**
- [ ] Every interaction works on gamepad (ProximityPrompt/GUI selection) and touch (buttons ≥ 48 px).
- [ ] `K.perf()`: part counts reasonable for phones; `StreamingEnabled` on for large maps.
- [ ] First-time experience: goal visible within 10 s of spawning.
- [ ] No leftover test objects, disabled scripts, or "Button"-labelled UI (audit lists them).

**Release**
- [ ] Commit, then `git tag v<version>` (ask the user for the version; suggest semver from the changes).
- [ ] Summarize the release notes for the user (player-facing changes first).
