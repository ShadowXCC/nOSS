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
| Particles | Low-count billboards: tire smoke, sparks, gravel, rain spray |
| Budget | Steam Deck 60 fps @ 1280×800 Low (NFR-02) |

**M1 (`retro_ps2` v0):** exponential distance fog, a painted sky shader (gradient, sun, cloud layer, two distant mountain silhouettes) that also feeds car reflections, procedural 64–256 px world textures, one low-res sun shadow, filmic tonemap and mild glow. The data lives in `data/styles/retro_ps2.json`; tracks use the `noss_world` shader, which reads the style's global uniforms.

**Authoring rule:** world assets are made at retro budget, and may include optional hi-res texture sets (`_hi`, up to 2K) for future profiles. All world materials use the `noss_world` shader so profiles can restyle them.

## 3. Content and licensing

- **Licenses:** everything shipped is original (made for nOSS, CC-BY-SA 4.0) or license-compatible third-party content (CC0, CC-BY, CC-BY-SA), credited in `CREDITS.md`.
- **GT4 textures** are *reference only*: palette, composition and mood. They are never copied, traced or shipped. The same goes for **FM4 cars**.
- **M1 placeholder content (original):**
  - **"nOSS Box":** a simple low-poly default car that follows the package conventions.
  - **"Proving Ground":** a ~2 km test circuit with a skidpad and a long straight, used for conformance tests ([PLATFORMS.md §5](PLATFORMS.md#5-conformance-tests)).
  - Procedural and simple textures in the retro style.

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
- **Later:** I3, I5, I6, flat-4, V6, flat-plane V8, V10, V12, 2-rotor rotary, diesel (truck), 2-stroke (kart), single and twin (moto), V-twin.
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
| Modes | Kart items, police sirens (with Doppler), traffic pass-bys, countdown and finish stings |
| World | Ambience per biome and track, rain, thunder |
| UI | Short, retro-styled clicks and confirms |
| Music | Original or CC-licensed menu and endless playlists, plus an optional user music folder (local OGG/MP3) |

**Splitscreen mix:** see [ARCHITECTURE.md §6](ARCHITECTURE.md#6-local-players-splitscreen-and-multi-monitor).

## 8. Later extras

| Extra | Notes |
|---|---|
| **Livery editor** (PKG-10) | Decals and vinyl layers on paint slots, projected in UV or object space, shareable as small files. Uses FM4-style livery masks when a model includes them. |
| **Replays and photo mode** (AV-08) | Built on the network state stream. TV cameras, free cam, depth of field, filters. |
| **Telemetry out** (AV-10) | UDP packets with the sim outputs ([PHYSICS.md §14](PHYSICS.md#14-outputs)) for SimHub, motion rigs and dash displays. Documented format, configurable rate and port. |
| **VR** (AV-09) | Godot OpenXR cockpit view. Monado or SteamVR on Linux. |
