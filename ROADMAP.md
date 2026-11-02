# Roadmap

## v1.2

Close the nine stable gates waived for 1.0 (moved from v1.1, which shipped the creative engine) ([WAIVERS.md](acceptance/v1-stable/WAIVERS.md)): Device Emulator touch, real gamepad, real-phone performance, 2-player streaming, live DataStore engine restart, natural lock expiry and two independent servers (in a new private test experience), provider-failure evidence, and an interactive `/reload-plugins` check.

The 1.0 stable gates and their evidence, including what is still untested, are in [acceptance/v1-stable/](acceptance/v1-stable/) (waivers approved 2026-10-19: [WAIVERS.md](acceptance/v1-stable/WAIVERS.md)); the beta evidence is in [docs/history/V1-BETA-LEDGER.md](docs/history/V1-BETA-LEDGER.md) and earlier history in [docs/history/V1-STATUS.md](docs/history/V1-STATUS.md). See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and [docs/BENCHMARK-STUDIO-TREE.md](docs/BENCHMARK-STUDIO-TREE.md).

## v1.2 also: prove the design work

- **Phones first.** The `level-design` phone rules are working rules; no phone has been measured.
- **Scale check.** Confirm the importer's Meters setting on a real asset, and confirm the default jump numbers on current avatars.
- **Behaviour tests.** Measure whether plain requests ("make a Roblox game", "make a fireball", "build a map") reach the right skill, with `claude plugin eval`. Nothing has measured this.
- **Same-level test.** Build one small level and one effect before and after each design change, and play both. Numbers won't show whether a level is fun.
- **`playtester` agent**, only if measurement justifies it.

## Next: Creator Store assets (planned, not started)
Use the Roblox Creator Store safely from Claude. The Studio MCP already has `search_asset` / `insert_asset`; moonbrick adds the safety and project integration around them.
- **`/moonbrick:asset <what>`**: search (prefer verified creators, free, moonbrick-format kits), compare thumbnails, then insert into a **quarantine folder** (`ServerStorage.Quarantine`), never straight into the live game.
- **Backdoor scan** before use: `require(<assetId>)`, `loadstring`, `getfenv`/`setfenv`, HttpService calls, MarketplaceService prompts, TeleportService, obfuscated/encoded strings, hidden or disabled scripts, scripts inside meshes/decals' parents. Report what the asset contains and every flag; the user approves.
- **Into files:** approved assets get exported to `src/world/` (`K.toModelJson`) or `src/` so git tracks them.
- Respect cross-owner consent (inserting another creator's inventory asset needs the user's explicit OK).

## Later: community kit library
Reusable systems (shop, round loop, abilities) packaged as kits: code + manifest (name, version, settings, a usage guide written for Claude) + tests + debug hooks. Shared via the Creator Store (Open Cloud Assets API uploads `.rbxm` models as packages; needs a user API key; making it public is a Creator Dashboard step) and installed with `/moonbrick:add`, through the same quarantine + scan as above. Open question: whether Rojo-built `.rbxm` files upload correctly (Roblox warns files made outside Studio might not).
