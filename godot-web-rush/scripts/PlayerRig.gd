extends Node3D
class_name PlayerRig

# The source model ships with no animation clips, so every pose here is driven
# by rotating named rig bones each frame.
#
# Godot's Skeleton3D has no per-axis Euler accessor the way a Three.js bone
# does, so the pose is kept here as Euler angles per bone and converted once
# per frame. That is not just a convenience: the whole animation set was tuned
# as per-axis angles, and the lerp/blend helpers below need to read back the
# value they wrote last frame.
#
# Two conventions matter and are easy to get wrong:
#
#  1. Euler order. Three.js defaults to XYZ; Godot's Quaternion.from_euler()
#     uses YXZ. Composing the same three numbers in a different order gives a
#     different rotation, so Basis.from_euler(..., EULER_ORDER_XYZ) is used
#     explicitly to keep the tuned angles meaning what they meant.
#  2. Bone pose rotations are relative to each bone's rest pose, which is what
#     the browser build's angles were relative to as well (a glTF bind pose),
#     so the numbers transfer directly.
#
# The axis and sign each bone needs - which local axis swings a limb forward vs
# sideways, and which sign means which direction - was determined empirically
# per bone in the browser build, by rotating it in isolation and comparing
# world positions before and after; the rig documents neither. Godot's glTF
# importer should preserve those local bone bases, but if a limb comes out
# rotating about the wrong axis, that is the thing to check first: the angles
# are all in one place here and DEBUG_BONE below isolates a single joint.

const MODEL: PackedScene = preload("res://assets/models/spiderman.glb")

const BONE_NAMES := {
    "thighL": "thigh_l_054",
    "thighR": "thigh_r_068",
    "calfL": "calf_l_055",
    "calfR": "calf_r_069",
    "ballL": "ball_l_057",
    "ballR": "ball_r_072",
    "upperArmL": "upperarm_l_0126",
    "upperArmR": "upperarm_r_0171",
    "lowerArmL": "lowerarm_l_0127",
    "lowerArmR": "lowerarm_r_0172",
    "handL": "hand_l_0128",
    "handR": "hand_r_0173",
    "clavicleL": "clavicle_l_0125",
    "clavicleR": "clavicle_r_0170",
    "neck": "neck_01_0142",
    "spine": "spine_03_0109",
    "head": "head_0164",
}

# Bind pose is a T-pose; this brings each upper arm down to a relaxed rest.
# Without it the model stands there with its arms straight out, which is the
# single most obvious "this is unfinished" tell a character can have.
const ARM_REST_Y := 1.3
# Elbows are never locked out on a real body, even at rest. On both arms,
# negative local Z folds the forearm up and forward.
const ELBOW_REST := -0.28

const SPRINT_REF_SPEED := 9.0
const PUNCH_ANIM_DURATION := 0.3
const DODGE_ANIM_DURATION := 0.4
const HURT_ANIM_DURATION := 0.45
const IDLE_FIDGET_DELAY := 5.5
const IDLE_FIDGET_BLEND := 0.7

# Set to a key of BONE_NAMES to freeze every other bone and sweep this one, for
# checking which local axis does what. Empty disables it.
@export var DEBUG_BONE := ""

var pivot: Node3D
var model: Node3D
var skeleton: Skeleton3D

var _bone_idx: Dictionary = {}     # key -> bone index
var _angles: Dictionary = {}       # key -> Vector3 of Euler angles
var _cube: Node3D

var _run_phase := 0.0
var _idle_phase := 0.0
var _climb_phase := 0.0
var _punch_phase := 1.0
var _dodge_phase := 1.0
var _hurt_phase := 1.0
var _idle_still_time := 0.0
var _fidget_amount := 0.0
var _cube_solve_phase := 0.0
var _current_tilt := Quaternion.IDENTITY
var _rest_feet_y := 0.0
var _debug_phase := 0.0


func _ready() -> void:
    pivot = Node3D.new()
    pivot.name = "Pivot"
    add_child(pivot)

    model = MODEL.instantiate()
    # The rig faces +Z; the camera rig treats -Z as forward.
    model.rotation = Vector3(0, PI, 0)
    pivot.add_child(model)

    skeleton = _find_skeleton(model)
    if skeleton == null:
        push_error("PlayerRig: no Skeleton3D in the model - animation will not run.")
        return

    for key: String in BONE_NAMES:
        var idx := skeleton.find_bone(BONE_NAMES[key])
        if idx < 0:
            push_warning("PlayerRig: bone '%s' (%s) not found in the imported skeleton." % [key, BONE_NAMES[key]])
        _bone_idx[key] = idx
        _angles[key] = Vector3.ZERO

    _angles["upperArmL"] = Vector3(0, ARM_REST_Y, 0)
    _angles["upperArmR"] = Vector3(0, ARM_REST_Y, 0)
    _angles["lowerArmL"] = Vector3(0, 0, ELBOW_REST)
    _angles["lowerArmR"] = Vector3(0, 0, ELBOW_REST)

    _colour_materials(model)
    _attach_cube()
    _apply_bones()

    # Measure the rest height with the root neutralised, so the calibration
    # isn't contaminated by wherever the player happens to be standing.
    var saved := transform
    transform = Transform3D.IDENTITY
    force_update_transform()
    _rest_feet_y = _lowest_foot_y()
    transform = saved


func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null


# The suit is coloured at runtime from the mesh's own material names plus a
# procedural web pattern, because the source model's ~18MB of textures were
# stripped to keep the asset shippable.
func _colour_materials(node: Node) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        var web := _web_texture()
        for i in range(mi.get_surface_override_material_count()):
            var existing := mi.mesh.surface_get_material(i)
            var mat_name := existing.resource_name if existing != null else ""
            var mat := StandardMaterial3D.new()
            mat.roughness = 0.55
            mat.metallic = 0.05
            if mat_name == "MI_HerbalFist_Mask":
                mat.albedo_color = Color("#b01423")
                mat.albedo_texture = web
                mat.uv1_scale = Vector3(6, 6, 1)
            elif mat_name == "MI_HerbalFist_Body":
                mat.albedo_color = Color("#1c3f9c")
                mat.albedo_texture = web
                mat.uv1_scale = Vector3(6, 6, 1)
            else:
                # The eyes, chiefly. A little emission keeps them readable as
                # the only bright thing on the character at night.
                mat.albedo_color = Color("#f2f2f2")
                mat.emission_enabled = true
                mat.emission = Color.WHITE
                mat.emission_energy_multiplier = 0.15
                mat.roughness = 0.3
            mi.set_surface_override_material(i, mat)
    for child in node.get_children():
        _colour_materials(child)


func _web_texture() -> ImageTexture:
    var size := 128
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color.WHITE)
    var line := Color(0, 0, 0, 0.35)
    # Two diagonal families crossing: a cheap stand-in for a webbed weave that
    # still reads correctly once it is scaled down onto the suit.
    for i in range(-size, size * 2, 14):
        for t in range(size):
            var ax := i + t
            var bx := i - t
            if ax >= 0 and ax < size:
                img.set_pixel(ax, t, line)
            if bx >= 0 and bx < size:
                img.set_pixel(bx, t, line)
    var tex := ImageTexture.create_from_image(img)
    return tex


# Stand perfectly still for ~5.5s and he pulls out a Rubik's cube and works on
# it - the Insomniac-style idle fidget, blending out the moment you move.
func _attach_cube() -> void:
    var idx: int = _bone_idx.get("handL", -1)
    if idx < 0:
        return
    var attach := BoneAttachment3D.new()
    attach.bone_idx = idx
    skeleton.add_child(attach)

    var face_colours := ["#d61f1f", "#ff8c1a", "#f2f2f2", "#f5d914", "#1fa83c", "#1f52d6"]
    _cube = Node3D.new()
    # Six thin slabs rather than one cube with six materials: a BoxMesh in
    # Godot has a single surface, so per-face colours need separate meshes.
    var offsets := [
        Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), Vector3(0.5, 0, 0),
        Vector3(-0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0, -0.5, 0),
    ]
    var sizes := [
        Vector3(1, 1, 0.04), Vector3(1, 1, 0.04), Vector3(0.04, 1, 1),
        Vector3(0.04, 1, 1), Vector3(1, 0.04, 1), Vector3(1, 0.04, 1),
    ]
    for i in range(6):
        var face := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = sizes[i]
        face.mesh = bm
        var m := StandardMaterial3D.new()
        m.albedo_color = Color(face_colours[i])
        m.roughness = 0.4
        face.material_override = m
        face.position = offsets[i]
        _cube.add_child(face)

    _cube.scale = Vector3.ONE * 0.062
    _cube.position = Vector3(0, 0.06, 0)
    _cube.visible = false
    attach.add_child(_cube)


func _lowest_foot_y() -> float:
    var l: int = _bone_idx.get("ballL", -1)
    var r: int = _bone_idx.get("ballR", -1)
    if l < 0 or r < 0 or skeleton == null:
        return 0.0
    var sk := skeleton.global_transform
    var ly := (sk * skeleton.get_bone_global_pose(l)).origin.y
    var ry := (sk * skeleton.get_bone_global_pose(r)).origin.y
    return minf(ly, ry)


# World position of a hand bone, so the web line can leave the hand rather than
# the middle of the chest. Returns null before the model is ready.
func hand_world_position(side: String) -> Variant:
    var idx: int = _bone_idx.get("handR" if side == "right" else "handL", -1)
    if idx < 0 or skeleton == null:
        return null
    return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


# --- pose helpers ----------------------------------------------------------
func _lerp_bone(key: String, axis: int, target: float, dt: float, speed: float = 8.0) -> void:
    if not _angles.has(key):
        return
    var a: Vector3 = _angles[key]
    a[axis] += (target - a[axis]) * minf(1.0, dt * speed)
    _angles[key] = a


# Overlay blend, as opposed to _lerp_bone's time-based ease: mixes a target
# over whatever the state pose already wrote this frame, by an explicit 0..1
# amount driven by the overlay's own phase curve.
func _blend_bone(key: String, axis: int, target: float, amount: float) -> void:
    if not _angles.has(key):
        return
    var a: Vector3 = _angles[key]
    a[axis] = lerpf(a[axis], target, amount)
    _angles[key] = a


func _set_bone(key: String, v: Vector3) -> void:
    if _angles.has(key):
        _angles[key] = v


func _add_bone(key: String, axis: int, amount: float) -> void:
    if not _angles.has(key):
        return
    var a: Vector3 = _angles[key]
    a[axis] += amount
    _angles[key] = a


func _get_bone(key: String, axis: int) -> float:
    if not _angles.has(key):
        return 0.0
    return (_angles[key] as Vector3)[axis]


func _apply_bones() -> void:
    if skeleton == null:
        return
    for key: String in _angles:
        var idx: int = _bone_idx.get(key, -1)
        if idx < 0:
            continue
        # Explicit XYZ order - see the note at the top of this file.
        var basis := Basis.from_euler(_angles[key] as Vector3, EULER_ORDER_XYZ)
        skeleton.set_bone_pose_rotation(idx, basis.get_rotation_quaternion())


const AX := 0
const AY := 1
const AZ := 2


func set_transform_for(p: Vector3, yaw: float) -> void:
    global_position = p
    rotation.y = yaw


func update_tilt(dt: float, state: String, velocity: Vector3, forward_yaw: float) -> void:
    var pitch := 0.0
    var roll := 0.0
    var speed := velocity.length()
    if state == "wall":
        # Lean the body into the facade so he lies against it rather than
        # standing in front of it.
        pitch = -1.15
    elif state == "swing" or state == "air" or state == "zip":
        var local_forward := Vector3(sin(forward_yaw), 0, cos(forward_yaw))
        var right_axis := Vector3(local_forward.z, 0, -local_forward.x)
        var vn := velocity / speed if speed > 0.01 else Vector3.ZERO
        pitch = clampf(-vn.y * 0.9, -0.9, 0.9)
        roll = clampf(-vn.dot(right_axis) * 0.6, -0.7, 0.7)
    var target := Basis.from_euler(Vector3(pitch, 0, roll), EULER_ORDER_XYZ).get_rotation_quaternion()
    _current_tilt = _current_tilt.slerp(target, minf(1.0, dt * (10.0 if state == "wall" else 6.0)))
    pivot.quaternion = _current_tilt


func update_animation(dt: float, p: Dictionary) -> void:
    if skeleton == null:
        return

    var state: String = p.get("state", "air")
    var ground_speed: float = p.get("ground_speed", 0.0)
    var vertical_velocity: float = p.get("vertical_velocity", 0.0)
    var speed: float = p.get("speed", 0.0)
    var punching: bool = p.get("punching", false)
    var dodging: bool = p.get("dodging", false)
    var hurt: bool = p.get("hurt", false)
    var diving: bool = p.get("diving", false)
    var climbing: float = p.get("climbing", 0.0)
    var reach_target: Variant = p.get("reach_target", null)
    var reach_hand: String = p.get("reach_hand", "right")

    if DEBUG_BONE != "":
        _debug_phase += dt
        for key: String in _angles:
            _angles[key] = Vector3.ZERO
        var sweep := sin(_debug_phase) * 1.2
        _set_bone(DEBUG_BONE, Vector3(sweep, 0, 0) if int(_debug_phase / 6.0) % 3 == 0 \
            else (Vector3(0, sweep, 0) if int(_debug_phase / 6.0) % 3 == 1 else Vector3(0, 0, sweep)))
        _apply_bones()
        return

    var bob := 0.0

    if punching and _punch_phase >= 1.0:
        _punch_phase = 0.0
    if _punch_phase < 1.0:
        _punch_phase += dt / PUNCH_ANIM_DURATION
    if dodging and _dodge_phase >= 1.0:
        _dodge_phase = 0.0
    if _dodge_phase < 1.0:
        _dodge_phase += dt / DODGE_ANIM_DURATION
    if hurt and _hurt_phase >= 1.0:
        _hurt_phase = 0.0
    if _hurt_phase < 1.0:
        _hurt_phase += dt / HURT_ANIM_DURATION

    var settled := state == "ground" and ground_speed <= 0.4 \
        and _punch_phase >= 1.0 and _dodge_phase >= 1.0 and _hurt_phase >= 1.0
    _idle_still_time = _idle_still_time + dt if settled else 0.0
    var fidget_target := 1.0 if _idle_still_time > IDLE_FIDGET_DELAY else 0.0
    var fidget_step := dt / IDLE_FIDGET_BLEND
    # Blends in over the full window but drops twice as fast, so the cube is
    # gone before the first step registers rather than trailing the move.
    _fidget_amount = clampf(
        _fidget_amount + (fidget_step if fidget_target > _fidget_amount else -fidget_step * 2.0), 0.0, 1.0)

    if state == "wall":
        # Wall crawl: limbs splayed wide and flattened against the facade, with
        # a slow diagonal crawl cycle when moving. A standing pose stuck to a
        # wall reads as a decal; the spread is what sells the stick.
        _climb_phase += dt * (1.5 + minf(climbing, 8.0) * 0.7)
        var crawl := sin(_climb_phase) * minf(1.0, climbing / 3.0)
        _lerp_bone("upperArmR", AY, 0.35, dt, 10)
        _lerp_bone("upperArmR", AX, -1.15 + crawl * 0.45, dt, 10)
        _lerp_bone("upperArmL", AY, 0.35, dt, 10)
        _lerp_bone("upperArmL", AX, -1.15 - crawl * 0.45, dt, 10)
        _lerp_bone("lowerArmR", AZ, -0.9, dt, 10)
        _lerp_bone("lowerArmL", AZ, -0.9, dt, 10)
        _lerp_bone("thighR", AX, -0.5 - crawl * 0.35, dt, 10)
        _lerp_bone("thighL", AX, -0.5 + crawl * 0.35, dt, 10)
        _lerp_bone("calfR", AZ, 0.95, dt, 10)
        _lerp_bone("calfL", AZ, 0.95, dt, 10)
        _lerp_bone("spine", AX, -0.25, dt, 8)
        _lerp_bone("neck", AX, -0.35, dt, 8)   # head up, looking where he's going
        _lerp_bone("head", AX, -0.2, dt, 8)

    elif state == "ground" and ground_speed > 0.4:
        var speed_factor := minf(ground_speed / SPRINT_REF_SPEED, 1.6)
        _run_phase += dt * (6.5 + speed_factor * 6.0)
        var swing := sin(_run_phase)
        _set_bone("thighR", Vector3(-swing * 0.5, 0, 0))
        _set_bone("thighL", Vector3(swing * 0.5, 0, 0))
        # Lerped rather than hard-set to the thigh angle: an instantaneous 1:1
        # knee/thigh coupling reads as robotic, a frame or two of lag reads as
        # a joint with some give.
        _lerp_bone("calfR", AZ, maxf(0.0, -_get_bone("thighR", AX)) * 1.05, dt, 20)
        _lerp_bone("calfL", AZ, maxf(0.0, -_get_bone("thighL", AX)) * 1.05, dt, 20)
        _set_bone("upperArmR", Vector3(-0.25, ARM_REST_Y, swing * 0.5))
        _set_bone("upperArmL", Vector3(-0.25, ARM_REST_Y, -swing * 0.5))
        var elbow_base := lerpf(-0.7, -1.15, minf(1.0, speed_factor))
        _lerp_bone("lowerArmR", AZ, elbow_base + swing * 0.35, dt, 18)
        _lerp_bone("lowerArmL", AZ, elbow_base - swing * 0.35, dt, 18)
        _lerp_bone("spine", AX, 0.1 + speed_factor * 0.08, dt, 8)
        _lerp_bone("clavicleR", AZ, swing * 0.06, dt, 12)
        _lerp_bone("clavicleL", AZ, -swing * 0.06, dt, 12)
        _set_bone("head", Vector3.ZERO)
        _set_bone("neck", Vector3(-0.08, 0, 0))
        bob = absf(swing) * 0.045

    elif state == "ground":
        _idle_phase += dt * 1.6
        var sway := sin(_idle_phase)
        _lerp_bone("thighR", AX, 0.0, dt)
        _lerp_bone("thighL", AX, 0.0, dt)
        _lerp_bone("calfR", AZ, 0.0, dt)
        _lerp_bone("calfL", AZ, 0.0, dt)
        _set_bone("upperArmR", Vector3(0, ARM_REST_Y, sway * 0.05))
        _set_bone("upperArmL", Vector3(0, ARM_REST_Y, -sway * 0.05))
        _lerp_bone("lowerArmR", AZ, ELBOW_REST + sway * 0.05, dt, 6)
        _lerp_bone("lowerArmL", AZ, ELBOW_REST - sway * 0.05, dt, 6)
        _lerp_bone("spine", AX, sin(_idle_phase * 0.5) * 0.02, dt, 8)
        _set_bone("head", Vector3(0, sin(_idle_phase * 0.31) * 0.1, 0))
        _set_bone("neck", Vector3.ZERO)
        bob = sin(_idle_phase) * 0.012

    elif state == "swing":
        # Blends from a relaxed "just grabbed the line" hang into a streamlined
        # tuck as speed builds, so a fast swing reads as cutting through the air
        # rather than holding the shape it had when it attached.
        var t := clampf(speed / 55.0, 0.0, 1.0)
        _lerp_bone("thighR", AX, lerpf(-0.15, -0.6, t), dt, 6)
        _lerp_bone("thighL", AX, lerpf(-0.15, -0.45, t), dt, 6)
        _lerp_bone("calfR", AZ, lerpf(0.5, 0.15, t), dt, 6)
        _lerp_bone("calfL", AZ, lerpf(0.5, 0.55, t), dt, 6)
        _lerp_bone("spine", AX, lerpf(-0.1, -0.35, t), dt, 6)
        _lerp_bone("neck", AX, lerpf(0.0, -0.2, t), dt, 6)

        # The free arm trails; the swinging arm is overwritten by the reach
        # overlay below so it actually points at the line.
        var free_arm := "L" if reach_hand == "right" else "R"
        _lerp_bone("upperArm" + free_arm, AY, lerpf(0.9, 0.45, t), dt, 6)
        _lerp_bone("upperArm" + free_arm, AX, lerpf(0.3, 0.75, t), dt, 6)
        _lerp_bone("lowerArm" + free_arm, AZ, lerpf(-0.6, -0.3, t), dt, 6)

    else:
        # Airborne. A dive is its own shape: head-down, arms swept back, legs
        # straight - the streamlined tuck that earns the extra speed.
        var rising := vertical_velocity > 1.0
        var fall_t := clampf(-vertical_velocity / 40.0, 0.0, 1.0)
        if diving:
            _lerp_bone("thighR", AX, -0.25, dt, 7)
            _lerp_bone("thighL", AX, -0.25, dt, 7)
            _lerp_bone("calfR", AZ, 0.05, dt, 7)
            _lerp_bone("calfL", AZ, 0.05, dt, 7)
            _lerp_bone("upperArmR", AY, 0.2, dt, 7)
            _lerp_bone("upperArmR", AX, 1.25, dt, 7)
            _lerp_bone("upperArmL", AY, 0.2, dt, 7)
            _lerp_bone("upperArmL", AX, 1.25, dt, 7)
            _lerp_bone("lowerArmR", AZ, -0.2, dt, 7)
            _lerp_bone("lowerArmL", AZ, -0.2, dt, 7)
            _lerp_bone("spine", AX, -0.3, dt, 7)
            _lerp_bone("neck", AX, -0.3, dt, 7)
        else:
            var thigh_t := 0.35 if rising else lerpf(-0.1, -0.3, fall_t)
            var calf_t := 0.9 if rising else lerpf(0.15, 0.05, fall_t)
            _lerp_bone("thighR", AX, thigh_t, dt, 5)
            _lerp_bone("thighL", AX, thigh_t, dt, 5)
            _lerp_bone("calfR", AZ, calf_t, dt, 5)
            _lerp_bone("calfL", AZ, calf_t, dt, 5)
            _lerp_bone("upperArmR", AY, ARM_REST_Y * 0.5, dt, 5)
            _lerp_bone("upperArmR", AX, -0.3, dt, 5)
            _lerp_bone("upperArmL", AY, ARM_REST_Y * 0.5, dt, 5)
            _lerp_bone("upperArmL", AX, -0.3, dt, 5)
            _lerp_bone("lowerArmR", AZ, lerpf(-0.55, -1.0, fall_t), dt, 5)
            _lerp_bone("lowerArmL", AZ, lerpf(-0.55, -1.0, fall_t), dt, 5)
            _lerp_bone("spine", AX, -0.05 if rising else lerpf(0.1, 0.25, fall_t), dt, 5)
            _lerp_bone("neck", AX, 0.0, dt, 5)

    # Reach overlay: the swinging arm points at the live anchor. Not real IK -
    # the anchor direction is converted into the model's own frame and mapped
    # onto the shoulder's two useful axes, which is enough for the arm to track
    # the line as the arc carries you under and past it.
    #
    # Godot does ship SkeletonIK3D, which would solve the full chain properly
    # and is the obvious upgrade here; this keeps the browser build's tuned
    # behaviour as the starting point so the two can be compared directly.
    if reach_target != null:
        var side := "R" if reach_hand == "right" else "L"
        var local: Vector3 = to_local(reach_target as Vector3)
        var horiz := maxf(0.001, Vector2(local.x, local.z).length())
        var elevation := atan2(local.y, horiz)          # + is above
        # A high anchor sweeps the arm overhead (upperarm x negative raises it
        # forward/up); sideways offset swings it out.
        var raise_amt := clampf(-0.35 - elevation * 1.15, -1.9, 0.2)
        var outward := clampf(local.x / horiz, -1.0, 1.0) * (-1.0 if side == "R" else 1.0)
        _set_bone("upperArm" + side, Vector3(raise_amt, clampf(0.55 + outward * 0.5, 0.0, 1.4), 0.0))
        _set_bone("lowerArm" + side, Vector3(0, 0, -0.35))   # nearly straight, taking the load

    if _punch_phase < 1.0:
        var amt := sin(clampf(_punch_phase, 0.0, 1.0) * PI)
        _blend_bone("upperArmR", AX, -1.4, amt)
        _blend_bone("upperArmR", AY, ARM_REST_Y * 0.3, amt)
        # The elbow drives the punch: cocked at the start, snapping through to
        # almost straight at full extension, which sells an impact far more
        # than rotating the shoulder does.
        _blend_bone("lowerArmR", AZ, lerpf(-1.7, -0.1, minf(1.0, _punch_phase * 1.6)), amt)
        _blend_bone("lowerArmL", AZ, -1.6, amt * 0.8)
        _set_bone("spine", Vector3(_get_bone("spine", AX), -0.25 * amt, _get_bone("spine", AZ)))

    if _dodge_phase < 1.0:
        var d := sin(clampf(_dodge_phase, 0.0, 1.0) * PI)
        _add_bone("spine", AX, 0.5 * d)
        _add_bone("spine", AY, 0.4 * d)
        _blend_bone("thighR", AX, 0.7, d)
        _blend_bone("thighL", AX, 0.35, d)
        _blend_bone("calfR", AZ, 1.0, d)
        _blend_bone("calfL", AZ, 0.7, d)
        _blend_bone("lowerArmR", AZ, -1.9, d)
        _blend_bone("lowerArmL", AZ, -1.9, d)
        _blend_bone("upperArmR", AX, -0.5, d)
        _blend_bone("upperArmL", AX, -0.5, d)
        bob -= 0.25 * d

    if _hurt_phase < 1.0:
        var h_amt := sin(clampf(_hurt_phase, 0.0, 1.0) * PI)
        _add_bone("spine", AX, -0.45 * h_amt)
        _blend_bone("head", AX, 0.4, h_amt)
        _blend_bone("upperArmR", AZ, 0.5, h_amt)
        _blend_bone("upperArmL", AZ, -0.5, h_amt)
        _blend_bone("lowerArmR", AZ, -1.3, h_amt)
        _blend_bone("lowerArmL", AZ, -1.3, h_amt)

    if _cube != null:
        var f := _fidget_amount
        _cube.visible = f > 0.02
        if f > 0.02:
            _cube_solve_phase += dt * 2.2
            _blend_bone("upperArmR", AX, -0.55, f)
            _blend_bone("upperArmR", AY, 1.28, f)
            _blend_bone("upperArmR", AZ, 0.1, f)
            _blend_bone("upperArmL", AX, -0.55, f)
            _blend_bone("upperArmL", AY, 1.28, f)
            _blend_bone("upperArmL", AZ, -0.1, f)
            _blend_bone("lowerArmR", AZ, -1.95, f)
            _blend_bone("lowerArmL", AZ, -1.95, f)
            _blend_bone("neck", AX, -0.18, f)
            _blend_bone("head", AX, -0.32, f)
            var twist := sin(_cube_solve_phase)
            _blend_bone("handR", AZ, twist * 0.7, f)
            _blend_bone("handL", AZ, -twist * 0.15, f)
            var quarters := floorf(_cube_solve_phase / PI)
            _cube.rotation = Vector3(quarters * (PI / 4.0), quarters * (PI / 2.0), twist * 0.25)

    _apply_bones()

    # Keep the animated feet out of the ground whatever pose just ran -
    # measured live from the two ball-of-foot bones rather than a precomputed
    # curve, so it stays correct for any future pose tweak. Skipped on a wall,
    # where "down" for the body isn't world down at all.
    model.position.y = -_rest_feet_y + bob
    if state != "wall":
        force_update_transform()
        var dip := _lowest_foot_y() - global_position.y
        if dip < 0.0:
            model.position.y -= dip
