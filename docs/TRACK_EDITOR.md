# Track editor and map import

An in-game editor, built with Godot's UI (not the Godot editor), for building, importing and sharing tracks. Requirements: EDT-01…EDT-10.

---

## 1. Track types

| Type | Used by | Notes |
|---|---|---|
| `circuit` | Track, Kart | Closed loop |
| `p2p` | Track, Highway runs, Kart | Point to point |
| `highway` | Highway | Multi-lane network with ramps (EDT-10, M7) |
| `arena` | Kart battle | Open area, no lap logic |

Endless mode generates its roads procedurally and doesn't use editor tracks. It shares the same road and terrain mesh code.

## 2. Editor tools

| Tool | What it does |
|---|---|
| **Road** | Place and drag spline control points. Per-point settings: width (left and right), banking, lanes, surface, curbs, barriers, run-off. |
| **Terrain** | Sculpt with raise, lower, smooth, flatten and noise brushes. |
| **Paint** | Paint terrain splat layers (grass, dirt, sand, rock, snow, gravel…). |
| **Props** | Place, rotate and scale props from the library. Scatter brush for trees and rocks. |
| **Pieces** | Snap stunt pieces onto the road (Kart, EDT-04). |
| **Race setup** | Start/finish, grid, sectors, checkpoints, AI line, respawn points. |
| **Environment** | Default time of day, weather, sky, ambient sound, suggested style profile. |
| **Test** | Drive it now (§6). |

### Road splines

- Cubic Bézier or Catmull-Rom control points, with handles.
- **Road mesh:** a cross-section profile extruded along the spline using parallel-transport frames. UVs are in metres, so retro textures tile cleanly.
- **Automatic curbs:** added on the inside and outside of corners above a curvature threshold. Editable per segment.
- **Barriers per side:** none, armco, concrete, tire wall, fence. Auto-placed at the run-off edge.
- **Run-off per side:** grass, gravel or asphalt, with a width.
- **Elevation:** a road either conforms to the terrain or is lifted off it. Lifted sections get supports automatically (bridges).
- **Junctions:** only highway merge/diverge lanes in M7. General intersections come later.

### Terrain

- Heightmap grid at 1 m resolution, in 256 × 256 m chunks, up to 4 × 4 km at first.
- **Road conform:** the terrain is flattened under the road, with a falloff band.
- **Collision:** `HeightMapShape3D` per chunk. Rendering uses chunked meshes with LOD.
- **Evaluate in M6:** the Terrain3D addon (MIT, GDExtension) versus our own implementation.

### Props

- A library of original retro-style assets: trees, buildings, grandstands, billboards, cones, tire stacks, crowd cut-outs, light poles.
- `MultiMeshInstance3D` for scatter. Each prop type has a simple collision shape.

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

- **Start/finish line and direction.**
- **Grid:** slots placed automatically behind the line (count and stagger).
- **Sectors:** 3 by default, movable.
- **Checkpoints:** invisible, automatic every ~100 m from the spline. Used for lap validity, wrong-way detection and respawn.
- **AI racing line:**
  - Generated automatically by **minimum-curvature optimization** within the road width.
  - A speed profile is estimated from a reference grip level.
  - Editable by dragging.
- **Pit lane:** later (M10).

## 5. File format: `.nosstrack`

A zip archive. Road, curb and barrier meshes are **rebuilt on load** from `track.json`, which keeps files small and deterministic.

```
my_track.nosstrack
├─ manifest.json    schema noss.track/1, id, version, name, author, license, type,
│                   attributions[], files {path: sha256}
├─ track.json       splines and attributes, pieces, prop instances, race setup, environment
├─ terrain/
│  ├─ meta.json     size, resolution, height scale
│  ├─ height.png    16-bit heightmap
│  └─ splat_0.png …
├─ scene/           imported 3D scenes only (§7)
│  ├─ scene.glb
│  └─ tags.json
├─ textures/        optional custom textures (≤1024², ≤20 MB total)
├─ thumb.png
└─ minimap.png      auto-rendered from above
```

- **Content hash** = SHA-256 of `manifest.json`, the same scheme as cars ([VEHICLE_PACKAGE.md §2](VEHICLE_PACKAGE.md#2-manifestjson)).
- **Default limits:** 100 MB per track, and 2 M triangles for imported scenes. Servers can lower them.
- **Safety:** the same rules as car packages ([VEHICLE_PACKAGE.md §9](VEHICLE_PACKAGE.md#9-limits-and-safety)). Never Godot resource files or scripts.
- **Sharing:** tracks auto-transfer when joining online (EDT-07, [NETWORKING.md](NETWORKING.md)).

## 6. Test-drive and editing comforts

- **Test-drive:** one key drops you in at the cursor (or on the grid) in your last-used car. Another key returns you to the editor at the same view.
- **Undo/redo:** a command stack, unlimited within a session.
- **Autosave:** every 2 min to `user://tracks/.autosave/`.
- **Validation:** before saving or sharing, the editor flags missing grid, unreachable checkpoints, or AI line errors ("No start line", "Gap at sector 2").

## 7. Map import

### 7.1 3D scene import, with Track Fitting (EDT-08, M6)

Use any modeled track or environment (glTF/GLB/FBX), the same way the Fitting Bay handles cars.

1. **Load:** the scene is validated and parsed on a worker thread. Limits: 2 M triangles, 200 MB unpacked.
2. **Tag surfaces:** click meshes or materials and assign a surface type:
   - drivable: asphalt, concrete, curb, grass, gravel, dirt, sand, snow, ice
   - `wall`, `no-collide` (visual only), `water` (respawn)
   - bulk rules by name, e.g. `*road*` / `*asphalt*` → asphalt
3. **Centerline:** click along the road to draw a centerline spline. Automatic tracing from the tagged road mesh is a stretch goal. The centerline drives checkpoints, track limits, respawn and the AI line.
4. **Race setup:** start line, grid, direction, sectors (§4).
5. **Collision:** generated per surface as static trimesh shapes.
6. **Style:** the scene keeps its own materials. "Apply style profile" optionally downsamples it to match `retro_ps2`.
7. **Save:** a `.nosstrack` containing `scene/scene.glb` (FBX is converted) and `scene/tags.json`.

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
