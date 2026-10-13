# Roadmap

## Next: Creator Store assets (planned, not started)
Use the Roblox Creator Store safely from Claude. The Studio MCP already has `search_asset` / `insert_asset`; roblox-kit adds the safety and project integration around them.
- **`/roblox-kit:asset <what>`**: search (prefer verified creators, free, roblox-kit-format kits), compare thumbnails, then insert into a **quarantine folder** (`ServerStorage.Quarantine`), never straight into the live game.
- **Backdoor scan** before use: `require(<assetId>)`, `loadstring`, `getfenv`/`setfenv`, HttpService calls, MarketplaceService prompts, TeleportService, obfuscated/encoded strings, hidden or disabled scripts, scripts inside meshes/decals' parents. Report what the asset contains and every flag; the user approves.
- **Into files:** approved assets get exported to `src/world/` (`K.toModelJson`) or `src/` so git tracks them.
- Respect cross-owner consent (inserting another creator's inventory asset needs the user's explicit OK).

## Later: community kit library
Reusable systems (shop, round loop, abilities like the Power Coin) packaged as kits: code + manifest (name, version, settings, a usage guide written for Claude) + tests + debug hooks. Shared via the Creator Store (Open Cloud Assets API uploads `.rbxm` models as packages; needs a user API key; making it public is a Creator Dashboard step) and installed with `/roblox-kit:add`, through the same quarantine + scan as above. Open question: whether Rojo-built `.rbxm` files upload correctly (Roblox warns files made outside Studio might not).
