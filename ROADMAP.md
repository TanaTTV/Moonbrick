# Roadmap

## v1.1

Close the nine stable gates waived for 1.0 ([WAIVERS.md](acceptance/v1-stable/WAIVERS.md)): Device Emulator touch, real gamepad, real-phone performance, 2-player streaming, live DataStore engine restart, natural lock expiry and two independent servers (in a new private test experience), provider-failure evidence, and an interactive `/reload-plugins` check.

The 1.0 stable gates and their evidence, including what is still untested, are in [acceptance/v1-stable/](acceptance/v1-stable/) (proposed waivers: [WAIVERS.md](acceptance/v1-stable/WAIVERS.md)); the beta evidence is in [docs/V1-BETA-LEDGER.md](docs/V1-BETA-LEDGER.md) and earlier history in [docs/V1-STATUS.md](docs/V1-STATUS.md). See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Next: Creator Store assets (planned, not started)
Use the Roblox Creator Store safely from Claude. The Studio MCP already has `search_asset` / `insert_asset`; moonbrick adds the safety and project integration around them.
- **`/moonbrick:asset <what>`**: search (prefer verified creators, free, moonbrick-format kits), compare thumbnails, then insert into a **quarantine folder** (`ServerStorage.Quarantine`), never straight into the live game.
- **Backdoor scan** before use: `require(<assetId>)`, `loadstring`, `getfenv`/`setfenv`, HttpService calls, MarketplaceService prompts, TeleportService, obfuscated/encoded strings, hidden or disabled scripts, scripts inside meshes/decals' parents. Report what the asset contains and every flag; the user approves.
- **Into files:** approved assets get exported to `src/world/` (`K.toModelJson`) or `src/` so git tracks them.
- Respect cross-owner consent (inserting another creator's inventory asset needs the user's explicit OK).

## Later: community kit library
Reusable systems (shop, round loop, abilities like the Power Coin) packaged as kits: code + manifest (name, version, settings, a usage guide written for Claude) + tests + debug hooks. Shared via the Creator Store (Open Cloud Assets API uploads `.rbxm` models as packages; needs a user API key; making it public is a Creator Dashboard step) and installed with `/moonbrick:add`, through the same quarantine + scan as above. Open question: whether Rojo-built `.rbxm` files upload correctly (Roblox warns files made outside Studio might not).
