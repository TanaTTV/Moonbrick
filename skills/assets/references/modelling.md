# Modelling for Roblox

Roblox art is read small, on a phone, from 20 to 100 studs. Judge everything at that distance first.

## Order of work
1. **Silhouette.** Primitive blocks only, flat grey, no detail. Could someone name it from the outline alone? A sword is its crossguard and taper; a tree is its crown mass against its trunk. If the outline is ambiguous, no texture saves it. Push one feature past realistic: stylised props read through exaggeration, such as a handle 30% too thick.
2. **Proportion.** Size masses big, medium, small, at roughly 3:1 steps. A prop made of six same-sized boxes has no hierarchy, whatever its polish.
3. **Three value zones.** Assign light, mid and dark to masses before choosing colour: about 60% one zone, 30% the second, 10% the third. The focal feature gets the strongest contrast. Two adjacent masses of equal value merge at distance.
4. **Material contrast.** Pair rough with smooth, matte with metal. One glossy or emissive accent per asset at most. All-matte or all-chrome looks like a placeholder.
5. **Bevels, last.** Roblox lighting needs an edge to catch. Bevel every hard edge the camera sees: width 1 to 2% of the longest dimension, 2 segments on heroes, 1 on props.

## Budgets
Roblox refuses a single mesh over 20,000 triangles. That's a wall, not a target: a phone draws the whole scene.

| Asset | Triangles | Materials | Texture |
|---|---|---|---|
| Scatter (grass tuft, pebble) | 20-150 | 1 | none or shared |
| Small prop (crate, lamp) | 150-500 | 1 | shared or 256 |
| Medium prop (cart, plinth) | 500-2,000 | 1-2 | 512 |
| Hero object (weapon, centrepiece) | 2,000-8,000 | 1-2 | 1024 |
| Building shell | 2,000-10,000, split into pieces | 2-3 | 1024 |

These are working budgets, not Roblox limits, and `art.json` overrides them. Spend triangles on the silhouette, not on flat faces. Split large things so streaming can load them in pieces.

## Topology, normals, UVs
- Quads while modelling, no n-gons on curved faces; the exporter triangulates. Roblox asks for watertight meshes with real thickness and no exposed backfaces. Faces render one side, so an open bowl needs an inner surface.
- Apply scale and rotation. Origin at the base centre for anything that sits on the ground, so placement tools drop it correctly. `get_scene_info` with `ground` should show it on the ground, not floating.
- Smooth shading with hard edges marked, or a Weighted Normal modifier over the bevels. Faceted shading on a curved form reads as a mistake unless it's the art style.
- One UV set, inside 0-1, even texel density, seams on hidden edges, 4 to 8 px of padding at 1024.
- Cheapest good texture: lay UV islands onto a small shared gradient palette built from `art.json` colours. Fifty props then share one image and stay on palette. Vertex colours also survive FBX and glTF import.
- Normal maps are tangent space, OpenGL orientation. A flipped green channel shows as dents that look inverted.

## In Studio afterwards
- `CollisionFidelity`: `Box` for small props, `Hull` for large ones, precise decomposition only for what players walk on or stand inside.
- Reuse one mesh with many instances rather than many near-identical meshes.
