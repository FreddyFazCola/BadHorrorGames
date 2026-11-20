extends Node3D
class_name PlayerController

# ---------------------------------------------------------------------------
# Physics model
#
# Movement is integrated by hand in _physics_process rather than through
# CharacterBody3D. The whole feel of this game lives in a handful of numbers
# that were measured and tuned against a fixed 120Hz step, and move_and_slide
# would quietly substitute its own collision response for the one those numbers
# were tuned against. Collision is a circle-vs-AABB push-out against the city's
# own box list, which at 120Hz is more than enough: the player covers ~0.7m per
# step even at full speed, far smaller than any building, so nothing tunnels.
#
# project.godot pins physics_ticks_per_second to 120, so `delta` here is
# exactly 1/120 on every call. The browser build needed an accumulator to get
# that; Godot gives it for free.
#
# Drag is quadratic, applied semi-implicitly (v /= 1 + k|v|h), which is
# unconditionally stable and gives a real terminal velocity instead of a hard
# clamp: ~55 m/s in free fall, ~65 on a line, ~78 in a dive.
# ---------------------------------------------------------------------------

signal died
signal perfect_dodge
signal perfect_release
signal landed(fall_speed: float)

const GRAVITY := -34.0
const AIR_DRAG := 0.011
const SWING_DRAG := 0.008
const DIVE_DRAG := 0.009   # a dive is a deliberately streamlined shape (~78 m/s terminal)

const RUN_ACCEL := 55.0
const RUN_MAX_SPEED := 9.0
const SPRINT_MAX_SPEED := 15.0
const GROUND_FRICTION := 12.0
const AIR_ACCEL := 16.0
const AIR_MAX_SPEED := 22.0
const JUMP_SPEED := 12.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const LANDING_SNAP_TOLERANCE := 3.0
const PLAYER_RADIUS := 0.4
const PLAYER_EYE := 1.3

const SWING_MIN_LEN := 12.0
const SWING_MAX_LEN := 95.0
const REEL_SPEED := 14.0
const REEL_MOMENTUM_CAP := 0.35
const SWING_LATERAL_ACCEL := 46.0   # steering authority - the arc should bend when you lean on it
const PUMP_ACCEL := 18.0
const SWING_RELEASE_BOOST := 9.0
const ATTACH_TANGENT_BOOST := 9.0
const ATTACH_LAUNCH_BOOST := 15.0
const ATTACH_LAUNCH_LIFT := 7.0
const WEB_MAX_DISTANCE := 150.0
const WEB_VIRTUAL_DISTANCE := 55.0
const ANCHOR_PREFERRED_RISE := 52.0
const ANCHOR_MIN_RISE := 24.0
const ANCHOR_ROOF_CLEARANCE := 8.0
const ANCHOR_ROOF_INSET := 6.0
const AUTO_REEL_CLEARANCE := 7.0
const AUTO_REEL_RATE := 1.2
const SWING_GROUND_CLEARANCE := 6.0
const ROPE_HAUL_RATE := 16.0
const REEL_FLOOR_FRACTION := 0.6
const CHAIN_WINDOW := 0.45
const CHAIN_SPEED_KEEP := 1.04

# Releasing at the right moment is the skill the whole swing is built around in
# Insomniac's games: let go at the flat, fast part of the arc and you keep
# everything and launch; let go while still falling and you just drop.
const PERFECT_RELEASE_MIN_SPEED := 26.0
const PERFECT_RELEASE_FLATNESS := 0.86   # horizontal share of the velocity
const PERFECT_RELEASE_GAIN := 1.14
const PERFECT_RELEASE_LIFT := 5.0

const DIVE_ACCEL := 22.0
const DIVE_MIN_HEIGHT := 6.0

const WALL_REACH := 0.9
const WALL_CLIMB_SPEED := 6.5
const WALL_STRAFE_SPEED := 5.5
const WALL_JUMP_OUT := 11.0
const WALL_JUMP_UP := 11.0
const WALL_STICK_COOLDOWN := 0.35
const WALL_STICK_SLOW_SPEED := 12.0
const WALL_MANTLE_MARGIN := 0.6

const PUNCH_DAMAGE := 1
const PUNCH_DURATION := 0.3

const PLAYER_MAX_HEALTH := 100.0
const DAMAGE_INVULN := 0.9
const HURT_ANIM_TIME := 0.45

const DODGE_DURATION := 0.4
const DODGE_SPEED := 17.0
const DODGE_HOP := 3.2
const DODGE_COOLDOWN := 0.55
const DODGE_INVULN := 0.45
const PERFECT_DODGE_INVULN := 0.8
const PERFECT_DODGE_RADIUS := 7.0

const ZIP_MAX_DISTANCE := 60.0
const ZIP_DURATION := 0.32
const ZIP_ARRIVE_OFFSET := 2.2
const ZIP_MIN_DISTANCE := 3.0
const ZIP_COOLDOWN := 0.15
const ZIP_EXIT_SPEED := 18.0

const CAM_DISTANCE := 8.5
const CAM_DISTANCE_SPEED_BOOST := 3.5
const CAM_HEIGHT := 1.5
const BASE_FOV := 62.0
const MAX_FOV_BOOST := 22.0
const FOV_SPEED_REF := 45.0
const AIM_FOV_ADJUST := -16.0
const AIM_MOVE_SCALE := 0.6
const MAX_CAM_ROLL := 0.42
const CAM_LEAD := 0.1
const CAM_SHAKE := 0.1
const SPEED_REF := 85.0

var city: City
var input: InputManager
var rig: Node3D            # PlayerRig
var crimes: Node           # CrimeSystem, optional
var camera: Camera3D
var web_line: MeshInstance3D
var anchor_marker: MeshInstance3D

var pos := Vector3(0, 1, 18)
var vel := Vector3.ZERO
var state := "air"         # ground | air | swing | zip | wall

var swing_anchor := Vector3.ZERO
var swing_length := 0.0
var rope_tension := 0.0
var swing_hand := "right"
var _swing_attach_elapsed := 0.0
var _time_since_release := 1e9
var _web_latched := false

var wall_normal := Vector3(0, 0, 1)
var wall_top := 0.0
var on_wall := false
var _wall_cooldown := 0.0

var diving := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _punch_time := 0.0
var _hurt_time := 0.0
var _invuln_time := 0.0
var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _zip_elapsed := 0.0
var _zip_cooldown := 0.0
var _zip_start := Vector3.ZERO
var _zip_target := Vector3.ZERO
var _web_anchor_point := Vector3.ZERO
var _web_mesh: ImmediateMesh = null

var health := PLAYER_MAX_HEALTH
var max_health := PLAYER_MAX_HEALTH
var dead := false

var aiming := false
var aim_target: Variant = null      # {"point": Vector3, "locked": bool} or null

var _cam_roll := 0.0
var _cam_shake := 0.0
var _cam_initialised := false


func look_dir() -> Vector3:
    return Vector3(0, 0, -1).rotated(Vector3.RIGHT, input.pitch).rotated(Vector3.UP, input.yaw)


func _flat_forward() -> Vector3:
    return Vector3(0, 0, -1).rotated(Vector3.UP, input.yaw)


func _flat_right() -> Vector3:
    return Vector3(1, 0, 0).rotated(Vector3.UP, input.yaw)


func reset_to(p: Vector3) -> void:
    pos = p
    vel = Vector3.ZERO
    state = "air"
    web_line.visible = false
    anchor_marker.visible = false
    health = max_health
    dead = false
    rope_tension = 0.0
    on_wall = false
    diving = false
    _invuln_time = 0.0
    _hurt_time = 0.0
    _punch_time = 0.0
    _dodge_time = 0.0
    _dodge_cooldown = 0.0
    _zip_cooldown = 0.0
    _wall_cooldown = 0.0
    _coyote = 0.0
    _jump_buffer = 0.0
    _time_since_release = 1e9
    _web_latched = false
    aiming = false
    aim_target = null
    _cam_initialised = false


# ---------------------------------------------------------------------------
# Per-frame: input, actions, presentation.
# ---------------------------------------------------------------------------
func frame_update(dt: float) -> void:
    dt = minf(dt, 0.1)
    input.poll_gamepad(dt)

    _punch_time = maxf(0.0, _punch_time - dt)
    _hurt_time = maxf(0.0, _hurt_time - dt)
    _invuln_time = maxf(0.0, _invuln_time - dt)
    _dodge_time = maxf(0.0, _dodge_time - dt)
    _dodge_cooldown = maxf(0.0, _dodge_cooldown - dt)
    _zip_cooldown = maxf(0.0, _zip_cooldown - dt)
    _wall_cooldown = maxf(0.0, _wall_cooldown - dt)
    _coyote = maxf(0.0, _coyote - dt)
    _jump_buffer = maxf(0.0, _jump_buffer - dt)
    _time_since_release += dt

    if dead:
        _update_dead(dt)
        return

    if input.consume_jump():
        _jump_buffer = JUMP_BUFFER
    if input.consume_dodge():
        _try_dodge()
    if input.consume_zip():
        _try_web_zip()
    if input.consume_punch():
        _try_punch()

    aiming = input.is_aim_down() and state != "swing" and state != "zip"
    aim_target = _find_aim_target() if aiming else null

    var want_web := input.is_web_down()
    if not want_web:
        _web_latched = false
    if state != "zip":
        if want_web and not _web_latched and state != "swing":
            _try_shoot_web()
        elif not want_web and state == "swing":
            _release(false)

    # Jumping off a line releases it with a boost. The latch matters: the web
    # button is normally still held at that moment, and without it the next
    # frame re-attaches a fresh line whose constraint eats the boost you just
    # launched with.
    if state == "swing" and _jump_buffer > 0.0:
        _jump_buffer = 0.0
        _release(true)
        _web_latched = true

    # Diving: hold back in the air to tuck and trade height for speed.
    diving = state == "air" \
        and input.movement_vector().y < -0.5 \
        and pos.y - city.ground_height_at(pos.x, pos.z) > DIVE_MIN_HEIGHT

    on_wall = state == "wall"

    if state != "swing":
        rope_tension = 0.0
    input.trigger_tension = rope_tension

    if state == "ground":
        _coyote = COYOTE_TIME

    rig.set_transform_for(pos, _model_yaw())
    rig.update_tilt(dt, state, vel, input.yaw)
    rig.update_animation(dt, {
        "state": state,
        "ground_speed": Vector2(vel.x, vel.z).length(),
        "vertical_velocity": vel.y,
        "speed": vel.length(),
        "punching": _punch_time > 0.0,
        "dodging": _dodge_time > 0.0,
        "hurt": _hurt_time > 0.0,
        "diving": diving,
        "climbing": vel.length() if state == "wall" else 0.0,
        # The reaching arm tracks the live anchor, which is most of what makes
        # a swing read as hanging from a line rather than floating beneath one.
        "reach_target": swing_anchor if state == "swing" else null,
        "reach_hand": swing_hand,
    })

    # After the animation, so the line leaves the hand where it actually is
    # this frame. Built before it, the hand position is a frame stale and the
    # web visibly hangs off a point beside the glove (measured: 0.24m off).
    if state == "swing" or state == "zip":
        _update_web_line()


# On a wall the model faces into the facade instead of along the camera.
func _model_yaw() -> float:
    if state != "wall":
        return input.yaw
    return atan2(-wall_normal.x, -wall_normal.z)


# The line is drawn from the actual hand bone, not the chest. It is a small
# thing that does a lot of work: a rope emerging from the middle of the torso
# reads as a tether, one leaving the hand reads as a web-shooter.
func _update_web_line() -> void:
    var hand: Variant = rig.hand_world_position(swing_hand)
    var from: Vector3 = hand if hand != null else pos + Vector3.UP * PLAYER_EYE
    var to: Vector3 = _web_anchor_point if state == "zip" else swing_anchor

    # One ImmediateMesh, cleared and refilled. Allocating a fresh one every
    # frame would churn a mesh resource 60+ times a second for two vertices.
    if _web_mesh == null:
        _web_mesh = ImmediateMesh.new()
        web_line.mesh = _web_mesh
    _web_mesh.clear_surfaces()
    _web_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    _web_mesh.surface_add_vertex(web_line.to_local(from))
    _web_mesh.surface_add_vertex(web_line.to_local(to))
    _web_mesh.surface_end()


func _update_dead(dt: float) -> void:
    input.clear_presses()
    vel.x *= maxf(0.0, 1.0 - dt * 4.0)
    vel.z *= maxf(0.0, 1.0 - dt * 4.0)
    vel.y += GRAVITY * dt
    pos += vel * dt
    var floor_y := city.ground_height_at(pos.x, pos.z)
    if pos.y <= floor_y:
        pos.y = floor_y
        vel = Vector3.ZERO
    rig.set_transform_for(pos, input.yaw)
    rig.update_animation(dt, {
        "state": "air",
        "ground_speed": 0.0,
        "vertical_velocity": vel.y,
        "speed": 0.0,
        "hurt": true,
    })


# ---------------------------------------------------------------------------
# One fixed physics step. delta is 1/120.
# ---------------------------------------------------------------------------
func _physics_process(h: float) -> void:
    if dead or city == null:
        return

    if state == "zip":
        _step_zip(h)
    elif state == "swing":
        _step_swing(h)
    elif state == "wall":
        _step_wall(h)
    else:
        _step_ground_air(h)

    var floor_y := city.ground_height_at(pos.x, pos.z)
    if pos.y < floor_y:
        pos.y = floor_y
        if vel.y < 0.0:
            vel.y = 0.0
        if state == "swing":
            _release(false)
        if state != "zip":
            state = "ground"


func _apply_drag(h: float, k: float) -> void:
    var speed := vel.length()
    if speed < 1e-4:
        return
    vel /= 1.0 + k * speed * h


# Applies the city's push-out and removes the part of the velocity driving into
# the wall. Without that second half the mover is repositioned every step but
# keeps its full inward speed, grinding along the facade at 50 m/s while making
# no progress at all.
func _collide_horizontal(ref_y: float, bounce: float = 1.0) -> bool:
    var res := city.resolve_horizontal_collision(pos, PLAYER_RADIUS, ref_y)
    pos = res["position"]
    var push: Vector3 = res["push"]
    var push_len := Vector2(push.x, push.z).length()
    if push_len < 1e-6:
        return false
    var n := Vector3(push.x / push_len, 0.0, push.z / push_len)
    var into := vel.x * n.x + vel.z * n.z
    if into < 0.0:
        vel.x -= n.x * into
        vel.z -= n.z * into
        vel.x *= bounce
        vel.z *= bounce
    return true


func _step_swing(h: float) -> void:
    _swing_attach_elapsed += h
    var mv := input.movement_vector()
    var strafe := mv.x
    var pump := mv.y
    var old_len := swing_length
    var ground_y := city.ground_height_at(pos.x, pos.z)

    # A pendulum's lowest point is one rope-length below its anchor, so a rope
    # longer than the anchor is high puts the bottom of the arc underground -
    # all such a "swing" can do is scrape the pavement. The usable range is
    # bounded at both ends: arc_ceiling is the longest rope whose arc clears
    # the deck, reel_floor stops you winding in until you're whipping a tight
    # circle around the anchor instead of swinging.
    var arc_ceiling := maxf(SWING_MIN_LEN, swing_anchor.y - ground_y - SWING_GROUND_CLEARANCE)
    var reel_floor := maxf(SWING_MIN_LEN, arc_ceiling * REEL_FLOOR_FRACTION)

    var new_len := clampf(old_len - pump * REEL_SPEED * h, reel_floor, SWING_MAX_LEN)
    if new_len > arc_ceiling:
        new_len = maxf(arc_ceiling, new_len - ROPE_HAUL_RATE * h)
    var clearance := pos.y - ground_y
    if _swing_attach_elapsed > 0.35 and clearance < AUTO_REEL_CLEARANCE:
        new_len = maxf(reel_floor, new_len - (AUTO_REEL_CLEARANCE - clearance) * AUTO_REEL_RATE * h)
    swing_length = new_len

    # Shortening the line conserves angular momentum, so tangential speed rises
    # as the radius drops - reeling in at the bottom of an arc is a real speed
    # technique. Capped, or it explodes (measured: 130 m/s in 1.5s uncapped).
    if new_len < old_len - 1e-6:
        var to_player := pos - swing_anchor
        var r := to_player.length()
        if r > 1e-4:
            var n := to_player / r
            var radial := vel.dot(n)
            var tangential := vel - n * radial
            var gain := minf(old_len / new_len, 1.0 + REEL_MOMENTUM_CAP * h)
            vel = tangential * gain + n * radial

    vel.y += GRAVITY * h

    if strafe != 0.0:
        vel += _flat_right() * (strafe * SWING_LATERAL_ACCEL * h)

    # Pumping pushes along the direction you're *facing*, projected onto the
    # plane the taut rope allows. Pushing along current velocity instead - the
    # obvious reading of "pump the swing" - feeds a conical orbit: energy in
    # tangentially, drag out, equilibrium a fast circle around the anchor.
    # Measured, that was 56 m/s of speed and 3 m/s of progress across the city.
    # Directional thrust spends the same energy on getting somewhere.
    if pump > 0.0:
        var to_player_n := pos - swing_anchor
        var l := to_player_n.length()
        if l > 1e-4:
            to_player_n /= l
            var fwd := _flat_forward()
            var thrust := fwd - to_player_n * fwd.dot(to_player_n)
            if thrust.length_squared() > 1e-6:
                vel += thrust.normalized() * (pump * PUMP_ACCEL * h)

    _apply_drag(h, SWING_DRAG)
    pos += vel * h

    var to_p := pos - swing_anchor
    var dist := to_p.length()
    rope_tension = clampf(dist / swing_length, 0.0, 1.0)
    if dist > swing_length and dist > 1e-4:
        var n := to_p / dist                    # unit, anchor -> player
        pos = swing_anchor + n * swing_length
        # Cancel only the component pulling *away* from the anchor: a rope can
        # pull, never push, so inward motion is untouched. This is the correct
        # inelastic response, and it's what makes the arc come out clean
        # instead of buzzing the way a position-only clamp does.
        var radial := vel.dot(n)
        if radial > 0.0:
            vel -= n * radial

    if pos.y < ground_y:
        pos.y = ground_y
        if vel.y < 0.0:
            vel.y = 0.0
    _collide_horizontal(pos.y, 0.94)


func _step_ground_air(h: float) -> void:
    var fwd := _flat_forward()
    var rgt := _flat_right()
    var mv := input.movement_vector()
    var want := fwd * mv.y + rgt * mv.x
    var grounded := state == "ground"

    if grounded:
        var max_speed := (SPRINT_MAX_SPEED if input.is_sprint_down() else RUN_MAX_SPEED) \
            * (AIM_MOVE_SCALE if aiming else 1.0)
        if want.length_squared() > 0.0:
            want = want.normalized()
            vel.x += want.x * RUN_ACCEL * h
            vel.z += want.z * RUN_ACCEL * h
        else:
            var speed := Vector2(vel.x, vel.z).length()
            if speed > 1e-4:
                var scale := maxf(0.0, speed - GROUND_FRICTION * h) / speed
                vel.x *= scale
                vel.z *= scale
        var flat := Vector2(vel.x, vel.z).length()
        if flat > max_speed:
            vel.x *= max_speed / flat
            vel.z *= max_speed / flat
        vel.y = 0.0
    else:
        if diving:
            # Tuck and drop: accelerate downward and along your aim, cut drag.
            vel.y -= DIVE_ACCEL * h
            vel += fwd * (DIVE_ACCEL * 0.45 * h)
        elif want.length_squared() > 0.0:
            # Air control that can only ever *add* speed in the direction
            # you're pushing, never scrub what you already have. The obvious
            # version - accelerate, then clamp horizontal speed to a maximum -
            # silently destroys the whole traversal game: launching out of a
            # swing at 52 m/s and holding forward clamped you straight back to
            # 22, so a perfectly timed release ended *slower* than a lazy one.
            # Projecting current velocity onto the wish direction and only
            # topping it up to the cap keeps momentum intact while still
            # letting you steer. After the fix the same release read 52 -> 60.
            want = want.normalized()
            var along := vel.x * want.x + vel.z * want.z
            var add := minf(AIR_ACCEL * h, maxf(0.0, AIR_MAX_SPEED - along))
            vel.x += want.x * add
            vel.z += want.z * add
        vel.y += GRAVITY * h
        _apply_drag(h, DIVE_DRAG if diving else AIR_DRAG)

    # Coyote time and jump buffering: pressing just after leaving a ledge or
    # just before landing both still work, which is most of what separates a
    # platformer that feels responsive from one that feels like it's ignoring
    # you.
    if _jump_buffer > 0.0 and (grounded or _coyote > 0.0):
        _jump_buffer = 0.0
        _coyote = 0.0
        vel.y = JUMP_SPEED
        state = "air"

    var pre_move_y := pos.y
    pos += vel * h
    _collide_horizontal(pre_move_y)

    # Only treat a rooftop as landable if it was already within a normal
    # landing's reach before this step - otherwise flying past a building's
    # edge from below snaps you onto its roof. If a roof is too far above,
    # street level is the floor instead, so a player at the foot of a tower
    # doesn't free-fall forever.
    var roof_y := city.ground_height_at(pos.x, pos.z)
    var landing_y := roof_y if roof_y - pre_move_y <= LANDING_SNAP_TOLERANCE else 0.0
    if pos.y <= landing_y:
        if state != "ground" and vel.y < -8.0:
            var fall_speed := -vel.y
            landed.emit(fall_speed)
            var scrub := clampf(1.0 - (fall_speed - 8.0) / 60.0, 0.45, 1.0)
            vel.x *= scrub
            vel.z *= scrub
        pos.y = landing_y
        vel.y = 0.0
        state = "ground"
        _coyote = COYOTE_TIME
    else:
        state = "air"
        if _wall_cooldown <= 0.0:
            _try_wall_stick()


# ---------------------------------------------------------------------------
# Wall crawling
# ---------------------------------------------------------------------------
func _try_wall_stick() -> bool:
    var probe := city.wall_probe(pos.x, pos.y, pos.z, WALL_REACH + PLAYER_RADIUS)
    if probe.is_empty():
        return false

    # Stick on a deliberate approach, not on any graze. Catching every facade
    # you stream past at 40 m/s would interrupt traversal constantly, so a fast
    # shallow pass slides by (ordinary collision handles it) while flying *at* a
    # wall, or drifting into one slowly, grabs it.
    var n: Vector3 = probe["normal"]
    var into := vel.x * n.x + vel.z * n.z
    var approach := -into                      # positive means heading into the face
    var speed := vel.length()
    var directness := approach / speed if speed > 1e-3 else 1.0
    if not (speed < WALL_STICK_SLOW_SPEED or (approach > 2.0 and directness > 0.3)):
        return false

    wall_normal = Vector3(n.x, 0.0, n.z)
    var point: Vector3 = probe["point"]
    pos.x = point.x + n.x * (PLAYER_RADIUS + 0.05)
    pos.z = point.z + n.z * (PLAYER_RADIUS + 0.05)
    vel = Vector3.ZERO
    state = "wall"
    wall_top = probe["top"]
    input.rumble(0.25, 0.2, 60)
    return true


func _step_wall(h: float) -> void:
    var probe := city.wall_probe(pos.x, pos.y, pos.z, WALL_REACH + PLAYER_RADIUS + 0.4)
    if probe.is_empty():
        # Crawled off the edge of the face.
        state = "air"
        _wall_cooldown = WALL_STICK_COOLDOWN
        return
    var n: Vector3 = probe["normal"]
    wall_normal = Vector3(n.x, 0.0, n.z)
    wall_top = probe["top"]

    # Jump off: away from the wall and up.
    if _jump_buffer > 0.0:
        _jump_buffer = 0.0
        state = "air"
        _wall_cooldown = WALL_STICK_COOLDOWN
        vel = Vector3(wall_normal.x * WALL_JUMP_OUT, WALL_JUMP_UP, wall_normal.z * WALL_JUMP_OUT)
        input.rumble(0.3, 0.45, 90)
        return

    # Movement maps onto the wall plane: forward/back climbs, left/right crawls
    # sideways along the face.
    var mv := input.movement_vector()
    var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x)
    vel = Vector3(0.0, mv.y * WALL_CLIMB_SPEED, 0.0) + tangent * (mv.x * WALL_STRAFE_SPEED)
    pos += vel * h

    # Hold against the face, so rounding a corner or drifting doesn't peel off.
    var point: Vector3 = probe["point"]
    pos.x = point.x + wall_normal.x * (PLAYER_RADIUS + 0.05)
    pos.z = point.z + wall_normal.z * (PLAYER_RADIUS + 0.05)

    # Reaching the roofline pulls you over the top rather than leaving you
    # stuck at the lip, which is what any climb in any game does.
    if pos.y >= wall_top - WALL_MANTLE_MARGIN:
        pos.y = wall_top
        pos.x -= wall_normal.x * (PLAYER_RADIUS + 0.9)
        pos.z -= wall_normal.z * (PLAYER_RADIUS + 0.9)
        vel = Vector3.ZERO
        state = "ground"
        _wall_cooldown = WALL_STICK_COOLDOWN
        return
    if pos.y <= city.ground_height_at(pos.x, pos.z) + 0.05:
        state = "ground"
        _wall_cooldown = WALL_STICK_COOLDOWN


func _step_zip(h: float) -> void:
    _zip_elapsed += h
    var t := minf(1.0, _zip_elapsed / ZIP_DURATION)
    var eased := 1.0 - pow(1.0 - t, 3.0)
    pos = _zip_start.lerp(_zip_target, eased)
    _collide_horizontal(pos.y)
    if t >= 1.0:
        var dir := _zip_target - _zip_start
        vel = dir.normalized() * ZIP_EXIT_SPEED if dir.length_squared() > 1e-6 else Vector3.ZERO
        state = "air"
        web_line.visible = false
        _zip_cooldown = ZIP_COOLDOWN


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func _raycast_world(from: Vector3, dir: Vector3, distance: float) -> Dictionary:
    var space := get_world_3d().direct_space_state
    var params := PhysicsRayQueryParameters3D.create(from, from + dir * distance, City.WORLD_LAYER)
    return space.intersect_ray(params)


func _try_shoot_web() -> void:
    var hit := _raycast_world(camera.global_position, look_dir(), WEB_MAX_DISTANCE)

    # Anchor placement decides whether a swing travels or parks you against a
    # wall. A web stuck to the *face* of a building ahead puts that building
    # inside your own arc, so the swing drives you into it and stops you dead.
    # Real swinging happens in the open air of the street canyon, hanging from
    # points above the rooftops - so that's where the line goes.
    var anchor: Variant = null
    if not hit.is_empty():
        var point: Vector3 = hit["position"]
        var collider: Object = hit["collider"]
        var building_top: float = collider.get_meta("roof_height") \
            if collider != null and collider.has_meta("roof_height") else point.y
        var to_player := Vector3(pos.x - point.x, 0.0, pos.z - point.z)
        var inset := to_player.normalized() * ANCHOR_ROOF_INSET if to_player.length_squared() > 1e-6 else Vector3.ZERO
        anchor = Vector3(
            point.x + inset.x,
            maxf(building_top + ANCHOR_ROOF_CLEARANCE, pos.y + ANCHOR_MIN_RISE),
            point.z + inset.z)

    if anchor == null or (anchor as Vector3).y - pos.y < ANCHOR_MIN_RISE:
        var origin := pos + Vector3.UP * PLAYER_EYE
        var flat_aim := look_dir()
        flat_aim.y = 0.0
        var aim := flat_aim.normalized() if flat_aim.length_squared() > 1e-4 else _flat_forward()
        var a := origin + aim * WEB_VIRTUAL_DISTANCE
        a.y = maxf(pos.y + ANCHOR_PREFERRED_RISE, city.ground_height_at(a.x, a.z) + ANCHOR_ROOF_CLEARANCE)
        anchor = a

    var anchor_v: Vector3 = anchor
    var dist := anchor_v.distance_to(pos)
    if dist < SWING_MIN_LEN:
        return

    swing_anchor = anchor_v
    _swing_attach_elapsed = 0.0
    # Hands alternate, the way they do when you actually swing - two webs in a
    # row from the same hand reads as a machine, not a person.
    swing_hand = "left" if swing_hand == "right" else "right"
    # Rope starts at exactly the current distance; any shorter and the first
    # constraint solve yanks you closer, which reads as a teleport.
    swing_length = clampf(dist, SWING_MIN_LEN, SWING_MAX_LEN)
    state = "swing"
    web_line.visible = true
    anchor_marker.visible = true
    anchor_marker.global_position = anchor_v

    # Attach impulse: project existing velocity onto the plane perpendicular to
    # the rope (the only direction a taut line allows) and push along it, so a
    # swing snaps into its arc instead of sagging into the pendulum. A pendulum
    # started from rest at the bottom of its arc has no height to convert into
    # speed, so a standing attach gets a real leg-driven launch while a running
    # or falling one keeps its own momentum.
    var n := (anchor_v - pos).normalized()
    var radial := vel.dot(n)
    vel += n * -minf(0.0, radial)
    var tangent := vel - n * vel.dot(n)
    if tangent.length_squared() < 1.0:
        var fwd := _flat_forward()
        tangent = fwd - n * fwd.dot(n)
    var starting_slow := vel.length() < 8.0
    if tangent.length_squared() > 1e-6:
        vel += tangent.normalized() * (ATTACH_LAUNCH_BOOST if starting_slow else ATTACH_TANGENT_BOOST)
    if starting_slow:
        vel.y += ATTACH_LAUNCH_LIFT

    if _time_since_release < CHAIN_WINDOW:
        vel *= CHAIN_SPEED_KEEP
    input.rumble(0.2, 0.12, 70)


func _release(boost: bool) -> void:
    if state != "swing":
        return
    state = "air"
    web_line.visible = false
    anchor_marker.visible = false
    rope_tension = 0.0
    _time_since_release = 0.0

    if not boost:
        return

    # Timing reward. Let go at the flat, fast part of the arc and you keep
    # everything and launch; let go while still falling and you just drop.
    var speed := vel.length()
    var flatness := Vector2(vel.x, vel.z).length() / speed if speed > 1.0 else 0.0
    var perfect := speed > PERFECT_RELEASE_MIN_SPEED and flatness > PERFECT_RELEASE_FLATNESS and vel.y > -3.0
    if perfect:
        vel *= PERFECT_RELEASE_GAIN
        vel.y += SWING_RELEASE_BOOST + PERFECT_RELEASE_LIFT
        input.rumble(0.5, 0.7, 180)
        perfect_release.emit()
    else:
        vel.y += SWING_RELEASE_BOOST


func _find_aim_target() -> Variant:
    var hit := _raycast_world(camera.global_position, look_dir(), ZIP_MAX_DISTANCE)
    var point: Variant = hit["position"] if not hit.is_empty() else null
    var locked := false
    if crimes != null:
        var enemy: Variant = crimes.find_aim_target(camera.global_position, look_dir(), ZIP_MAX_DISTANCE)
        if enemy != null:
            point = enemy.global_position
            locked = true
    return {"point": point, "locked": locked} if point != null else null


func _try_web_zip() -> void:
    if state == "swing" or state == "zip" or _zip_cooldown > 0.0:
        return
    var t: Variant = aim_target if aim_target != null else _find_aim_target()
    if t == null:
        return
    var target: Vector3 = (t as Dictionary)["point"]

    var to_target := target - pos
    var dist := to_target.length()
    if dist < ZIP_MIN_DISTANCE:
        return

    var arrive := maxf(1.5, minf(dist, ZIP_MAX_DISTANCE) - ZIP_ARRIVE_OFFSET)
    _zip_start = pos
    _zip_target = pos + to_target.normalized() * arrive
    _web_anchor_point = target
    _zip_elapsed = 0.0
    state = "zip"
    web_line.visible = true
    anchor_marker.visible = false
    input.rumble(0.3, 0.5, 90)


func _try_punch() -> void:
    if crimes == null or state == "swing" or state == "zip":
        return
    _punch_time = PUNCH_DURATION
    var res: Dictionary = crimes.try_punch(pos, PUNCH_DAMAGE)
    if res.get("defeated", false):
        input.rumble(0.6, 1.0, 200)
    elif res.get("hit", false):
        input.rumble(0.35, 0.55, 90)


func _try_dodge() -> void:
    if dead or _dodge_cooldown > 0.0 or state == "swing" or state == "zip":
        return
    var mv := input.movement_vector()
    var dir := _flat_forward() * mv.y + _flat_right() * mv.x
    if dir.length_squared() < 0.01:
        dir = -_flat_forward()
    dir = dir.normalized()

    var perfect := crimes != null and crimes.is_danger_near(pos, PERFECT_DODGE_RADIUS)
    _dodge_time = DODGE_DURATION
    _dodge_cooldown = DODGE_COOLDOWN
    _invuln_time = maxf(_invuln_time, PERFECT_DODGE_INVULN if perfect else DODGE_INVULN)

    vel.x = dir.x * DODGE_SPEED
    vel.z = dir.z * DODGE_SPEED
    if state == "ground" or state == "wall":
        vel.y = DODGE_HOP
        state = "air"
        _wall_cooldown = WALL_STICK_COOLDOWN

    if perfect:
        input.rumble(0.7, 0.9, 220)
        perfect_dodge.emit()
    else:
        input.rumble(0.25, 0.35, 90)


func take_damage(amount: float) -> void:
    if amount <= 0.0 or _invuln_time > 0.0 or state == "zip" or dead:
        return
    health = maxf(0.0, health - amount)
    _invuln_time = DAMAGE_INVULN
    _hurt_time = HURT_ANIM_TIME
    input.rumble(0.5, 0.85, 160)
    if health <= 0.0:
        dead = true
        state = "air"
        web_line.visible = false
        anchor_marker.visible = false
        input.rumble(1.0, 1.0, 500)
        died.emit()


# ---------------------------------------------------------------------------
# Chase camera
# ---------------------------------------------------------------------------
func update_camera(dt: float) -> void:
    var speed := vel.length()
    var speed_ratio := clampf(speed / SPEED_REF, 0.0, 1.0)

    var target := pos + Vector3.UP * CAM_HEIGHT
    var dir := look_dir()
    var cam_distance := CAM_DISTANCE + speed_ratio * CAM_DISTANCE_SPEED_BOOST
    var desired := target - dir * cam_distance
    desired.y = maxf(desired.y, city.ground_height_at(desired.x, desired.z) + 1.2)

    var to_desired := desired - target
    var dist_to_desired := to_desired.length()
    if dist_to_desired > 0.001:
        var hit := _raycast_world(target, to_desired / dist_to_desired, dist_to_desired)
        if not hit.is_empty():
            var hit_dist := target.distance_to(hit["position"] as Vector3)
            desired = target + (to_desired / dist_to_desired) * maxf(1.5, hit_dist - 0.5)

    # A little camera shake at speed. Small enough to read as wind rather than
    # a rattle, and gated on speed so standing still is rock steady.
    _cam_shake = lerpf(_cam_shake, speed_ratio * CAM_SHAKE, 1.0 - exp(-6.0 * dt))
    if _cam_shake > 0.002:
        desired.x += (randf() - 0.5) * _cam_shake
        desired.y += (randf() - 0.5) * _cam_shake

    if not _cam_initialised:
        camera.global_position = desired
        _cam_initialised = true
    else:
        # Exponential smoothing written frame-rate independently, so the camera
        # lags by the same amount of *time* at any refresh rate.
        camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-10.0 * dt))

    var rgt := Vector3(dir.z, 0.0, -dir.x)
    var lateral := vel.dot(rgt)
    var roll_target := clampf(-lateral / SPEED_REF, -1.0, 1.0) * MAX_CAM_ROLL if state == "swing" else 0.0
    _cam_roll = lerpf(_cam_roll, roll_target, 1.0 - exp(-5.0 * dt))

    # Lead the shot slightly toward where you're actually travelling, not just
    # where you're aiming - at speed those diverge, and leading them sells the
    # sense of being carried by the arc.
    var look_at_point := target + dir * 4.0
    if speed > 1.0:
        look_at_point += vel * ((CAM_LEAD * speed_ratio) / maxf(1.0, speed / 20.0))
    var up := Vector3.UP.rotated(dir.normalized(), _cam_roll)
    if look_at_point.distance_to(camera.global_position) > 0.01:
        camera.look_at(look_at_point, up)

    var speed_factor := clampf(speed / FOV_SPEED_REF, 0.0, 1.0)
    var target_fov := BASE_FOV + speed_factor * MAX_FOV_BOOST + (AIM_FOV_ADJUST if aiming else 0.0)
    camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-4.0 * dt))
