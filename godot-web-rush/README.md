# Web Rush — Godot 4

A Godot 4 remake of the browser-based Spider-Man web-swinging prototype in
[`../spider-man-swinging`](../spider-man-swinging). Procedural city, fixed-step
rope physics, wall crawling, thugs that fight back.

## Status — read this first

**This project has never been run.** Executing a downloaded Godot binary in the
container this was written in was blocked by the sandbox's permission system, so
every file here was authored as text and not one line of it has been through
Godot's parser, let alone played. That is a real caveat, not a formality: expect
a first pass of parser and API errors to shake out, and expect the bone-rotation
axes to need checking (see *Animation* below).

What that means practically: open the project, press play, and send me whatever
the Output panel says. The physics, the city generation and the combat state
machine are direct ports of code that was measured and tuned in the browser
build, so the *behaviour* is known-good; the risk is in the translation, not the
design.

## Run it

Open `project.godot` in Godot 4.3 or newer and press Play. Godot imports
`assets/models/spiderman.glb` on first open, which takes a moment.

No addons, no build step, no C# — plain GDScript.

## Controls

| Input | Gamepad | Action |
| --- | --- | --- |
| `W A S D` | Left stick | Run |
| Mouse | Right stick | Look / aim |
| Left click (hold) | R2 (hold) | Shoot a web and swing |
| `W` while swinging | Left stick | Pump — thrust along your aim, and reel in |
| `A` / `D` while swinging | Left stick | Steer the arc |
| `Space` while swinging | Cross ✕ | Release — at the flat, fast part of the arc it's a **perfect release** |
| `S` in the air | Left stick down | **Dive** — trade height for speed |
| Touch a wall | — | **Stick to it**: `W`/`S` climb, `A`/`D` crawl, `Space` jumps off |
| `E` | Square ▢ | Punch |
| `Q` | R1 | Web-zip to your aim point |
| Right click (hold) | L2 (hold) | Aim (soft lock-on, narrowed camera) |
| `C` | Circle ○ | Dodge — time it to your spidey sense |
| `Shift` | L1 / L3 | Sprint |
| `Esc` | Options | Pause |

## What the engine change actually bought

Being specific about this, because the honest answer is narrower than "Godot is
better":

**Gained outright.** A real renderer: glow on the window lights and crime
beacons, SSAO, ACES tonemapping, distance fog and a procedural sky, all
configured in `scenes/Main.tscn` rather than hand-rolled as post-processing
passes. Shadow-casting directional lights. Physics-engine raycasts for the web
shot, the aim ray and the camera's occlusion probe, replacing manual
ray-vs-box intersection.

**Gained for free.** The fixed timestep. The browser build needed an
accumulator to run the rope constraint at a stable 120Hz; `project.godot` pins
`physics_ticks_per_second` to 120, so `_physics_process` *is* the fixed step and
`delta` is exactly 1/120 on every call.

**Available but not yet used.** `AnimationTree`, blend spaces and
`SkeletonIK3D`. This is the strongest argument for Godot on this project and the
thing most likely to fix the "animations are goofy" problem for real — the
reaching arm is currently a two-axis approximation where `SkeletonIK3D` would
solve the whole chain. The port deliberately kept the browser build's tuned
poses so the two can be compared directly before anything is replaced.

**Lost.** DualSense adaptive triggers. See below.

**Not gained, contrary to expectation.** Motion blur. It is not a built-in in
Godot 4 either — the Environment has glow, SSAO, SSIL, SSR, depth of field, fog
and tonemapping, but no camera motion blur; it is one of the engine's
longest-standing feature requests. What ships here instead is
`shaders/speed_blur.gdshader`, a radial blur driven off the player's speed and
centred on the direction of travel. That is what the effect reads as in the
console games anyway: the frame smearing outward while the middle stays
readable. A true per-object motion blur would mean a custom `CompositorEffect`
with its own compute shader.

## The swing

Everything in `PlayerController` is integrated by hand rather than through
`CharacterBody3D`, because the feel lives in a handful of numbers that were
measured against this exact collision response and `move_and_slide` would
quietly substitute its own. Collision is a circle-vs-AABB push-out against the
city's own box list, which at 120Hz is plenty: the player covers ~0.7 m per step
even at full speed, far smaller than any building, so nothing tunnels.

- **Rope constraint with velocity projection.** After clamping position onto
  the rope sphere, only the component pulling *away* from the anchor is
  cancelled — a rope pulls, never pushes. Recomputing velocity from the
  corrected position instead feeds the correction back as fake acceleration
  and buzzes.
- **Quadratic drag**, semi-implicit (`v /= 1 + k·|v|·h`), unconditionally
  stable, giving real terminal velocities: ~55 m/s falling, ~65 on a line,
  ~78 in a dive.
- **Angular-momentum reeling.** Shortening the line raises tangential speed as
  the radius drops, so reeling at the bottom of an arc is a genuine technique.
  Capped — unbounded it reached 130 m/s in 1.5s.
- **Arc-aware rope length.** A pendulum's lowest point is one rope-length below
  its anchor, so a rope longer than the anchor is high puts the bottom of the
  arc underground and the "swing" just scrapes the pavement.
- **Anchors go above the roofline**, never on the facade you're flying at — a
  web stuck to a wall ahead puts that building inside your own arc.
- **Directional pump.** Holding forward thrusts along the direction you're
  *facing*, projected onto the plane the taut rope allows. Pushing along
  current velocity instead feeds a conical orbit: measured, 56 m/s of speed
  and 3 m/s of actual progress across the city.
- **Perfect release.** Letting go while moving fast and close to horizontal
  keeps everything and launches. Let go while still falling and you just drop.
- **Momentum is never scrubbed.** Air control can only *add* speed along the
  direction you push. The obvious version — accelerate then clamp horizontal
  speed — quietly destroyed the traversal game: launching out of a swing at
  52 m/s and holding forward clamped you straight back to 22, so a perfectly
  timed release ended *slower* than a lazy one. After the fix, 52 → 60.

Street width matters as much as any of it: at the original 42 m grid the avenues
were ~18 m across, narrower than one swing arc, so every attach ended in a
facade. The 84 m grid took chained traversal from **50 m to ~420 m per 15
seconds**, averaging ~28 m/s with peaks around 68.

## The city

Streamed in 84 m cells around the player, every cell's contents derived from a
hash of its grid coordinates, so a cell rebuilt after you wander away and come
back is identical rather than popping into a different skyline.

Buildings share one unit cube scaled per instance and a small cache of facade
materials bucketed by tint, window warmth and UV tiling. The first version
built a fresh mesh and a fresh material per building, which at 13x13 streamed
cells meant ~170 of each resident at all times, none able to batch. The cache
collapses that to a few dozen shared materials, which is what makes the rooftop
detail affordable.

Above the roofline is where you spend the whole game, so the roofs are dressed:
water towers, vent housings, antenna masts on the tallest buildings, and red
aviation beacons on anything over 60 m. The beacons are deliberately
over-bright — with glow on they bloom into the fog and give the skyline a
readable top edge from across the city, which is what you need when you're
picking a web anchor at 60 m/s. Street lamps are emissive geometry with no
`OmniLight` behind them; a real light per lamp across 169 cells would be
hundreds of point lights for scenery you mostly fly over.

Window emission colour varies per building — cool offices beside warm
apartments — because one uniform sheet of glass is what makes a procedural
skyline read as procedural.

## Animation

The source model ships with no animation clips, so every pose is driven by
rotating named rig bones each frame. `PlayerRig` keeps the pose as Euler angles
per bone and converts once per frame, because Godot's `Skeleton3D` has no
per-axis accessor and the lerp/blend helpers need to read back what they wrote
last frame.

**Two conventions to check if a limb comes out wrong:**

1. **Euler order.** Three.js defaults to XYZ; Godot's `Quaternion.from_euler()`
   uses YXZ. Composing the same three numbers in a different order gives a
   different rotation, so `Basis.from_euler(..., EULER_ORDER_XYZ)` is used
   explicitly throughout to keep the tuned angles meaning what they meant.
2. **Bone local axes.** Which local axis swings a limb forward vs sideways, and
   which sign means which direction, was determined empirically per bone in the
   browser build — the rig documents neither. Godot's glTF importer *should*
   preserve those bases, but if an arm rotates about the wrong axis this is the
   first thing to check. Set `DEBUG_BONE` on the `PlayerRig` node to a key of
   `BONE_NAMES` to freeze every other bone and sweep that one joint through
   each axis in turn.

Stand perfectly still for ~5.5s and he pulls out a **Rubik's cube** and works
on it, blending out the moment you move.

## Gamepad

Rumble works through `Input.start_joy_vibration`, driven by impacts, landings,
web attaches, perfect dodges and perfect releases.

**Adaptive triggers do not, and this is a real regression from the browser
build.** That version reached the DualSense's trigger resistance through WebHID,
writing the raw HID output report directly. Godot exposes no equivalent — there
is no raw HID API in GDScript — so getting it back means a GDExtension wrapping
`hidapi` and porting `DualSenseHID.js`'s report framing (USB report `0x02` vs
Bluetooth `0x31` with a trailing CRC32, taken from the Linux kernel's
`hid-playstation.c`). The rope tension that drove it is still computed every
swing step and exposed as `InputManager.trigger_tension`, so that extension
would have somewhere to plug in without touching the physics.

## Project layout

```
project.godot              config; pins the physics tick to 120Hz
scenes/Main.tscn           structural nodes, lights, Environment (glow/SSAO/fog/sky)
shaders/speed_blur.gdshader radial speed blur
scripts/Game.gd            scene wiring, mode state machine, speed-blur driver
scripts/City.gd            procedural streamed city, collision, wall probe, spawns
scripts/PlayerController.gd fixed-step physics, swing, wall crawl, dive, zip, camera
scripts/PlayerRig.gd       model loading, runtime colouring, all bone animation
scripts/InputManager.gd    keyboard/mouse + gamepad, mouse capture, rumble
scripts/Enemy.gd           thug NPC state machine
scripts/CrimeSystem.gd     crime spawning, spidey sense, soft lock-on
scripts/HUD.gd             HUD and menus, built in code
assets/models/spiderman.glb player/enemy model
```

The HUD and menus are built in GDScript rather than laid out in a `.tscn`. That
is a trade for this stage: one source of truth that cannot drift out of sync
with the code driving it. Moving it into a scene and editing it visually is a
natural next step and nothing depends on it staying in code.

## Assets

The player model is ["Spiderman Brand New Day"](https://sketchfab.com/3d-models/spiderman-brand-new-day-ef54026773e14cffad16359fd771c5f8)
by [mpolo0604](https://sketchfab.com/mpolo0604), licensed
[CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/). It ships as geometry +
skeleton only; its ~18MB of textures were stripped, and the suit is coloured at
runtime from the mesh's own material names plus a procedural web pattern. The
thug is the same mesh recoloured.

> This work is based on "Spiderman Brand New Day" by mpolo0604, licensed under
> CC-BY-4.0. The character is Marvel's IP; this asset is included for this
> prototype only, not for redistribution or commercial use.

## Known limitations

- **Never executed** — see *Status*.
- Building collision is a circle-vs-AABB push-out, not a capsule sweep.
- Rooftop props and street lamps are decoration only — the collision model is
  still one box per building, so you can walk through a water tower. Giving
  each prop a body would mean teaching `resolve_horizontal_collision` about
  several boxes per cell, which isn't worth it for scenery you're near for a
  couple of seconds.
- Wall crawling only handles the four vertical faces of a box — no ceilings, no
  sloped geometry, and corners are a hard switch between faces.
- One enemy type, one attack, no ranged combat, no multi-thug coordination.
- The reaching arm is a two-axis approximation, not `SkeletonIK3D`.
- No adaptive-trigger support (see *Gamepad*).
- Input is read off the hardware directly rather than through `InputMap`, so
  there is no remapping UI.
