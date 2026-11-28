# Handoff

Read this first if you're a new session picking up this project.

## What this is

**Web Rush** — a Spider-Man web-swinging game. Two builds exist side by side:

- `spider-man-swinging/` — the original browser build (three.js, no build step).
  Complete, working, and **played and measured**. Every physics number in the
  project was tuned here against real measurements.
- `godot-web-rush/` — a Godot 4 remake of it. **Never executed.**

Branch: `claude/spider-man-game-swinging-kr9hmb`. Don't push anywhere else.

## The first job

Open `godot-web-rush/project.godot` in Godot 4.3+, press Play, and fix what
comes out of the Output panel. The project was authored entirely as text in a
cloud container where running Godot was blocked, so it has never been through
the engine's parser. Everything else is downstream of this.

It has been linted hard (no tabs, consistent 4-space indentation, no
JavaScript syntax, every cross-script call resolves to a defined method), so
expect API mismatches rather than structural problems.

## What not to redo

`README.md` documents the physics in detail. The short version: these were
real bugs, found by measurement, and they are easy to reintroduce by
"simplifying" the code.

- The rope constraint cancels **only outward** radial velocity. A rope pulls,
  never pushes.
- Pumping thrusts along the direction you **face**, projected onto the rope's
  tangent plane. Pushing along current velocity gives a conical orbit: 56 m/s
  of speed and 3 m/s of actual progress.
- Air control may only **add** speed along the wish direction. Accelerate-then-
  clamp destroyed the traversal game — a perfect release ended slower than a
  lazy one.
- Rope length is clamped so the bottom of the arc clears the ground, and
  anchors go **above the roofline**, never on a facade ahead.
- The 84 m street grid is load-bearing. At 42 m the avenues were narrower than
  one swing arc. Widening it took traversal from 50 m to ~420 m per 15 s.
- Movement is hand-integrated, not `CharacterBody3D`. `move_and_slide` would
  substitute its own collision response for the one these numbers were tuned
  against.

## Gotchas

- **Euler order.** Godot composes Euler angles in YXZ; Three.js uses XYZ. All
  bone poses call `Basis.from_euler(..., EULER_ORDER_XYZ)` explicitly. If a
  limb rotates about the wrong axis, set `DEBUG_BONE` on the `PlayerRig` node
  to a key of `BONE_NAMES` — it freezes every other bone and sweeps that joint
  through each axis in turn.
- Rooftop props and street lamps are **decoration only** — collision is still
  one box per building, so you can walk through a water tower.
- No adaptive-trigger support. Rumble works; the DualSense's trigger
  resistance needs a GDExtension wrapping hidapi. The rope tension that drove
  it in the browser build is still computed and exposed as
  `InputManager.trigger_tension`.
- Input is read off the hardware directly, not through `InputMap`, so there is
  no remapping UI.

## Where the user wants to go

1. Get it running. Nothing else is real until this is done.
2. Replace the hand-written bone angles with real animation. The rig has no
   clips in the source model, so every pose is procedural. Two routes: author
   clips in Blender and export (Blender is installed on the user's machine as
   a Claude desktop extension — it is **not** reachable from a cloud session),
   or write glTF animation channels into `assets/models/spiderman.glb`
   directly. Either way the target is `AnimationTree` + `SkeletonIK3D`, which
   is the strongest reason this project moved to Godot at all.
3. Keep polishing the look. Glow, SSAO, ACES tonemapping, fog, a procedural
   sky and a radial speed blur are already in.

## Note on the environment

If you are running in a cloud container you cannot reach the user's computer,
their Blender install, or their desktop extensions — and you probably cannot
run Godot either. Say so plainly rather than guessing at results. A session
running on the user's own machine can do all of it.
