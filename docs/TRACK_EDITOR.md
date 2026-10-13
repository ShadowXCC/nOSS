# Track editor and map import

An in-game editor, built with Godot's UI (not the Godot editor), for building, importing and sharing tracks. Requirements: EDT-01…EDT-10.

---

## 1. Track types

| Type | Used by | Notes |
|---|---|---|
| `circuit` | Track, Kart | Closed loop |
| `p2p` | Track, Highway runs, Kart | Point to point |
| `highway` | Highway | Multi-lane network with ramps (EDT-10, M7). The main road can close into a two-way loop for the Loop sub-mode. |
| `arena` | Kart battle | Open area, no lap logic |

Endless mode generates its roads procedurally and doesn't use editor tracks. It shares the same road and terrain mesh code.

## 2. Editor tools

**Track Editor** on the title screen. A panel of tools on the left, the track in a 3D view on the right, and Test drive, Undo, Redo, Save and Exit under the panel. Status lines are read out (polite live region). In M6 the editor builds circuits; the other track types come with their milestones.

| Tool | What it does |
|---|---|
| **Road** | Click to add control points (on the road: into it), drag to move, Alt+drag for height. Per point: widths left and right, banking, height (on the ground or set). Per segment (to the next point): surface, lanes, lines, curbs, barriers and run-off each side. "Use these everywhere", Flip direction. On a fitted scene: the centreline only (§7.1). |
| **Surfaces** | Fitted scenes only (§7.1): what each material is to a car, rules by name, style, Measure widths. |
| **Terrain** | Raise, lower, smooth, flatten (with "Pick height") and noise brushes; size, strength, falloff. "Fit terrain to track". |
| **Paint** | Eight layers: grass, dirt, sand, gravel, rock, snow, concrete, asphalt. Wheels drive on what's painted. |
| **Props** | Place (by kind: nature, buildings, trackside, ground), move, turn, scale, size; scatter and erase with a brush (kept off the road, spaced, random turns and sizes). |
| **Race** | Start line, sectors, checkpoints, grid, rolling start, gantry, AI caution, and the AI line: drag it sideways to pin it (§4). |
| **Check** | What the checks found (§6), errors first; each one shows where it is. |
| **File** | Name, author, license; Save, Save as a copy, New track (from a template), Open track, Import scene, Show track files. |

Templates: Empty, Oval (1.2 km), Circuit (2.5 km), Figure 8 with a bridge. Each comes on terrain sized round it, with its start, grid and sectors set.

**Controls** (D95). Every view action is also a panel button, and every value has a field:

| | Mouse | Keys | Controller |
|---|---|---|---|
| Pick, drag | Left button | Enter or Space grabs, again drops (crosshair) | A grabs, again drops |
| Move the view | Middle drag | WASD or arrows | Left stick |
| Turn | Right drag | Q / E | Right stick |
| Zoom | Wheel | Z / X | Triggers |
| Previous / next point, pin or prop | | `[` / `]` | LB / RB |
| Delete | | Delete or Backspace | X |
| Undo / redo | | Ctrl+Z / Ctrl+Y (Ctrl+Shift+Z) | D-pad left / right |
| Map view (from above) | | M | Y |
| Test drive (from the cursor; Shift: the grid) | | F5 | Start |
| To the panel and back | | F6 or Esc | B |
| Tools | | 1–8 | |

The keyboard and controller work round a crosshair in the middle of the view. Editor shortcuts can't be rebound yet (D103).

### Road splines

- Catmull-Rom control points. Widths and banking blend across a segment (smoothstep); the other settings hold for the segment that starts at the point.
- **Road mesh:** extruded along the spline with banked frames: the left vector is horizontal, rolled by the banking (D93). UVs are in metres, so retro textures tile cleanly. Lines: edges, lanes, both or none.
- **Curbs:** automatic on the inside and outside of corners above a curvature threshold, or on or off per side.
- **Barriers per side:** auto, none, tyres, armco, concrete, fence, at the run-off edge.
- **Run-off per side:** grass, gravel, asphalt, concrete, sand or dirt, with a width.
- **Height:** a point either follows the ground (smoothed, at most 15% grade) or has its own height. Where the road is 3 m or more above the ground it gets a deck, parapets and pillars (a bridge). Near another part of the road, height decides which one a car is on, so crossings and bridges work (D94).

### Terrain

Our own, not the Terrain3D addon (D91, closes Q4).

- Heightmap grid at 1 m, in 256 × 256 m chunks, up to 16 × 16 chunks (4 × 4 km). Two layers: what was sculpted, and that with the road's bed cut in (worked out again on load, never saved).
- **Road bed:** the ground is flattened 5 cm under the road out to its edge, curbs and run-off, with a 12 m falloff.
- **Rendering:** a shared grid mesh per level of detail (1, 2, 4 and 8 m), displaced in the shader from a 16-bit height texture per chunk; eight paint layers blended in the shader.
- **Collision:** a `HeightMapShape3D` per chunk. What a wheel drives on comes from the paint under it (a native surface map).

### Props

- Original low-poly pieces in the retro style, made in code (D100): pine, tree, flat tree, bush, rock; grandstand and pit building (with a length), tent, marshal post; billboard, light pole, crowd, cone, tyre stack; skidpad (drivable concrete).
- Placed items are baked into the world; scattered ones are `MultiMeshInstance3D`s per 256 m chunk, seen to 1500 m, with simple collision where the type has it.

## 3. Stunt pieces (Kart, M8)

Pieces snap to the road at a distance along the spline:

| Piece | Behavior |
|---|---|
| Boost pad | A short boost on contact |
| Item box row | 3–5 item boxes across the road. They respawn after 3 s. |
| Jump ramp | Height and length set by parameters. Trick input in the air gives a landing boost. |
| Wall-ride | A 90° banked wall segment |
| Loop *(stretch)* | Uses an `Area3D` gravity override to keep cars on the surface |

## 4. Race setup

- **Start line and direction:** at the cursor, by distance, or reversed.
- **Grid:** slots (2–40), first row's distance back, row spacing, stagger, pole side. Two columns, each half way to the nearer edge.
- **Sectors:** even splits (1–6), or each line by distance.
- **Checkpoints:** invisible, every 100 m by default (25–500). They make laps count and catch wrong-way driving.
- **Rolling start** distance, the start **gantry**, and how far the AI drives carefully on lap 1 (auto, or set).
- **AI racing line:**
  - Solved automatically by **minimum curvature** inside the road (wide entry, apex, wide exit).
  - Speeds from the class's grip, power, braking and downforce, and the track's banking, grade and crests: banking into a turn lets it go faster, a crest takes load off the tires (the AI lifts so it keeps 75% of the car's weight on them), climbs slow the car (D93).
  - **Pins:** drag the line sideways to pin it there; it bends through the pin and stays inside the road. Pins don't change the layout (records stay, D97).
  - "AI lap" shows the reference car's lap on the line (Track GT).
- **Pit lane:** later (M10).

## 5. File format: `.nosstrack`

A zip archive (or an unpacked folder: built-in tracks, downloads). Road, curb and barrier meshes are **rebuilt on load** from `track.json`, which keeps files small and deterministic (D92).

```
my_track.nosstrack
├─ manifest.json    noss.track_package/1: id, version, name, author, license, type, kind (road|scene),
│                   length_m, layout (hash), attributions[], source, created, game_min_version,
│                   files {path: sha256}
├─ track.json       noss.track/1: road (defaults and control points), race setup, ground,
│                   props (items and scatter), environment, scene
├─ terrain/
│  ├─ meta.json     noss.terrain/1: origin, chunks, cell and chunk size, height range and step, layers
│  ├─ height.png    16-bit grey, (chunks × 256 + 1) samples a side
│  └─ splat_0.png, splat_1.png    eight paint layers' weights (RGBA, summing to 255)
├─ scene/           tracks made from a 3D scene only (§7.1)
│  ├─ scene.glb
│  └─ tags.json     noss.scene_tags/1
├─ thumb.png
└─ minimap.png      drawn from the road
```

- Schemas: `data/schemas/track_package`, `track`, `terrain` and `scene_tags`. Older `noss.track/0` files (a bare `track.json`, like the first Proving Ground) are upgraded as they load.
- `track.json` in short (each point stores only what differs from `road.defaults`; distances are metres from point 0 in driving order, so flipping the direction moves them):

```jsonc
{ "schema":"noss.track/1", "id":"…", "name":"Lakeside Loop", "type":"circuit", "style":"retro_ps2",
  "road": { "mode":"road",   // or "centreline": a fitted scene is the road (§7.1)
    "defaults": { "width_l":6, "width_r":6, "bank_deg":0, "height":"ground", "lanes":1, "lines":"edges",
                  "surface":"asphalt", "curb_l":"auto", "curb_r":"auto", "runoff_l":"grass", "runoff_r":"grass",
                  "runoff_l_m":16, "runoff_r_m":16, "barrier_l":"auto", "barrier_r":"auto" },
    "points": [ { "p":[x,y,z] }, { "p":[…], "width_l":7.5, "bank_deg":5, "height":"set", "barrier_l":"armco" } ] },
  "race": { "start_m":150, "sectors_m":[880,1690], "checkpoint_spacing_m":100,
            "grid":{ "slots":20, "front_m":12, "row_m":13, "stagger":0.5, "pole":"left" },
            "rolling_back_m":220, "gantry":true, "ai":{ "caution_until_m":-1, "pins":[{"at_m":812,"offset_m":-2.5}] } },
  "ground": { "terrain":"terrain/meta.json" },   // or { "flat_y":-0.03, "surface":"grass" }
  "props": { "items":[{ "prop":"grandstand","p":[…],"yaw_deg":90,"scale":1,"size":[13,9.9,110],"ground":true }],
             "scatter":[{ "prop":"tree_pine","xf":[x,z,yaw,scale, …] }] },
  "environment": {}, "scene": null }   // a fitted scene: { "glb":"scene/scene.glb", "tags":"scene/tags.json" }
```

- **Content hash** = SHA-256 of `manifest.json`, the same scheme as cars ([VEHICLE_PACKAGE.md §2](VEHICLE_PACKAGE.md#2-manifestjson)).
- **Layout hash** = SHA-256 of the road and race setup (AI pins left out). Records for a track you made are kept under its id and layout, so changing the layout starts them afresh; built-in tracks keep theirs under the id (D97).
- **Limits:** 100 MB zipped, 250 MB unpacked, 512 files; scenes up to 2 M triangles, 20 000 nodes and 4096² textures. Servers can lower them.
- **Safety:** the same rules as car packages ([VEHICLE_PACKAGE.md §9](VEHICLE_PACKAGE.md#9-limits-and-safety)): every file is checked against the manifest's hash before any is used, sizes before anything is decompressed or decoded. Never Godot resource files or scripts.
- **Where:** your tracks are `user://tracks/*.nosstrack` (File → Show track files); built-in tracks are folders in `content/tracks/`.
- **Sharing:** tracks go to players who don't have them when they join online (EDT-07, D98, [NETWORKING.md §7](NETWORKING.md)). Tracks marked "Personal use only" never go online.

## 6. Test-drive and editing comforts

- **Test drive:** F5 (Start on a controller, or the Test drive button) drops you in at the cursor in your last car and class: on the road, along it; elsewhere, facing the way the camera looks; with the cursor off any ground (or Shift+F5), on the grid. **Back to editor** is first in the pause menu, or one key while driving (D102): F5 on the whole keyboard and its left side, F8 on the right side, D-pad down on a controller. The editor comes back as you left it: view, tool, selection and history.
- **Undo/redo:** every change is one step ("Undone: Move point"), up to 1000, kept with the track through test drives (D96). A brush stroke or a drag is one step.
- **Autosave:** every 2 min while it changes, and before a test drive, to `user://tracks/.autosave/`. Opening the editor offers the last one back.
- **Checks** (D101), well under a second after a change, on a worker, with the AI line. Errors stop saving to your tracks, sharing and hosting (autosave still works); warnings and notes don't:

| Check | Message | Level |
|---|---|---|
| Fewer than 3 points, or under 200 m | Track too short | error |
| No start line | No start line | error |
| The road meets itself without 4.5 m between them | Road overlaps at 1.2 km | error |
| A corner tighter than the road is wide | Too tight at 640 m | error |
| A height step past what driving can take | Gap at 2.1 km | error |
| Steeper than 25% | Too steep at 900 m | warning |
| Fewer than 2 slots / fewer than 12 | Grid too small | error / warning |
| A slot on a road too narrow or banked over 6° | Grid off the road | error |
| The grid takes more than 40% of the lap | Grid too long | error |
| Sector lines out of order or under 100 m apart | Sector 2 out of order | error |
| A prop (that cars hit) on the road / blocking it | Prop on the road / Road blocked at 300 m | warning / error |
| The road within 50 m of the terrain's edge | Road leaves the terrain at 2.4 km | error |
| The AI line out of the road, kinked, or slower than a walk | AI line error at 2.1 km | error |
| A fitted scene: nothing drivable tagged; the road under the line untagged; no ground under the grid or a checkpoint | No surfaces tagged / Road surface not tagged / Grid off the road / Checkpoint blocked | error |
| "Personal use only" license | Personal-use tracks stay offline | note |

## 7. Map import

### 7.1 3D scene import, with Track Fitting (EDT-08, M6)

Use any modeled track or environment (GLB, glTF or FBX), the same way the Fitting Bay handles cars (D99).

1. **Import:** File → Import scene. The scene is checked and read on a worker thread (up to 3 minutes). FBX and glTF with separate files become one GLB.
2. **Tag surfaces** (Surfaces tool). What each surface (a material on a mesh) is to a car:
   - drivable: asphalt, concrete, curb, paint, grass, gravel, dirt, sand, snow, ice
   - `wall` (solid, not for driving), `no-collide` (only seen), `water` (sends the car back to the road: "In the water")
   - Untagged surfaces are solid and driven on as concrete.
   - A mesh's own tag wins, then its material's, then the first **rule** that matches the material's name and then the mesh's (`*road*` → asphalt; the defaults know common words), then "Everything else".
   - Materials are listed by name without the numbers exporters add (`grey`, `grey2` … are one row). Clicking the scene picks the material under the cursor.
3. **Centreline** (Road tool): click along the middle of the road. Points only go on surfaces tagged to drive on ("Not a road surface"), at the scene's height. The centreline drives checkpoints, track limits, resets and the AI line; nothing is built from it.
4. **Measure widths:** the road's width each side at each point, read off the scene (sideways in 25 cm steps while the ground stays the centre's tag and doesn't step more than 40 cm; the median over the segment). One undo step.
5. **Race setup:** start line, grid, direction, sectors (§4). The checks (§6) look for ground under the line, the grid and every checkpoint.
6. **Collision:** concave shapes per tag, cut into 256 m squares (at most 200 000 triangles each).
7. **Style:** the scene's own materials, or Retro (textures made small and sharp, on copies).
8. **Save:** a `.nosstrack` with `scene/scene.glb` and `scene/tags.json`.

Automatic tracing of the centreline from the tagged road is still a stretch goal. The test scene is a circuit made from the Kenney Racing Kit (CC0) by `tools/make_kenney_circuit.gd`.

### 7.2 Real-world import: OpenStreetMap + elevation (EDT-09, M10+)

Generates an **editable** nOSS track from real places.

- **Input:** pick a bounding box (≤ 5 × 5 km at first), or load local files:
  - `.osm` / `.osm.pbf` extract
  - elevation GeoTIFF (SRTM 30 m, Copernicus GLO-30, or similar)
- **Pipeline:**
  1. Project lat/lon to local metres (ENU).
  2. `highway=*` ways become road splines. Lanes and width come from tags, with defaults per road class. `bridge`, `tunnel` and `layer` set elevation.
  3. DEM becomes terrain, resampled to the editor grid. Roads conform to it.
  4. `building=*` footprints are extruded using height and levels tags. `landuse`, `natural=wood` and water become splat layers and prop scatter.
  5. The player picks the roads that form a circuit or route, or keeps the whole network (highway or free roam).
- **Online fetch is optional and off by default.** When used, it must follow the Overpass API's and elevation providers' usage policies, so local files are the preferred path.
- **Attribution travels with the track:** "© OpenStreetMap contributors (ODbL)" plus the DEM source are written to `manifest.attributions`. Tracks containing OSM-derived data keep the ODbL notice.
