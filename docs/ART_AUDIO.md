# Art, audio, cameras, UI

The look, sound and presentation of nOSS. Requirements: AV-01…AV-10, NFR-06.

---

## 1. Visual direction

**The world is retro and the cars are not.** The world recalls PS2-era racers (Gran Turismo 4, early Midnight Club): low-res textures, strong fog, painted skies and glossy cars. Player cars always render at full detail.

The world look is a swappable **style profile** ([ARCHITECTURE.md §7](ARCHITECTURE.md#7-render-style-profiles)). `retro_ps2` is the first profile. Others (`modern`, stylized, community) plug in later without rebuilding tracks.

## 2. `retro_ps2` style profile (default)

| Aspect | Spec |
|---|---|
| World textures | 512 px max (most 256), bilinear plus mip bias, no normal maps by default |
| Lighting | One directional sun plus an ambient sky color. Baked vertex color or AO for the "baked" look. No SSR, SSAO or GI. |
| Shadows | Projected blob or low-res shadow under cars. Optional low-res cascaded sun shadows. |
| Fog | Strong distance fog that fades to the horizon, plus height fog in valleys |
| Sky | Textured dome (gradient plus cloud layer) and a distant skyline/mountain strip, as in GT4's `far` role |
| Distant scenery | Cut-out billboards for crowds and far trees |
| Post | Mild bloom, per-time-of-day color grade. Optional "Authentic" toggles: render-scale downsample (e.g. 480p, nearest upscale), dithering, scanlines. All per viewport. |
| Car reflections | Blurred environment cubemap updated at a low rate, for the shiny GT4 paint look. Cars are full PBR with clearcoat. |
| Particles | Low-count billboards: tire smoke, sparks, gravel, rain spray; tire tracks in snow and off the road (D197) |
| Budget | Steam Deck 60 fps @ 1280×800 Low (NFR-02) |

**M1 (`retro_ps2` v0):** exponential distance fog, a painted sky shader (gradient, sun, cloud layer, two distant mountain silhouettes) that also feeds car reflections, procedural 64–256 px world textures, one low-res sun shadow, filmic tonemap and mild glow. The data lives in `data/styles/retro_ps2.json`; tracks use the `noss_world` shader, which reads the style's global uniforms.

**M9 (time of day and weather, D153):** the sun and the moon are one directional light, crossing over below the horizon. The sky shader gets the sun and moon, night (stars, a moon), cloud cover and storm darkness; fog, ambient light, exposure and the sky's colours come from the style's palettes by the sun's height (`times`: night, twilight, golden hour, day; `overcast` for cloud and storms). World shaders read four globals: `env_wetness` (darker, shinier paved surfaces), `env_snow` (snow settling on what faces up; on paved surfaces a dusting of specks and wind-drawn patches, D197), `env_night` (lamps and lit windows glow only after dark) and `env_flicker` (old lamps flicker, each in its own time; 0 with Reduce flashing, D221). Headlights, tail lights and lit beams (players' cars and the four nearest) come on at dusk, in rain and in fog. Rain and snow are streaks wrapped round each player's camera by one shader, with nothing to simulate; spray rises behind cars on wet roads. Highway tunnels stay dry. Wheels leave tracks in fallen snow and on grass, dirt, sand and gravel, which fade after a minute or so (`TireTracks`, D197). Lightning lights each player's view on its own, with a bolt in the sky (none with Reduce flashing, [ACCESSIBILITY.md §4](ACCESSIBILITY.md#4-motion-comfort-and-flashing)).

**Authoring rule:** world assets are made at retro budget, and may include optional hi-res texture sets (`_hi`, up to 2K) for future profiles. All world materials use the `noss_world` shader so profiles can restyle them.

## 3. Content and licensing

- **Licenses:** everything shipped is original (made for nOSS, CC-BY-SA 4.0) or license-compatible third-party content (CC0, CC-BY, CC-BY-SA), credited in `CREDITS.md`.
- **GT4 textures** are *reference only*: palette, composition and mood. They are never copied, traced or shipped. The same goes for **FM4 cars**.
- **M1 placeholder content (original):**
  - **"nOSS Box":** a simple low-poly default car that follows the package conventions.
  - **"Proving Ground":** a ~2 km test circuit with a skidpad and a long straight, used for conformance tests ([PLATFORMS.md §5](PLATFORMS.md#5-conformance-tests)).
  - Procedural and simple textures in the retro style.
- **M8 kart content (original, made in code):** the **nOSS Kart** (`tools/make_noss_box.gd --kart`: a low frame, side pods, a driver, paint slots and presets); five kart tracks (`tools/make_kart_tracks.gd`: Marble Mile, Gearworks, Skyhop Ridge, Crate Yard, Dust Bowl, D147); props for yards and arenas (crate, shipping container, yard crane); item boxes (a turning crate with an original glyph whose colours shift slowly), the items themselves, drift sparks, boost flame, shield, the EMP ring, spin stars and the tow drone. No item effect flashes the whole screen; with Reduce flashing they keep under 3 flashes a second (D146).
- **M9 endless content (original, made in code):** eight biomes (`data/endless/biomes/<id>.json`, schema `endless_biome`: ground paint, road, props and how dense, sky and fog tints, far-ground colour, sounds, weather odds; a biome's own sun, fog colour, fog floor and front odds, D221): coast, forest, farmland, desert canyon, alpine, snow, autumn and Haunted, after GT4-era places but nothing copied. New props: cactus, palm, cypress, an autumn tree, a snowy pine, hay bales, a barn, a chalet and curve chevrons; for Haunted (D221) a dead tree, a gravestone, a jack-o'-lantern (its face glows after dark), wrought iron railings and an old lamp (its glass glows after dark and flickers); bridges with pillars and guard rails come from the road builder; the sea is a plane along the coast. No new lights: the glow is emission (D205).

## 4. Cameras

| Camera | Milestone | Notes |
|---|---|---|
| Chase (near and far) | M1 | Spring-damped, speed-based FOV |
| Cockpit | M1 | Uses the model's interior and `eye_point`. Head movement from g-forces (adjustable). The `steering_wheel` node rotates. Optional look-to-apex. |
| Hood, bumper | M2 | From `fit.json` `cameras` (the Fitting Bay measures them on the model), or placed automatically: hood 62% of the way from the eye point to the nose, just below eye height; bumper 0.42 m up at the nose. Fixed to the car; horizon lock applies. |
| TV / replay | M10 | Trackside cameras placed by the editor, or automatic |
| Free / photo | M10 | Photo mode (AV-08) |
| VR cockpit | M10+ | OpenXR (AV-09) |

FOV is per camera and per player. Each viewport has its own camera ([ARCHITECTURE.md §6](ARCHITECTURE.md#6-local-players-splitscreen-and-multi-monitor)).

## 5. UI and HUD

- **Short, direct text** (NFR-06): "Lap 2/5", "P3", "+0.42", "Car loaded", "Track limits", "Busted", "Combo ×4". No sentences on the HUD.
- **Retro theme:** chunky and bold, matching the world style. OFL-licensed fonts.
- **HUD:** speed (km/h or mph), gear, RPM bar, position, lap and timing, delta, minimap. Mode extras: item slot, combo meter, heat. Scales per viewport (NFR-08).
- **Colorblind-safe palettes** for UI states and the racing line. All vision, hearing and motion options: [ACCESSIBILITY.md](ACCESSIBILITY.md).

## 6. Engine sound

*Requirements: AV-05, AV-06.*

Players can customize every car's engine sound, and the result is saved inside the car's `.noss`.

### System
- **Sample-based:** looped recordings at RPM points, with **on-load** and **off-load** variants, cross-faded and pitch-shifted between points.
- **Emitters:** engine, exhaust and intake as separate 3D sources on the car.
- **Layers:** turbo spool and whistle, blow-off, supercharger whine, gearbox whine (straight-cut option), lift-off crackle and backfire, limiter bounce, starter.
- **Driven by the sim:** RPM, throttle, load (fraction of torque), boost, shift events.
- **The sound never affects performance.** A profile's RPM range is remapped onto the platform's idle–redline, so a V12 profile works on a 7,000 rpm platform.

**Synthesized (M2, D53):** the built-in profiles are original sound, made when a profile is first used (`NossAudio`, about 50 ms per profile). Each loop holds whole engine cycles: a pulse per firing at the crank angles of the firing order, through resonant exhaust (per bank, with its own pipe resonance and delay) and intake filters, plus block and valvetrain noise and small cycle-to-cycle variation. The filters run to steady state, so loops are seamless. Electric profiles use motor and inverter harmonics instead. Loops are made at six rpm points, on- and off-load, for each emitter; the player cross-fades the two points around the current rpm and pitches them to it. Tire squeal, wind and the tweak layers (turbo whistle, blow-off, supercharger and gear whine, crackle pops) are synthesized too.

### Built-in profiles
- **M2 starter set:** I4, cross-plane V8 (firing order 1-8-4-3-6-5-7-2: each bank fires unevenly, hence the burble), flat-6, EV. Data in `data/sound_profiles/<id>.json`.
- **M8:** 2-stroke (kart): one firing a turn, a bright expansion-chamber exhaust; the nOSS Kart's sound.
- **Later:** I3, I5, I6, flat-4, V6, flat-plane V8, V10, V12, 2-rotor rotary, diesel (truck), single and twin (moto), V-twin.
- **Sources:** synthesized (original). Recordings (original or CC0/CC-BY, tracked in `CREDITS.md`) can replace a profile later with the same player.

### Player customization

Every car carries its own engine sound inside its `.noss` (`sound/`, format in [VEHICLE_PACKAGE.md §6](VEHICLE_PACKAGE.md#6-engine-sound-sound)). The sound goes wherever the car goes: garage, hotswap, online.

| Level | What the player does | Size |
|---|---|---|
| **Tune** a built-in | Pick a base profile, then adjust pitch, emitter mix, idle lope, turbo, blow-off, supercharger, gear whine, crackle and limiter. | < 1 KB, no audio files |
| **Record** your own | Add your own samples at RPM points (on-load and off-load) plus extras (start, limiter, backfire). Tweaks still apply. Any layer you skip comes from the base profile. | ≤ 10 MB |

- **Where:** the Fitting Bay sound step, or **Sound** in the garage for an existing car. Rev in neutral, run a dyno sweep or test-drive while you listen.
- **Reuse:** "Copy sound" applies one car's sound to another car in the garage.
- **Sound only:** picking a turbo layer doesn't add a turbo. If the platform has no boost, the turbo layer follows throttle and RPM instead.
- **Online:** auto-transferred with the car. Tuned built-ins always play, since they use shipped samples. Servers can turn off own recordings; those cars then play their base profile with tweaks.

## 7. Other audio

| Category | Sounds |
|---|---|
| Tires | Squeal by slip, scrub, skid, surface layers (gravel spray, grass, curb rumble) |
| Car | Wind (by speed), suspension bottoming, transmission clunk, horn set, collisions (light, heavy, scrape), glass break |
| Modes | Kart items (M8, synthesized by `NossAudio.render_fx`: pickup, roulette tick, fire, hit, shield, EMP, boost, drift tier step), police sirens (with Doppler), traffic pass-bys, countdown and finish stings |
| World | Rain, wind and thunder with the weather; per endless biome (or a track's setting) surf, birds by day, crickets at night, wind and distant thunder (M9, D221) |
| UI | Short, retro-styled clicks and confirms |
| Music | Endless: original ambient pieces made from the road's seed, or your own OGG/MP3 files from the music folder (M9). Menu music later |

**Tire sounds (D90):** each car picks a built-in tire sound in the Fitting Bay's Sound step (`data/tire_sounds/<id>.json`, schema `tire_profile`), or brings its own loop over it. **Squeal** (the default) is synthesized by `NossAudio.render_tire_loop`: noise through narrow band-passes at non-harmonic centres (about 1.05, 1.73 and 2.6 kHz), a faint tone that wanders at random, and a random flutter of the level, in a seamless 2.5 s loop. Its level follows the fastest-slipping wheel on a paved surface (1.5 m/s starts it, 7.5 m/s is loudest), comes in fast (30 ms) and fades slowly (160 ms), and a broad scrub layer joins in for locked or spinning wheels. **Classic** is the first nOSS tire tone, kept as it was. A new built-in is a new JSON file. The Sound step's **Skid** button plays the tires in the bay.

**Highway sounds (M7):** sirens are synthesized by `NossAudio.render_siren` (a 4 s wail, a faster yelp within 80 m of the listener, with Doppler as they pass); the horn by `NossAudio.render_horn` (two tones, a seamless half-second loop) for every car, remote ones from their states; traffic near players shares six engine loops (a light I4 and a heavy V8 made by the engine synth) instead of a sound per car (D120).

**Traffic and police models (M7, D117):** seven original low-poly vehicles made in code by `tools/make_traffic_set.gd` (hatchback, saloon, SUV, van, box truck, bus, police), each with a far LOD merged into one mesh per type (drawn with one MultiMesh, paint from each car's colour, brake and indicator lights from bits) and light groups (head, brake, indicators; the police car's light bar halves). The city round the Lumen Ring is props made in code too: four tower types, a landmark tower, overpasses, sign gantries, crash cushions, double lamps and laybys.

**Weather and music (M9):** rain, wind, surf, crickets and birds are synthesized seamless loops and thunder a one-shot (`NossAudio.render_weather`, seeded noise, the same every time); rain is noise only, a hiss, the fizz of near drops and a few soft pats, with nothing pitched (D197), played on the Ambience bus with levels that follow the weather and the biome; thunder comes after a strike at the speed of sound. The endless road's music (`NossAudio.render_music`, D157) is a 64 s loop per seed: a slow progression of eight chords on soft detuned pads, a quiet bass and a few bell notes, with an echo; each seed gives its own key, chords and melody. Each piece plays twice, then the next fades in over 6 s. OGG or MP3 files in `user://music/` play instead, shuffled.

**Splitscreen mix:** see [ARCHITECTURE.md §6](ARCHITECTURE.md#6-local-players-splitscreen-and-multi-monitor).

## 8. Later extras

| Extra | Notes |
|---|---|
| **Livery editor** (PKG-10) | Decals and vinyl layers on paint slots, projected in UV or object space, shareable as small files. Uses FM4-style livery masks when a model includes them. |
| **Replays and photo mode** (AV-08) | Built on the network state stream. TV cameras, free cam, depth of field, filters. |
| **Telemetry out** (AV-10) | UDP packets with the sim outputs ([PHYSICS.md §14](PHYSICS.md#14-outputs)) for SimHub, motion rigs and dash displays. Documented format, configurable rate and port. |
| **VR** (AV-09) | Godot OpenXR cockpit view. Monado or SteamVR on Linux. |
