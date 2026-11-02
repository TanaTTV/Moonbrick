---
name: level-design
description: Design and build Roblox maps and levels: layout from the core loop, blockout, scale, guiding players, pacing, dressing, phone limits, review tours. Use for "build a map", "make a level", "design the lobby", "add a new area", "this map feels empty", "players get lost".
argument-hint: "[area, map or genre]"
---

# Level design

A level is the core loop laid out in space. Work in this order and don't skip ahead: dressing a layout that hasn't been walked wastes the most effort of anything in this skill.

## 1. Start from the loop
Read `docs/design.md`. Write down the core loop, session length and main device. Convert time to distance: a walking player covers 16 studs a second, so 100 studs is 6 seconds and a 30-second loop spans about 480 studs of travel. Too long means fewer stops or a shortcut; too short means players will see everything in the first minute.

## 2. Map as a text list
Add a `## Map` section to `docs/design.md` before placing a part:

```
Spawn plaza: safe, 60x60. Moment: see the tower, get told nothing, walk to it.
  → Market lane (120 long, 14 wide), compression
Tower yard: first danger. Moment: first loss, respawn 10 s away.
  → Rope bridge (one way) | → Sewer shortcut (unlocks after first win)
```

Each area gets a size, its job in the loop and **one moment**. No moment, no area: cut it. Loops beat dead ends; every dead end needs a reward. Passing: you can read the list aloud as a player's session. Show it to the user before building.

## 3. Block out in plain Parts
Greybox only: one neutral colour for walkable, one for hazard, one for goals. No materials, no props. Build under `Workspace.World`. Use real sizes from the numbers below, then playtest the route.

**Default character (confirm, don't assume).** Roblox documents WalkSpeed 16, gravity 196.2, JumpPower 50 with `CharacterUseJumpPower` true, or JumpHeight 7.2 when it's false. By ballistics that is a peak rise of 6.4 to 7.2 studs, about 0.5 s of air and 8 to 9 studs of flat distance. Those are calculated: measure a real test jump in your place on day one, using the checks below, and write the result in `docs/design.md`.

| Feature | Comfortable | Skilled | Never without a test |
|---|---|---|---|
| Rise onto a ledge | up to 4 | 5 | 6+ |
| Flat gap | 4 to 5 | 6 to 7 | 8+ |

Character is about 5 tall and 2 to 4 wide; avatars vary. Doors at least 6 wide, 9 high. Corridors 10+ wide and ceilings 12+ for third person, or the camera shoves in. Stairs rise at most 1 per 2 of tread. A landing pad 6x6 or bigger on anything a phone player must hit.

**Test jump.** In a playtest, sample `HumanoidRootPart.Position` with `K.record` through one jump over a ruled floor. Passing: measured rise and gap recorded, every required jump at least 1 stud under them.

## 4. Guide the eye
Players follow what stands out; signs are the last resort.
- **Landmark:** one tall, unique shape visible from spawn and from most of the map. Players navigate by it. It should be the first thing in a spawn screenshot.
- **Light:** the path out of any area is the brightest thing in that area. Warm pools against cool surroundings pull harder than arrows.
- **Colour:** reserve the `art.json` accent for goals and interactables. If props use it too, it stops meaning anything.
- **Framing:** arches, gaps and tree lines that point at the goal. Line up the first view of each area from its entrance.
- **Motion:** a moving thing (Fx ambience, a flag, another player) catches the eye before any static shape.

## 5. Pace it
- **Compression and release:** a narrow, low stretch makes the next open space feel huge. Put the best view right after the tightest squeeze.
- **Safe, then danger:** alternate. A safe stretch needs a checkpoint or rest within 20 seconds of any hard part, so failure stings but doesn't send players away.
- **Exploration pays:** every side route ends in a reward, a view or a shortcut; roughly one in three should be findable without help.
- **Escalation:** introduce a hazard alone in safety, then with a twist, then combined. Never a new idea and a new difficulty at once.

## 6. Dress in three layers
Only after the route survives a walkthrough.
1. **Big forms:** buildings, cliffs, large trees. Set the skyline. Use `GeoShapes`, Blender heroes (see `moonbrick:assets`) or Parts.
2. **Medium:** fences, crates, lamps, rocks, in clusters of 3 to 5 at uneven spacing. `Scatter` for natural placement with a fixed seed.
3. **Small:** grass, pebbles, cables, signs. Cheap, and last. Set `CastShadow` off on it.

Keep rest areas: leave at least a third of each floor bare so the eye and the character can move. Clutter along the required path is a bug. Dressing beside a walkway has collision off unless it's meant to block.

## 7. Light the scene
The world's look lives in `art.json`, not in hand-edited Lighting: scene settings are recorded there and applied explicitly through `Scene`. Applying is a deliberate step you run and report, never a side effect, and a project file must not carry Workspace or Lighting properties. Use `Fx.ambience` for persistent dust, fog or fireflies per area, and `Camera` for fixed or follow rigs if the genre wants one. Terrain and hand-built parts stay in the place file; remind the user to save.

## 8. Phones
Most players are on phones and no phone has been measured in this repo, so treat these as working rules.
- Required paths 12+ wide: a thumbstick steers roughly.
- Sightlines: break long views with corners and hills, so the client draws less and streaming has cover.
- `StreamingEnabled` on for anything larger than an arena. Roblox's defaults are `StreamingMinRadius` 64 and `StreamingTargetRadius` 1024; low devices may hold little beyond the minimum, so gameplay can't assume a far part exists. Client code handles nil. Landmarks that must always show use `ModelStreamingMode = Persistent`.
- `K.perf()` after each dressing layer; if part count jumps, replace repeated parts with clones of one mesh.

## 9. Review (max 3 rounds)
1. Tour with `K.cam`/`K.tour`: one stop at player height (eye about 5 studs up) at every area entrance from the Map list, one overhead for the whole layout. Overhead shows flow and empty zones; player height shows what players see.
2. For each shot: can you see where to go next? Is the landmark or the goal the clearest thing? Does it match `art.json`?
3. Name the top 3 weaknesses, fix them, retake only those stops. Stop at round 3 or when nothing changes the read. For an opinion from something that didn't build it, give the `moonbrick:art-critic` agent the moment and the camera and look-at position of each stop; it captures its own views.

## 10. Walkthrough
In a playtest, drive the required route with Studio's `character_navigation` (Client datamodel), area by area in Map order, then sample position to confirm arrival. Passing: each stop reached, in about the time the Map promised (distance ÷ 16). A stuck character means a real blockage or a gap the navigation can't cross; note which. Check jump sections with the test jump instead. Report any section you couldn't drive.

## 11. Keep it
`K.toModelJson` refuses complex classes, so export what it accepts to `src/world/` and use native Rojo syncback or `.rbxm` for the rest. Verify the rebuilt copy before deleting anything.

Genre checklists (obby, simulator, tycoon, arena combat, horror, RPG hub, lobby): read the one you need in `${CLAUDE_SKILL_DIR}/references/genres.md`. Ready-made gameplay pieces: recipes `Spawn`, `Zones`, `Round`, `Obby` in `tools/recipes/`; Kit signatures in `tools/KIT_CREATIVE.md`.
