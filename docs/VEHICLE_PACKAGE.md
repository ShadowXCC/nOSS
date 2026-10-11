# Vehicle packages (`.noss`)

A `.noss` file holds one player vehicle: the model, its paint and engine sound, plus everything needed to mount it on any platform. Requirements: PKG-01…PKG-10, AV-05, AV-06, NFR-10.

---

## 1. Container layout

A `.noss` is a zip archive (stored or deflated):

```
my_car.noss
├─ manifest.json        identity, author, license, file hashes          (required)
├─ fit.json             orientation, scale, wheels, eye point, lights   (required)
├─ paint.json           paint slots, default colors, presets            (required)
├─ model/
│  ├─ body.glb          LOD0, full detail                               (required)
│  ├─ lod1.glb … lodN.glb   lower LODs; generated at pack time if missing (no textures)
│  └─ extra/*.glb       optional alternate parts (ignored for now)
├─ sound/               engine sound, customized by the player (§6)
│  ├─ profile.json      base profile, tweaks, recording map
│  └─ *.ogg / *.wav     own recordings (optional)
└─ thumb.png            512×288 garage thumbnail (rendered at pack time)
```

FBX imports are converted to GLB when packed (Godot `FBXDocument` → `GLTFDocument` export), so packages only ever contain glTF binaries.

## 2. `manifest.json`

```json
{
  "schema": "noss.package/1",
  "id": "5b0d3f0e-2c1a-4f53-9a57-1c8e2f6b7a10",
  "version": 3,
  "name": "1997 Acura NSX",
  "author": "ShadowXCC",
  "license": "personal-use-only",
  "family": "car",
  "tags": ["coupe", "1990s", "mid-engine"],
  "source": "fm4_to_noss 0.1 from ACU_NSX_97",
  "created": "2026-10-09",
  "game_min_version": "0.1.0",
  "files": {
    "fit.json":       "sha256:…",
    "paint.json":     "sha256:…",
    "model/body.glb": "sha256:…",
    "model/lod1.glb": "sha256:…",
    "sound/profile.json": "sha256:…",
    "thumb.png":      "sha256:…"
  }
}
```

- `id` stays the same across versions of the same car. `version` increments on each save.
- **Content hash** = SHA-256 of the exact `manifest.json` bytes. The manifest lists the hash of every other file, so one hash identifies the whole package. The packer writes canonical JSON (sorted keys, UTF-8, `\n` line endings).
- `license` is an SPDX identifier (e.g. `CC-BY-4.0`) or free text. The game shows it but doesn't enforce it.
- **In-game writer** (`PackageWriter`): validates `fit.json`, `paint.json` and `sound/profile.json`, writes the zip next to its target, loads it back with the normal loader, and only then replaces the old file. Saving a car unchanged keeps its file; any change bumps `version`. A new car gets a random UUID; a file that belongs to another car's id is never overwritten.

## 3. Model conventions

These match the FM4 rips, so those convert with no manual work. Models that don't follow them can still be fitted by hand (§7).

**Coordinates (glTF standard):** +Y up, +Z forward, +X is the car's left, units in metres. FBX units and axes are converted on import.

### Nodes

| Name | Meaning |
|---|---|
| `hub_LF`, `hub_RF`, `hub_LR`, `hub_RR` | Hub centers for 2-axle vehicles. Aliases of `hub_L1`, `hub_R1`, `hub_L2`, `hub_R2`. |
| `hub_<L\|R\|C><axle>` | General form. Axle 1 is the frontmost. `C` is a centerline wheel (3-wheelers, motorcycles). Dual tires sit under one hub. |
| `wheel_<id>` | Child of a hub. **Spins** around the hub's local X axis. May contain `rotor_<id>`. |
| `caliper_<id>` | Child of a hub. **Steers but doesn't spin.** |
| `steering_wheel` | Rotates with steering input (visual lock from `fit.json`). |
| `light_head_*`, `light_brake_*`, `light_reverse_*`, `light_indicator_L_*`, `light_indicator_R_*` | Light nodes or materials switched on by the game. FM4-style names like `headlight*` are matched by pattern. |

### Materials

| Name | Meaning |
|---|---|
| `Paint_Primary`, `Paint_Secondary`, `Paint_Tertiary` | Recolorable paint slots. An optional base-color texture acts as a multiply/detail layer (white = pure paint), as in FM4. |
| `Glass*` | Treated as transparent glass. Breaks with cosmetic damage. |
| anything else | Rendered as-is (PBR metallic-roughness) |

## 4. `fit.json`

```json
{
  "schema": "noss.fit/1",
  "model_transform": { "scale": 1.0, "rotation_deg": [0, 0, 0], "offset_m": [0, 0, 0] },
  "ground_y": -0.1445,
  "wheel_mode": "model",
  "wheels": [
    { "id": "LF", "axle": 1, "side": "L", "node": "hub_LF", "spin_node": "wheel_LF",
      "fixed_nodes": ["caliper_LF"], "center": [ 0.7963, 0.1568,  1.3335], "radius": 0.2999, "width": 0.215 },
    { "id": "RF", "axle": 1, "side": "R", "node": "hub_RF", "spin_node": "wheel_RF",
      "fixed_nodes": ["caliper_RF"], "center": [-0.7963, 0.1568,  1.3335], "radius": 0.2999, "width": 0.215 },
    { "id": "LR", "axle": 2, "side": "L", "node": "hub_LR", "spin_node": "wheel_LR",
      "fixed_nodes": ["caliper_LR"], "center": [ 0.7757, 0.1680, -1.2177], "radius": 0.3139, "width": 0.245 },
    { "id": "RR", "axle": 2, "side": "R", "node": "hub_RR", "spin_node": "wheel_RR",
      "fixed_nodes": ["caliper_RR"], "center": [-0.7757, 0.1680, -1.2177], "radius": 0.3139, "width": 0.245 }
  ],
  "steering_wheel": { "node": "steering_wheel", "visual_lock_deg": 450 },
  "eye_point": [0.36, 0.78, -0.25],
  "cameras": { "hood": null, "bumper": null },
  "envelope": { "min": [-0.89, -0.146, -2.13], "max": [0.89, 1.04, 2.05] },
  "lights": { "head": ["headlight*"], "brake": ["light_brake_*"], "reverse": [], "indicator_L": [], "indicator_R": [] },
  "exhaust_points": [],
  "hide_nodes": [],
  "lod_distances_m": [0, 12, 30, 70, 150, 300]
}
```

- `pivot` (per wheel): `node` (default) means `node` and `spin_node` exist in the model (FM4 convention). `insert` means the model has no hub nodes: the game makes `node` and `spin_node` at `center`, with the hub's X along the car's axle, and moves `spin_nodes` (and `fixed_nodes`) under them. The Fitting Bay writes this for wheels it detects, so the model never needs editing.
- `wheel_mode`:
  - `model`: the model's wheels are used.
  - `stock`: the model's wheels are hidden and the platform's stock wheels are drawn at the anchors.
  - `static`: the wheels are baked into the body and stay still, which is allowed but looks odd.
- `null` cameras are auto-placed from the envelope.
- `steering_wheel.visual_lock_deg` is the model's steering wheel rotation lock-to-lock, used with keyboard and controller. With a real wheel, the in-car wheel turns with it, up to the platform's lock.
- `hide_nodes` takes glob patterns, e.g. FM4 alternate race parts like `*race`.
- `lod_materials`: `own` (default) or `shared`. Generated LODs (§7 step 9) carry plain materials without textures; with `shared` the loader gives each LOD≥1 surface LOD0's material of the same name, so LODs add no texture memory (D40) and paint and lights still match by name.

## 5. `paint.json`

```json
{
  "schema": "noss.paint/1",
  "slots": {
    "primary":   { "materials": ["Paint_Primary"],   "color": "#FFD400", "finish": "solid" },
    "secondary": { "materials": ["Paint_Secondary"], "color": "#FFD400", "finish": "solid" }
  },
  "presets": [
    { "name": "Factory 1", "primary": "#FFD400", "finish": "solid" },
    { "name": "Factory 2", "primary": "#252295", "finish": "metallic" }
  ]
}
```

Finishes are `solid`, `metallic`, `pearl`, `matte` and `chrome`. Each maps to metallic, roughness and clearcoat values.

## 6. Engine sound (`sound/`)

*Requirements: AV-05, AV-06. Sound system and how players customize it: [ART_AUDIO.md §6](ART_AUDIO.md#6-engine-sound).*

Players customize each car's engine sound, and it is saved in the package with the model and paint. The Fitting Bay writes `sound/profile.json`. A package without it plays the family's default built-in profile.

A sound is either a **tuned built-in** (`base` + `tweaks`, no audio files) or **own recordings** (`layers` + `extras`, with tweaks on top):

```json
{
  "schema": "noss.sound/1",
  "name": "My V8",
  "base": "v8_crossplane",
  "tweaks": {
    "pitch": 0.95,
    "mix": { "engine": 0.8, "exhaust": 1.2, "intake": 0.6 },
    "idle_lope": 0.4,
    "turbo": "twin", "blowoff": true, "supercharger": false,
    "gear_whine": "straight_cut",
    "crackle": 0.7,
    "limiter": "bounce"
  },
  "rpm_idle": 800,
  "rpm_max": 7000,
  "layers": [
    { "emitter": "exhaust", "samples": [
      { "rpm": 1000, "on": "ex_on_1000.ogg", "off": "ex_off_1000.ogg" },
      { "rpm": 3000, "on": "ex_on_3000.ogg", "off": "ex_off_3000.ogg" },
      { "rpm": 6000, "on": "ex_on_6000.ogg", "off": "ex_off_6000.ogg" }
    ]}
  ],
  "extras": {
    "start": "start.ogg", "limiter": "limiter.ogg",
    "backfire": ["bf1.ogg", "bf2.ogg"], "turbo": null, "blowoff": null
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `base` | Yes | Built-in profile id. It fills any layer you didn't record, and it plays when a server turns off own recordings. |
| `tweaks` | No | `pitch` 0.8–1.2. `mix` per emitter 0–1.5. `idle_lope` and `crackle` 0–1. `turbo`: `none`, `single`, `twin`. `blowoff` and `supercharger` on/off. `gear_whine`: `normal`, `straight_cut`. `limiter`: `soft`, `bounce`, `cut`. |
| `rpm_idle`, `rpm_max` | With `layers` | The RPM range the recordings cover. It is remapped onto the platform's idle–redline. |
| `layers`, `extras` | No | Own recordings per emitter (`engine`, `exhaust`, `intake`). Omit them for a tuned built-in. |

- **Audio files:** OGG Vorbis (preferred) or 16-bit PCM WAV. Mono, 44.1 or 48 kHz, seamless loops (20 s at most). Paths are relative to `sound/`. Each file's header is checked before it's decoded (`SoundImport`); a profile naming a file the package doesn't have doesn't load.
- **Playing them:** each recorded emitter cross-fades its loops by rpm over `rpm_idle`–`rpm_max` (mapped onto the platform's idle–redline); an emitter without recordings plays the built-in `base`. An off-load loop falls back to the on-load one. Recorded extras replace the synthesized start, limiter, backfire, turbo and blow-off.
- **Recording** happens outside the game (any audio editor); the Fitting Bay imports the files (§7). Recording from a microphone in-game isn't planned (D88).
- **Hashed like everything else:** `profile.json` and every audio file are listed in the manifest `files`.
- **Never affects performance:** the platform decides power, revs and boost. The sound only follows them.
- **Limits:** 10 MB and 32 samples (§9).
- **Schema:** `data/schemas/sound.schema.json`; the loader rejects a profile that doesn't pass it.

## 7. Fitting Bay (in-game import)

*Requirements: PKG-02…PKG-04. Milestone M2.*

**How the automatic steps work** (`ModelImport`, `ModelAnalysis`):
- **Import:** a GLB that already passes §9 is stored byte for byte. Anything else (FBX through `FBXDocument`, `.gltf` with separate files, external, WebP or oversized textures) is re-exported through Godot into a plain GLB (PNG textures, JPEG if PNG would pass 50 MB; textures over 4096 are scaled down). Draco- and meshopt-compressed files are refused with "Re-export without compression". The resulting GLB is parsed again, so the bay sees exactly what the game will load.
- **Wheels:** named hubs if present. Otherwise round, thin parts: whole meshes, or connected parts inside a merged mesh (meshoptimizer-based, `NossMesh.components`). Parts on one axle line (tire, rim, disc) form a wheel; the wheels kept share an axle direction and similar radii. Wheel-like names (`wheel`, `tire`, `rim`…) count as extra evidence. Wheels merged into the body are split out into their own meshes.
- **Orientation:** the axle direction is the car's left-right; the spread of the wheel centres is its length; up is the side the car reaches further from its wheels. Front comes from names (`front`, `head`, `FL`… against `rear`, `tail`, `back`…) and the steering wheel; glTF's +Z breaks a tie. Rotations within 3° of a right angle snap to it.
- **Scale:** the wheelbase decides: a common unit (m, cm, mm, inch, foot) if one gives 1.8–3.6 m, otherwise whatever gives 2.6 m.
- **Other parts:** ground planes, stands and cloths (by name, or much bigger than the car's footprint) are hidden. `Paint_*` materials become slots; otherwise the body's main material is offered unless the wheels or glass use it too. Lights and the steering wheel come from names, the eye point from the steering wheel, hood and bumper cameras from the body's shape. A model whose wheels stand outside its body is `open`, others `car`.

| Step | What happens | Automatic? |
|---|---|---|
| 1. Import | Pick a `.glb`, `.gltf` or `.fbx` (Browse, or the `import/` folder next to the garage). It's checked, converted if needed and analysed on a worker thread. Name, author, license and type (car, open-wheel, truck) are set here. | Yes |
| 2. Orient | The yellow arrow shows the front. Buttons turn it 90°/180° or tip and roll it. | Yes, overridable |
| 3. Wheels | Found wheels are shown as rings. Without any (or by choice), `stock` or `static` wheels are placed with sliders: front and rear axle, track, radius, height. | Mostly |
| 4. Scale | From the wheelbase. The player can type the real length; the class may still scale it to fit (shown, e.g. "Scaled to 92%"). | Yes, overridable |
| 5. Paint | Each material can be primary, secondary, tertiary or not painted; then colour and finish per slot. | `Paint_*` materials, or the body's main material |
| 6. Cockpit | Sliders for the driver's eye, hood and bumper cameras, with a view from each. | Guessed |
| 7. Sound | Pick a built-in profile and tune it (§6); Rev to listen. **Own recordings** (M5): pick what a file is for (an emitter at an rpm and load, or an extra), then Add file; each is listed and removed by pressing it; Recorded idle and top set the range they stand for. | Type default |
| 8. Save | Pick a class and test-drive on the Proving Ground (the pause menu leads back), or save to the garage. **Save and drive** is there from step 1 on. | — |

- **Preview:** the car is always shown as the game will draw it, fitted to the chosen class, with that class's notes ("Scaled to 92%", "Wheels moved 4 cm in").
- **Saving** generates the LODs (meshoptimizer, D50) and renders the 512×288 thumbnail.
- **Drafts** live in `user://fitting/<id>/` as unpacked packages while being fitted, and are removed once the car is saved or thrown away.
- Not done: placing wheel anchors by clicking on the model. Editing a car keeps its recordings.

## 8. Garage and hotswap

*Requirements: PKG-05, PKG-06.*

- The garage lists the built-in cars and `user://garage/*.noss` with thumbnail, name, author, family and triangle count (counts are cached in `user://cache/garage_index.json`). The selected car turns on a turntable. Actions: drive (pick a class that takes it), edit in the Fitting Bay, paint (presets, colours, finishes), sound (the bay's sound step), duplicate, copy sound to another car, delete (asks first). Built-in cars can be driven and copied; editing one makes a copy.
- A car without `thumb.png` gets one rendered from the turntable, kept in `user://cache/thumbs/`.
- Editing a car keeps its own LODs and thumbnail while its model stays the same.
- **Hotswap** replaces only the visuals, engine sound and collision envelope. The platform and the physics state carry on, so the car keeps moving.
  - Allowed in lobby, practice, cruise, free roam and endless mode.
  - Locked mid-race unless the server allows it.
  - If the new envelope would overlap geometry, the swap waits until the car is clear (≤2 s), then nudges it up 0.6 m.
  - The in-session picker (Tab) only lists cars the current class accepts.
  - Online, the new content hash is broadcast and other players fetch it ([NETWORKING.md](NETWORKING.md)).

## 9. Limits and safety

*Requirements: PKG-08, NFR-10.*

**Default limits.** Servers can only lower them.

| Item | Limit |
|---|---|
| Package (zip) | 50 MB |
| Unpacked total | 150 MB |
| LOD0 triangles | 500,000 |
| Nodes / materials | 2,000 / 128 |
| Texture size | 4096 × 4096 |
| Decoded texture memory | 256 MB (RGBA pixels of all LODs, mipmaps not counted) |
| Sound pack | 10 MB, 32 samples max |
| Zip entries | 512 |

**Safety rules:**
- **Allowed file types:** `.json`, `.glb`, `.gltf` with embedded or zip-local buffers and images, `.png`, `.jpg`, `.ogg`, `.wav`. Everything else is rejected.
- **Zip checks:** no absolute paths, no `..`, no symlinks, and entry count and compression ratio are capped (zip-bomb guard).
- **Checked before full parsing:** GLB header and chunk sizes, accessor counts and image headers.
- **glTF:** an allowlist of extensions, and no external or remote URIs. Allowed: `KHR_materials_*` (clearcoat, emissive strength, IOR, specular, sheen, transmission, unlit, volume, pbrSpecularGlossiness), `KHR_texture_transform`, `KHR_mesh_quantization`, `KHR_lights_punctual`, `GODOT_single_root`. Rejected with a clear error: Draco, meshopt, WebP and BasisU.
- **Never loaded from a package:** Godot resource formats (`.tscn`, `.scn`, `.tres`, `.res`), scripts, shaders.
- **Isolation:** parsing runs on a worker thread with a timeout. On any failure the player sees "Car failed to load" and a placeholder appears in its place.
- **Hash check:** every file is verified against the manifest before use.

## 10. Runtime load pipeline

*Target: NFR-04. A 200k-triangle car is drivable in under 5 s; steps 1–2 run off the main thread.*

1. Verify the zip and the manifest hashes, then check the limits.
2. `GLTFDocument.append_from_buffer()` → `generate_scene()` on a worker thread. Mipmaps are generated for every texture; cameras and animation players in the model are dropped.
3. Apply `fit.json`: transform, find hubs, hide nodes, map lights.
4. Paint: replace `Paint_*` materials with the `noss_paint` shader material (slot color, finish, detail texture).
5. LODs: attach `lodN.glb` meshes with visibility ranges from `lod_distances_m`.
6. Cache the result in `user://cache/<hash>/` (machine-generated `.scn`) for fast reloads. *Deferred (D41): FM4 cars already load in about 2 s.*
7. Mount on the platform ([PLATFORMS.md §4](PLATFORMS.md#4-fitting-and-handling-normalization)).

## 11. FM4 converter (`tools/fm4_to_noss.py`)

*Requirement: PKG-09. Milestone M1. Local use only. Packages it makes are marked `personal-use-only`, which keeps them off the network: online they can't be picked, aren't AI cars and are never sent ([NETWORKING §7](NETWORKING.md#7-content-transfer)).*

```
python3 tools/fm4_to_noss.py "<…>/Forza Motorsport 4/models/ACU_NSX_97"   # into the garage
python3 tools/fm4_to_noss.py "<…>/Forza Motorsport 4/models"              # every car in the folder
```

The default output is the game's garage (`user://garage/`); `--out` picks another folder. The package id comes from the media name, so re-running updates the same car: an unchanged car is left alone, a changed one gets `version` + 1.

| FM4 rip (`car.json`, `paint.json`, GLBs) | `.noss` | Notes |
|---|---|---|
| `<media>.glb` | `model/body.glb` | LOD0 |
| `<media>_lod1…5.glb` | `model/lod1…5.glb` | |
| `<media>_parts.glb` | — | Skipped for now |
| `hubs.XX.position` | `wheels[XX].center` | Already in glTF space |
| `hubs.XX.radius`, `.width` | `wheels[XX].radius`, `.width` | |
| node layout `hub_XX` / `wheel_XX` / `caliper_XX` | `node`, `spin_node`, `fixed_nodes` | Same names |
| mean of `hub.y − radius` | `ground_y` | Cross-checked against `front/rear_ride_height` |
| GLB AABB | `envelope` | `collision_box_fm4_space` used only as a cross-check |
| `dimensions.wheelbase`, `*_track_outer` | — (derived from wheels) | Warning if it differs from the derived value by >1 cm |
| `curb_weight_kg`, `weight_distribution_front` | **ignored** | The platform decides mass. Rip values can be wrong (NSX says 13.6 kg). |
| interior node `steering_wheel` | `steering_wheel.node` | |
| `seatL`/`seatR` mesh bounds, `steering_wheel` | `eye_point` | Seat's lowest point + 0.75 m (capped 0.17 m below the roof), 0.30 m forward of the seat back, in line with the steering wheel (D39). The driver's side comes from the steering wheel's x; `--rhd`/`--lhd` override it. Adjust in Fitting Bay. |
| sections `headlight*` | `lights.head` | Pattern |
| materials `tail_light*`, `reverse_light*` | `lights.brake`, `lights.reverse` | Brake lights glow while braking |
| nodes `exhaust*` | `exhaust_points` | |
| `previews/<media>_front34.png` | `thumb.png` | Copied as is (not resized) |
| `paint.json` `materials_in_glb` | `paint.slots` | |
| `paint.json` `factory_colors[]` | `paint.presets[]` | `Normal` → `solid`, `Metallic` → `metallic` |
| `year`, `make`, `media_name` | `manifest.name`, `source`, `tags` | "1997 Acura" + model, from media name |
| — | `sound/profile.json` | Family default `base`. `--sound <id>` picks another. Tune it later in the garage. |

### Worked example: ACU_NSX_97

From `car.json`:
- **Wheelbase:** front hub z 1.3335 − rear hub z (−1.2177) = **2.551 m**, matching `dimensions.wheelbase` 2.55124. ✓
- **Front track at the hubs:** 2 × 0.7963 = **1.593 m**. Rear: 2 × 0.7757 = 1.551 m. Average **1.572 m**.
- **Ground:** front 0.1568 − 0.2999 = −0.1431 m, matching `front_ride_height` 0.143124 ✓. Rear 0.1680 − 0.3139 = −0.1459 m, matching `rear_ride_height` 0.145856 ✓. Mean `ground_y` = **−0.1445 m**.
- **Mounted on Track / GT** (wheelbase 2.30–2.95, track 1.45–1.75): both are in range, so there is **no scaling and no clamping**. The geometry adapts and the §4.2 invariants keep handling identical to the reference.
