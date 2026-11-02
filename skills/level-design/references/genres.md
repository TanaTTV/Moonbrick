# Genre checklists

Read only your genre. Numbers assume default movement; rescale them if the game changes speed or jump. They are design starting points, so adjust after a test jump and a real play.

## Obby
- First three stages can't be failed by a new phone player: pads 8x8, gaps 3 to 4, no moving parts.
- Checkpoint every 3 to 5 jumps at first, then every 5 to 8. Respawn in under 3 seconds. The `Obby` recipe has stages, hazards, a timer and a sample course.
- Teach one idea per stage: moving pad, then kill brick, then both.
- Keep the next platform in frame from the current one; a blind jump is a cheap death.
- Kill bricks read at a glance: one hazard colour, used nowhere else, with a pulse or glow.
- Give a visible height or distance goal, plus a stage counter.
- Skip option for stuck players; decide this before balancing.

## Simulator
- Spawn within 30 studs of the first collectable; first sell or upgrade inside 30 seconds.
- Hub in the centre, zones as spokes, each gated by a visible number on a visible gate.
- A new zone is seen before it's affordable: players look through the gate at what they're saving for.
- Sell and upgrade stations sit on the return path, not off to the side.
- Wide paths (20+): crowds, pets and large characters share them.
- Leave room for the player's growth if scale or pets are part of the fantasy.

## Tycoon
- Plots spaced apart so one player's build never blocks another's view or path.
- Buttons in one readable order along a path, cheapest nearest the dropper.
- First purchase affordable within 15 seconds; show the next two buttons, not all of them.
- Each purchase changes the skyline of the plot, so progress reads from a distance.
- Reserve the full footprint in blockout. Late floors and defences need their space from day one.
- Plan what happens to a plot when its owner leaves.

## Arena combat
- Three-lane logic: two flanks and one centre, with loops. No dead ends; a corner with one exit is a coffin.
- Cover at character-chest height (3 to 4) to shoot over, full height (6+) to break line of sight, spaced 15 to 25 apart.
- Spawn with cover and out of direct sight of the centre, and 60+ studs from any other spawn.
- One power position or pickup worth contesting, exposed on two sides.
- Every height advantage needs a counter route.
- Time to cross: 8 to 12 seconds between spawns. Longer than that and matches go quiet.
- Round maps need a reset state; the `Round` recipe moves players between `LobbySpawn` and `ArenaSpawn` parts.

## Horror
- Light is the mechanic: the player's way forward is the dim one, and safety is lit.
- Tight corridors (8 to 10 wide), low ceilings, frequent corners. Keep sightlines under 40 studs.
- Long quiet stretches before each scare; three calm rooms for each event. Sound does most of the work.
- A loop in every chase area, or the chase ends in an unfair corner.
- Hide-spots visible before the threat appears, so players can plan.
- Set the mood with `Scene` and `Fx.ambience`, then check brightness on a phone in a bright room: dark games turn solid black on phone screens.

## RPG hub
- One readable central plaza with exits as distinct as possible: each direction has its own colour, shape and landmark.
- Quest-givers on the walking line, facing the entrance.
- Shops by function, signed by silhouette (anvil, potion bottle), not text.
- Vertical space adds character cheaply: stairs, balconies, overlooks.
- Fast travel from the second visit on.
- Other players are the decoration: leave sit spots, stages and places to show off gear.

## Lobby
- Players reach the action in under 20 seconds: a clear portal or queue directly ahead of spawn.
- One view shows everything: portal, shop, leaderboard. No wandering required.
- Stagger spawn points in a wide area, so crowds don't stack.
- Keep it small: 80 to 120 studs across.
- Show the game's best visual in the lobby. It's the first screenshot and the first impression.
- Low part count; everyone loads this first, including the slowest phone.
