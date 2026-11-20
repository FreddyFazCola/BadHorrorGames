# Web Rush — Spider-Man Swinging Prototype

A from-scratch, browser-based Spider-Man web-swinging prototype: a procedurally
generated city, fixed-timestep rope physics, wall crawling, and thugs that
fight back. Plain ES modules and [three.js](https://threejs.org/) — no build
step required to run it.

## Run it

```bash
cd spider-man-swinging
python3 -m http.server 8080
# then open http://localhost:8080
```

(three.js is vendored under `vendor/three/`, so this works fully offline.)

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
| `C` | Circle ○ | Dodge — time it to your spidey sense for a perfect dodge |
| `Shift` | L1 / L3 | Sprint |
| `Esc` | Options | Pause |

## The swing

Everything in `PlayerController` runs on a **fixed 120Hz timestep** accumulated
across frames, not on the raw frame delta. The rope constraint is therefore
framerate-independent (solving a pendulum once per *frame* makes the correction
size depend on refresh rate and jitters on a long frame), nothing tunnels
(~0.7m per step even at full speed), and a dropped frame can't launch you.

Core physics:

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
  arc underground and the "swing" just scrapes the pavement. The line is hauled
  to a usable length, and can't be wound in past a fraction of it.
- **Anchors go above the roofline**, never on the facade you're flying at — a
  web stuck to a wall ahead puts that building inside your own arc.
- **Directional pump.** Holding forward thrusts along the direction you're
  *facing*, projected onto the plane the taut rope allows. Pushing along
  current velocity instead feeds a conical orbit: measured, 56 m/s of speed
  and 3 m/s of actual progress across the city.

What makes it feel like the console games specifically:

- **The web leaves the hand**, not the chest, and the reaching arm tracks the
  live anchor as the arc carries you under and past it. Hands alternate between
  swings. A rope from the middle of the torso reads as a tether; one from the
  glove reads as a web-shooter.
- **Perfect release.** Letting go (jump) while moving fast and close to
  horizontal keeps everything and launches — a speed multiplier plus extra
  lift, with a HUD flash. Let go while still falling and you just drop. That
  one timing decision is the skill the whole traversal loop is built around.
- **Dive.** Hold back in the air to tuck: steeper, faster, lower drag, with its
  own streamlined pose, then convert the speed into the next swing.
- **Momentum is never scrubbed.** Air control can only *add* speed along the
  direction you push, never reduce what you have. The obvious version —
  accelerate then clamp horizontal speed — quietly destroyed the traversal
  game: launching out of a swing at 52 m/s and holding forward clamped you
  straight back to 22, so a perfectly timed release ended *slower* than a lazy
  one.
- **Camera** pulls back, widens its FOV, rolls into the arc, shakes a little at
  speed, and leads toward where you're actually travelling rather than where
  you're aiming.

Street width matters as much as any of it: at the original 42m grid the avenues
were ~18m across, narrower than one swing arc, so every attach ended in a
facade. The 84m grid took chained traversal from **50m to ~420m per 15
seconds**, averaging ~28 m/s with peaks around 68.

## Wall crawling

Fly into a facade (or drift into one slowly) and you stick to it. `City.wallProbe()`
finds the nearest vertical face within reach and returns its outward normal,
the contact point and the building's roof height; `PlayerController`'s `wall`
state then holds you against that face with gravity switched off. `W`/`S` climb,
`A`/`D` crawl sideways, `Space` kicks you off and away, and climbing to within
a margin of the roofline **auto-mantles** you onto the roof rather than leaving
you stuck at the lip. Crawl off the side of a face and you drop.

Sticking is deliberate rather than automatic: a fast shallow pass slides by
(ordinary collision handles it), while flying *at* a wall or drifting into one
below ~12 m/s grabs it. Catching every facade you stream past at 40 m/s would
interrupt traversal constantly.

The pose is a splayed crawl flattened against the wall — body pitched into the
facade, limbs wide, head up — with a slow diagonal crawl cycle while moving. A
standing pose stuck to a wall reads as a decal.

## Crime system

`CrimeSystem` spawns a red beacon plus a thug (`Enemy.js`) on a rooftop or
street, up to 3 at a time. Thugs run idle → approach → telegraph → attack →
recover. The telegraph is a visible wind-up and a fair warning; punching (`E`)
interrupts any state, and three hits takes one down.

**Spidey sense** surfaces the nearest telegraphing thug as a screen-edge
vignette, an arrow pointing at the danger, and a rumble pulse. **Dodging** (`C`)
inside that window is a *perfect dodge* — longer i-frames and a HUD flash.
Running out of health ends the run on a game-over screen with a retry.

## Animation

The model ships with no animation clips, so every pose is driven by rotating
named rig bones each frame. The rig has full arm chains (clavicle → upperarm →
**lowerarm** → hand) and a neck; driving only the shoulder leaves arms
ruler-straight, which reads as a mannequin. Elbows are driven in every state —
runners pump bent arms, punches cock the elbow and snap it through on impact.

Stand perfectly still for ~5.5s and Spider-Man pulls out a **Rubik's cube** and
works on it, blending out the moment you move.

## Gamepad & DualSense

Any standard-mapping gamepad works. A DualSense additionally gets R2 feedback
that ramps with rope tension, via two very different tiers:

- **Gamepad API** (automatic): `dual-rumble`, plus the experimental
  `trigger-rumble` effect — vibration localized to the trigger motor, **not**
  real resistance.
- **WebHID** (opt-in button on the Controls screen): `DualSenseHID.js` writes
  the raw HID output report, which does include real adaptive-trigger
  resistance. Works wired or over an OS-level Bluetooth pairing; the two
  transports need different framing (report `0x02` vs `0x31` with a trailing
  CRC32), detected on connect.

Raw `navigator.bluetooth` can't do this at all — Bluetooth's HID-over-GATT
service is on the [Web Bluetooth blocklist](https://github.com/WebBluetoothCG/registries/blob/master/gatt_blocklist.txt).

**Unverified against real hardware** — there's no controller in the environment
this was built in. The Bluetooth framing comes from the Linux kernel's
`hid-playstation.c`; the effect encodings come from community
reverse-engineering. That's why the Controls screen ships a resistance sweep
test and an encoding cycler: if one encoding does nothing on your controller,
try the others.

## Project layout

```
index.html               menu/HUD markup
src/City.js              procedural streamed city, collision, wall probe, spawn points
src/Player.js            model loading, runtime colouring, all bone animation
src/Enemy.js             thug NPC state machine
src/modelLoader.js       shared model fetch/decode
src/PlayerController.js  fixed-step physics, swing, wall crawl, dive, zip, combat, camera
src/CrimeSystem.js       crime spawning, spidey sense, aim-assist
src/InputManager.js      keyboard/mouse + gamepad + pointer lock
src/DualSenseHID.js      WebHID rumble + adaptive-trigger resistance
src/Game.js              renderer/scene wiring, main loop, mode state
src/main.js              DOM/menu/HUD wiring
assets/models/           player model as chunked base64 text
vendor/three/            vendored three.js (MIT)
```

## Assets

The player model is ["Spiderman Brand New Day"](https://sketchfab.com/3d-models/spiderman-brand-new-day-ef54026773e14cffad16359fd771c5f8)
by [mpolo0604](https://sketchfab.com/mpolo0604), licensed
[CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/). It ships as geometry +
skeleton only; its ~18MB of textures were stripped, and the suit is coloured at
runtime from the mesh's own material names plus a canvas-drawn web pattern.

> This work is based on "Spiderman Brand New Day" by mpolo0604, licensed under
> CC-BY-4.0. The character is Marvel's IP; this asset is included for this
> prototype only, not for redistribution or commercial use.

## Known limitations

- Building collision is a circle-vs-AABB push-out, not a capsule sweep.
- Wall crawling only handles the four vertical faces of a box — no ceilings, no
  rounded or sloped geometry, and corners are a hard switch between faces.
- One enemy type, one attack, no ranged combat, no multi-thug coordination.
- No web-zip-to-point chaining or air tricks.
- DualSense output is unverified against hardware (see above).
