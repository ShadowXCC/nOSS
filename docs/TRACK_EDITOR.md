# Track editor and map import

An in-game editor, built with Godot's UI (not the Godot editor), for building, importing and sharing tracks. Requirements: EDT-01…EDT-10.

---

## 1. Track types

| Type | Used by | Notes |
|---|---|---|
| `circuit` | Track, Kart | Closed loop |
| `p2p` | Track, Highway runs, Kart | Point to point |
| `highway` | Highway | A carriageway each way either side of a median, with ramps to portals and flyovers between the carriageways (EDT-10, M7, D106). In M7 the main road is always a closed loop, so one map serves every sub-mode; open highways come with Endless (M9). |
| `arena` | Kart battle | Open area, no lap logic (M8, D138): the closed spline is the outline, a flat floor inside it and a wall round it (floor surface, wall kind and height in the Road tool). Spawns and item box clusters are automatic unless placed (the Stunts tool). No Race tool. |

Endless mode generates its roads procedurally and doesn't use editor tracks. It shares the same road and terrain mesh code.

## 2. Editor tools

**Track Editor** on the title screen. A panel of tools on the left, the track in a 3D view on the right, and Test drive, Undo, Redo, Save and Exit under the panel. Status lines are read out (polite live region). It builds circuits and (M7) highways: the "Highway loop (4 km)" template, or "Track type: Highway" in the Road tool.

| Tool | What it does |
|---|---|
| **Road** | Click to add control points (on the road: into it), drag to move, Alt+drag for height. Per point: widths left and right, banking (±45°; ±10° on a highway), an apron each side (width and slope), height (on the ground or set). Per segment (to the next point): surface, lanes, lines, curbs, barriers (sound walls too) and run-off each side. "Use these everywhere", Flip direction, Track type. On a highway the points are the median's line, and instead of widths: lanes each way (2–4), lane width, median width and barrier, shoulders, speed limit and the outer barriers (the widths follow). On a fitted scene: the centreline only (§7.1). |
| **Ramps** | Highways only (D122). Add at the cursor, on the carriageway it's on: an exit and an entry (an interchange), an exit, an entry, or a crossover (a flyover to the other carriageway). Click a ramp to pick it; drag its points (Alt+drag: height) or set them by field; insert and delete points; move it along the road; name, lanes (1–2), speed limit, whether traffic uses it, its portal's name; delete it (and its portal). A drag rebuilds only that ramp. |
| **Surfaces** | Fitted scenes only (§7.1): what each material is to a car, rules by name, style, Measure widths. |
| **Terrain** | Raise, lower, smooth, flatten (with "Pick height") and noise brushes; size, strength, falloff. "Fit terrain to track". |
| **Paint** | Eight layers: grass, dirt, sand, gravel, rock, snow, concrete, asphalt. Wheels drive on what's painted. |
| **Props** | Place (by kind: nature, buildings, trackside, ground), move, turn, scale, size; scatter and erase with a brush (kept off the road, spaced, random turns and sizes). |
| **Stunts** | Kart pieces (M8, D136–D138), on road circuits and arenas: Add at cursor (boost pad, item boxes, jump, wall-ride, loop; in an arena boost pads and jumps anywhere), the list of pieces, pick one and drag it along the road (pads also sideways; in an arena anywhere) or step it 10 m, its fields by kind, Delete; item boxes Automatic (rows every third of a lap unless you place rows), Placed or None. In an arena: Add spawn at cursor (facing the middle), Add item boxes at cursor (a cluster of four), delete the last of each. A drag rebuilds only that piece. |
| **Race** | Start line, sectors, checkpoints, grid, rolling start, gantry, AI caution, and the AI line: drag it sideways to pin it (§4). On a highway: the lap line, runs (click where one starts, then where it ends), speed traps, zones (speed limit, tunnel, which way) and the traffic (cars, share taking exits); no grid or AI line. |
| **Check** | What the checks found (§6), errors first; each one shows where it is. |
| **File** | Name, author, license; Save, Save as a copy, New track (from a template), Open track, Import scene, Downloaded tracks, Export…, Show track files. |

Templates: Empty, Oval (1.2 km), Circuit (2.5 km), Figure 8 with a bridge, each on terrain sized round it with its start, grid and sectors set; Highway loop (4 km): flat concrete, 3 lanes each way, an exit and an entry each way and a flyover each way; Kart circuit (1.2 km, flat: a boost pad, a row of boxes and a jump on the start straight, a wall-ride round the outside of the first corner, the loop on the back straight); Arena (100 m, two jumps). A highway's test drive is Cruise with its traffic; any track's test drive with a kart class (the last one picked) is a kart free drive, an arena's a battle.

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

- Catmull-Rom control points. Widths and aprons blend across a segment (smoothstep); banking follows a smooth curve through the points (level where it levels off, as a smoothstep, and steady through a steady change, so a long banked transition doesn't twist in steps, D206); the other settings hold for the segment that starts at the point.
- **Road mesh:** extruded along the spline with banked frames: the left vector is horizontal, rolled by the banking (D93). UVs are in metres, so retro textures tile cleanly. Lines: edges, lanes, both or none.
- **Curbs:** automatic on the inside and outside of corners above a curvature threshold, or on or off per side.
- **Barriers per side:** auto, none, tyres, armco, concrete, fence, sound wall, or a SAFER wall (an oval's: 1.2 m of white wall with a 3.8 m chain-link catch fence and posts on top), at the run-off edge. Every wall (and a bridge's parapets) is one smooth strip, so a car can slide along it; where a wall ends it narrows to a point over 1.5 m (D218).
- **Apron per side (D202):** paved road past the edge (and its curb), 0–30 m across, at its own slope (±30°; + raises the left, as banking does). It drives and collides as the road's own surface and counts as track. Run-off and the barrier move out past it, and the ground's bed takes the apron's slope from the road's edge out, where without one it carries the banking on. An oval's flat inside is an apron next to banked road.
- **Run-off per side:** grass, gravel, asphalt, concrete, sand or dirt, with a width.
- **Height:** a point either follows the ground (smoothed, at most 15% grade) or has its own height. Where the road is 3 m or more above the ground it gets a deck, parapets and pillars (a bridge). Near another part of the road, height decides which one a car is on, so crossings and bridges work (D94).

### Terrain

Our own, not the Terrain3D addon (D91, closes Q4).

- Heightmap grid at 1 m, in 256 × 256 m chunks, up to 16 × 16 chunks (4 × 4 km). Two layers: what was sculpted, and that with the road's bed cut in (worked out again on load, never saved).
- **Road bed:** the ground is flattened 5 cm under the road out to its edge, curbs, apron and run-off, with a 12 m falloff. Banked road counts as lifted (a bridge) only when its lower edge is 3 m or more above the ground, so an oval standing on its inner edge isn't one.
- **Rendering:** a shared grid mesh per level of detail (1, 2, 4 and 8 m), displaced in the shader from a 16-bit height texture per chunk; eight paint layers blended in the shader.
- **Collision:** a `HeightMapShape3D` per chunk. What a wheel drives on comes from the paint under it (a native surface map).

### Props

- Original low-poly pieces in the retro style, made in code (D100): pine, tree, flat tree, bush, rock; grandstand and pit building (with a length), tent, marshal post; billboard, light pole, light tower (30 m, its lamps lit after dark), crowd, cone, tyre stack; skidpad (drivable concrete). For a graveyard (D221): dead tree and gravestone (nature); jack-o'-lantern (its face glows after dark), iron fence (with a length) and old lamp (its glass glows after dark and flickers, steady with Reduce flashing) (trackside).
- Placed items are baked into the world; scattered ones are `MultiMeshInstance3D`s per 256 m chunk, seen to 1500 m, with simple collision where the type has it.

## 3. Stunt pieces (Kart, M8)

Pieces snap to the road at a distance along the spline (`at_m`, and `lateral_m` for pads); in an arena they stand where they're put (`p`, `yaw_deg`). Each is a static body with its surface and a tag (`noss_tag`: 1 boost, 2 jump, 4 stick) the kart layer reads (D133, D137):

| Piece | Behavior |
|---|---|
| Boost pad | A 2 cm slab with scrolling chevrons (no flashing): 0.8 s of boost on contact |
| Item box row | 3–5 item boxes across the road, 1 m up (no collision). They come back 3 s after a kart takes one. Without placed rows, rows go every third of a lap at the flattest place near. |
| Jump ramp | Height, length and width (0: the road's) set by parameters, its foot meeting the road. Drift just after take-off for a trick; an upright landing boosts. Needs 30 m of road after it (a warning). |
| Wall-ride | A quarter-pipe from the road's edge to vertical, with a lip along the top; its height and curve narrow at each end, back to the road. It stands where the barrier was, on the side you pick (round the outside of a corner). Karts stick to it above 7 m/s. At least 30 m long. |
| Loop | A circle of radius 7–14 m: in from the left half of the road, out on the right. Needs a road twice its width and a straight of 2 × radius + 40 m; a boost pad 25 m before it comes with it. Karts stick to it above 7 m/s (stick gravity, which replaced the planned `Area3D` override); the AI takes it from its lanes. |

The checks add: piece off the road, pieces overlapping, a loop round a corner or on a narrow road, a short wall-ride, a wall-ride over a bridge or ramp, an item row on a tight corner, over 64 boxes, a road under 8 m for karts (a warning); for arenas, an outline crossing itself, under 2500 m², fewer than 8 spawns clear of props, spawns, boxes or pieces outside.

## 4. Race setup

- **Start line and direction:** at the cursor, by distance, or reversed.
- **Grid:** slots (2–40), first row's distance back, row spacing, stagger, pole side. Two columns, each half way to the nearer edge.
- **Sectors:** even splits (1–6), or each line by distance.
- **Checkpoints:** invisible, every 100 m by default (25–500). They make laps count and catch wrong-way driving.
- **Rolling start** distance, the start **gantry**, and how far the AI drives carefully on lap 1 (auto, or set).
- **AI racing line:**
  - Solved automatically by **minimum curvature** inside the road (wide entry, apex, wide exit).
  - Speeds from the class's grip, power, braking and downforce, and the track's banking, grade and crests: banking into a turn lets it go faster, a crest takes load off the tires (the AI lifts so it keeps 75% of the car's weight on them), climbs slow the car (D93). The grade and crests are the line's own (on banking it runs above or below the centreline); banking presses the car into the road, and loaded tires grip a little less (D206); a corner's speed is where that grip stops covering the turn, found by halving (D223).
  - A wall within 2 m of the edge (an oval's) keeps the line 0.6 m further in.
  - **Pins:** drag the line sideways to pin it there; it bends through the pin and stays inside the road. Pins don't change the layout (records stay, D97).
  - "AI lap" shows the reference car's lap on the line (Track GT).
- **Sky** (M9, D153): the track's own time of day (a fixed sun, or Dawn … Night) and weather (Clear … Snow, or Changing), stored in its `environment` block. Events that keep "Track's" get them; an event can pick another.
  - **Setting** (D221): None, or an endless biome whose sky and sounds the track has throughout (`environment.biome`). Haunted is a misty night whatever the event's time and weather (its mist on top of the track's own fog), with its own storm and fog fronts when the weather is Changing, wind, crickets and distant thunder: for a graveyard circuit.
- **Pit lane** (D203): "Add pit lane" (along the start straight, on the right), or click "Pit entry" and "Pit exit" on the road. It leaves the road at the entry and has joined it again by the exit, attached to the paved edge for its taper at each end (as a highway's ramps are), and is laid along the road between, 3 m past the edge. Side, width, speed limit, boxes and the pit wall (on the lane's road side, where it's clear of the road) are fields. The road's barrier and run-off open at its mouths. Limit lines stand 40 m in from each end; the boxes (painted outlines, nearest the exit first) sit between them on the lane's far half. A car in the lane is on track and out of track limits and the flags; its laps count along the road. The checks: it builds, it's 150 m or more, it keeps off the road, its boxes fit, and no grid slot is in a mouth.

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
                  // bank_deg ±45 (D223); optional (D202): "apron_l_m", "apron_r_m" (0-30), "apron_l_deg", "apron_r_deg" (±30); barrier "safer"
    "points": [ { "p":[x,y,z] }, { "p":[…], "width_l":7.5, "bank_deg":5, "height":"set", "barrier_l":"armco" } ] },
  "race": { "start_m":150, "sectors_m":[880,1690], "checkpoint_spacing_m":100,
            "grid":{ "slots":20, "front_m":12, "row_m":13, "stagger":0.5, "pole":"left" },
            "rolling_back_m":220, "gantry":true, "ai":{ "caution_until_m":-1, "pins":[{"at_m":812,"offset_m":-2.5}] } },
  "ground": { "terrain":"terrain/meta.json" },   // or { "flat_y":-0.03, "surface":"grass" }
  "props": { "items":[{ "prop":"grandstand","p":[…],"yaw_deg":90,"scale":1,"size":[13,9.9,110],"ground":true }],
             "scatter":[{ "prop":"tree_pine","xf":[x,z,yaw,scale, …] }] },
  "environment": { "time":"dusk", "weather":"rain" },   // optional: also sun_elevation_deg, sun_azimuth_deg, fog, floodlit (D205), biome (D221)
  "scene": null }   // a fitted scene: { "glb":"scene/scene.glb", "tags":"scene/tags.json" }
```

- A highway (`"type":"highway"`, D106) adds a `highway` section; its road's defaults come from it (widths, no curbs, concrete run-off and barriers):

```jsonc
"highway": { "drive":"right", "lanes":3, "lane_m":3.6, "median_m":2.4, "shoulder_in_m":0.8, "shoulder_out_m":3.0,
  "median_barrier":"concrete", "speed_kmh":110,
  "zones":  [{ "dir":0, "from_m":2580, "to_m":3240, "speed_kmh":80, "tunnel":true, "name":"Cathedral Tunnel" }],
  "ramps":  [{ "id":"interchange_1_off", "name":"Harbour Gate", "kind":"exit",          // exit, entry or link
               "from":{ "dir":1, "at_m":1010 }, "to":{ "portal":"interchange_1_out" },  // or { "dir":-1, "at_m":… }
               "lanes":1, "lane_m":3.6, "taper_m":200, "speed_kmh":70, "traffic":true,
               "points":[{ "p":[x,y,z], "height":"set" }] }],                           // the points between its ends
  "portals":[{ "id":"interchange_1_out", "name":"Harbour Gate", "p":[x,y,z], "yaw_deg":90 }],  // one per ramp
  "runs":   [{ "id":"harbour_sprint", "name":"Harbour sprint", "dir":1, "from_m":7280, "to_m":1000 }],
  "traps":  [{ "dir":-1, "at_m":2072 }],
  "traffic":{ "count":150, "exit_share":0.15, "seed":7 } }
```

  Direction 1 drives along the road's line on its right side, −1 the other way on its left; lanes count from the outside; `race.start_m` is the lap line. Flip direction swaps the directions and mirrors the distances; the ramps stay where they are.
- A track can suggest Track-mode rules (D207) in a `rules` section, used by events that keep "Track's"; it isn't part of the layout. The Race tool's "Suggested rules" sets it:

```jsonc
"rules": { "start":"rolling", "draft":true, "fuel_x":5, "tyre_x":5, "pack":true }
```

- A pit lane (D203) goes in a `pit` section on circuits:

```jsonc
"pit": { "side":"right", "from_m":2990.4, "to_m":3978.0,   // where it leaves the road, where it has joined it
  "taper_m":90, "points":[{ "p":[x,y,z] }],                  // its own points between the tapers (height: ground or set)
  "width_m":8, "speed_kmh":80, "limit_m":40, "boxes":20, "box_m":10, "wall":true }
```

  Flip direction swaps its ends and side.
- Scenery roads (D212) go in a `roads` list: open roads round the course that aren't part of it, the rest of a venue (an oval's infield road course, a road course's unused banking). Each is made as the road is, from its own points and defaults (widths, banking, apron, curbs, run-off, barriers); where it runs onto the road, its pit lane or a scenery road before it, its edge stops at theirs (the cross-section tilted to meet it), and where it's wholly on them it's cut, so a road may cross another. They're built and shaped into the ground as the road is; cars can drive them, but nothing is timed there (a car on one is off the track). The editor shows them, fitted again as the road moves; there's no tool to draw them yet (`TrackDraft.add_road`, `remove_road`). A prop on one is a warning.

```jsonc
"roads": [{ "name":"Oval turn 1",
  "defaults":{ "width_l":9, "width_r":9, "height":"set", "apron_l_m":9, "barrier_r":"safer" },
  "points":[{ "p":[x,y,z], "bank_deg":-24 }, …] }]                // two or more
```

- Water (D224) goes in a `water` list: lakes off the road, each a flat surface at height `y` over its outline on the map (`[x, z]` corners in order, not crossing themselves; 16 at most). Under each surface is a catch volume 6 m deep: a car that goes in is sent back to the road ("In the water"), as from a fitted scene's water. It counts in the layout hash. The ground under a lake is the track's own (a generator lowers it); the editor shows the water and keeps it, with no tool to draw it yet. Water on the road or its pit lane is an error; a prop in it is a warning.

```jsonc
"water": [{ "name":"Lake Lloyd", "y":1.5, "points":[[x,z], [x,z], [x,z], …] }]   // three corners or more
```

- Kart pieces (D136) go in a `kart` section on circuits and arenas; an arena (`"type":"arena"`, D138) adds an `arena` section:

```jsonc
"kart": { "boxes":"auto",                       // "auto": rows every third of a lap unless rows are placed; "placed"; "none"
  "stunts":[
    { "id":"boost_pad_1", "kind":"boost_pad", "at_m":420.0, "lateral_m":0.0, "length_m":5.0, "width_m":3.0 },
    { "id":"item_row_1",  "kind":"item_row",  "at_m":640.0, "count":4 },           // 0: as many as the road takes
    { "id":"jump_1",      "kind":"jump",      "at_m":910.0, "height_m":1.4, "length_m":9.0, "width_m":0.0 },
    { "id":"wall_ride_1", "kind":"wall_ride", "at_m":1210.0, "length_m":120.0, "side":"left", "height_m":6.0 },
    { "id":"loop_1",      "kind":"loop",      "at_m":1500.0, "radius_m":9.0, "width_m":5.0 } ] },
// In an arena, pieces stand anywhere: { "kind":"jump", "p":[x,y,z], "yaw_deg":90, … }
"arena": { "floor":"asphalt", "wall":"tyres", "wall_m":1.2,
           "spawns":[{ "p":[x,0,z], "yaw_deg":45 }],    // none: 12 round the middle, facing it
           "boxes":[{ "p":[x,0,z], "count":4 }] }        // none: the middle and four half way out
```

  At most 64 boxes. Flip direction mirrors the pieces' distances and swaps wall-rides' sides.
- **Content hash** = SHA-256 of `manifest.json`, the same scheme as cars ([VEHICLE_PACKAGE.md §2](VEHICLE_PACKAGE.md#2-manifestjson)).
- **Layout hash** = SHA-256 of the road and race setup (AI pins left out), a highway's section (its traffic settings left out), and the `kart`, `arena`, `pit` and `roads` sections when a track has them (so tracks without them keep their hashes). Records for a track you made are kept under its id and layout, so changing the layout starts them afresh; built-in tracks keep theirs under the id (D97).
- **Limits:** 100 MB zipped, 250 MB unpacked, 512 files; scenes up to 2 M triangles, 20 000 nodes and 4096² textures. Servers can lower them.
- **Safety:** the same rules as car packages ([VEHICLE_PACKAGE.md §9](VEHICLE_PACKAGE.md#9-limits-and-safety)): every file is checked against the manifest's hash before any is used, sizes before anything is decompressed or decoded. Never Godot resource files or scripts.
- **Where:** your tracks are `user://tracks/*.nosstrack` (File → Show track files); built-in tracks are folders in `content/tracks/`. A built-in track's PNGs use Godot's **Keep File** import (`importer="keep"` in their `.import`, written by `TrackWriter`), so builds carry the PNG itself. As textures they'd be left out, and the track wouldn't load ("Missing file", D200).
- **Export…** writes the track as it stands to a file anywhere on disk, leaving the library copy alone; a saved track's version carries over, so an export says which one it is.
- **Downloaded tracks** lists the tracks that arrived from a host and sit in the content cache ([NETWORKING.md §7](NETWORKING.md)), each with Save to my tracks and Export…: the cache is cleared from time to time, so this is how a track from an online session is kept.
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
| A slot on a road too narrow or banked over 20° (D223) | Grid off the road | error |
| The grid takes more than 40% of the lap | Grid too long | error |
| Sector lines out of order or under 100 m apart | Sector 2 out of order | error |
| A prop (that cars hit) on the road / blocking it | Prop on the road / Road blocked at 300 m | warning / error |
| Water over the road or its pit lane (D224) | Water on the road / Water on the pit lane | error |
| A prop standing in water | Prop in the water | warning |
| The road within 50 m of the terrain's edge | Road leaves the terrain at 2.4 km | error |
| The AI line out of the road, kinked, or slower than a walk | AI line error at 2.1 km | error |
| A fitted scene: nothing drivable tagged; the road under the line untagged; no ground under the grid or a checkpoint | No surfaces tagged / Road surface not tagged / Grid off the road / Checkpoint blocked | error |
| "Personal use only" license | Personal-use tracks stay offline | note |
| A highway: a ramp that doesn't build (too short, no portal) | exit_1: Ramp too short | error |
| A highway ramp tighter than it is wide; on the road it doesn't join without 4.5 m between them | Ramp too tight: Exit 1 / Ramp overlaps road: Exit 1 | error |
| Two highway ramps leaving or joining at the same place, or on each other | Ramps too close: A, B / Ramps overlap: A, B | error |
| A highway ramp steeper than 8% | Ramp too steep: Exit 1 | warning |
| Exits off a carriageway but no entry back onto it | Exit with no entry back | warning |
| No crossover, or one way only | No crossover / Crossover one way only | warning |
| A run under 500 m | Run too short: Dash | error |
| Traffic can't use the road (its lane graph won't build) | Traffic can't drive it: … | error |

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
- **First real-world track:** the **Eifel GP** (D200) was made ahead of this importer by two one-off tools:
  - `tools/fetch_eifel_gp.py` fetches OSM relation 38567 and EU-DEM heights once, into `tools/data/eifel_gp.json`.
  - `tools/make_eifel_gp.gd` turns that into an editable track.
  - Its steps can seed EDT-09: join the circuit's ways into a loop, project, smooth out the mapping jitter, place points closer in corners, and lower the DEM under terrain's 555 m ceiling.
- **Second:** **Piedmont Speedway** (D206), the Charlotte Motor Speedway quad-oval, by `tools/fetch_piedmont.py` (its five oval ways, its pit road and every raceway round it with node ids, from Overpass; USGS NED heights from OpenTopoData) and `tools/make_piedmont_speedway.gd`. The helpers both generators share are in `tools/track_gen_util.gd`. New steps: move a map line that runs along the inside out to where the track measures its length, bank from the line's curvature, level the venue at the infield's grade with a berm outside the wall, and lay a pit road from the map's.
- **Third:** **Piedmont Road Course** (D211), the infield "Roval" at the same venue, by `tools/make_piedmont_road_course.gd` from the same data. New steps: copy another track's control points for the shared sections (banking and all), route the infield through the map's road graph between two nodes (shortest way, one-way ways driven their way), swap in a chicane's own way where it has one, and narrow stretches that run side by side with a wall between.
