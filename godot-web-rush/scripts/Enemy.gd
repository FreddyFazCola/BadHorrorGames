extends Node3D
class_name Enemy

# A thug. Runs idle -> approach -> telegraph -> attack -> recover.
#
# The telegraph is the whole design: a visible wind-up that is a fair warning,
# long enough to read and react to. Punching interrupts any state, so a
# counter-punch mid-wind-up works the way you'd expect it to.

const HIT_POINTS := 3
const FLINCH_DURATION := 0.35
const DEFEAT_DURATION := 1.1
const AGGRO_RANGE := 16.0
const ATTACK_RANGE := 2.6
const LEASH_RANGE := 11.0
const MOVE_SPEED := 3.4
const TELEGRAPH_DURATION := 0.55
const ATTACK_DURATION := 0.35
const ATTACK_HIT_T := 0.55
const RECOVER_MIN := 0.5
const RECOVER_MAX := 1.1
const ATTACK_DAMAGE := 12.0

const MODEL: PackedScene = preload("res://assets/models/spiderman.glb")

const AX := 0
const AY := 1
const AZ := 2

var health := HIT_POINTS
var state := "idle"      # idle | approach | telegraph | attack | recover | flinch | defeated
var telegraphing := false
var defeated := false

var _model: Node3D
var _skeleton: Skeleton3D
var _bone_idx: Dictionary = {}
var _angles: Dictionary = {}
var _spawn_pos := Vector3.ZERO
var _state_time := 0.0
var _recover_for := RECOVER_MIN
var _attack_did_hit := false
var _idle_phase := 0.0
var _facing := 0.0
var _rest_feet_y := 0.0


func setup(p: Vector3) -> void:
    global_position = p
    _spawn_pos = p


func _ready() -> void:
    _idle_phase = randf() * 10.0
    _facing = randf() * TAU

    _model = MODEL.instantiate()
    _model.rotation = Vector3(0, PI, 0)
    add_child(_model)

    _skeleton = _find_skeleton(_model)
    if _skeleton == null:
        push_error("Enemy: no Skeleton3D in the model.")
        return

    for key: String in PlayerRig.BONE_NAMES:
        _bone_idx[key] = _skeleton.find_bone(PlayerRig.BONE_NAMES[key])
        _angles[key] = Vector3.ZERO
    _angles["upperArmL"] = Vector3(0, PlayerRig.ARM_REST_Y, 0)
    _angles["upperArmR"] = Vector3(0, PlayerRig.ARM_REST_Y, 0)
    # Same soft-elbow rest as the player - a thug with ruler-straight arms
    # reads as a shop mannequin too.
    _angles["lowerArmL"] = Vector3(0, 0, PlayerRig.ELBOW_REST)
    _angles["lowerArmR"] = Vector3(0, 0, PlayerRig.ELBOW_REST)

    _recolour(_model)
    _apply_bones()
    force_update_transform()
    _rest_feet_y = _lowest_foot_y() - global_position.y


func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null


# The thug is the same mesh as the player, recoloured dark with a red glow, so
# one asset covers both and the silhouette stays readable at distance.
func _recolour(node: Node) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        for i in range(mi.get_surface_override_material_count()):
            var existing := mi.mesh.surface_get_material(i)
            var mat_name := existing.resource_name if existing != null else ""
            var mat := StandardMaterial3D.new()
            mat.roughness = 0.7
            mat.metallic = 0.05
            if mat_name == "MI_HerbalFist_Mask":
                mat.albedo_color = Color("#1a1a1a")
            elif mat_name == "MI_HerbalFist_Body":
                mat.albedo_color = Color("#2b2b30")
            else:
                mat.albedo_color = Color("#ff3b3b")
                mat.emission_enabled = true
                mat.emission = Color("#ff0000")
                mat.emission_energy_multiplier = 0.3
            mi.set_surface_override_material(i, mat)
    for child in node.get_children():
        _recolour(child)


func _set_bone(key: String, v: Vector3) -> void:
    if _angles.has(key):
        _angles[key] = v


func _set_axis(key: String, axis: int, value: float) -> void:
    if not _angles.has(key):
        return
    var a: Vector3 = _angles[key]
    a[axis] = value
    _angles[key] = a


func _apply_bones() -> void:
    if _skeleton == null:
        return
    for key: String in _angles:
        var idx: int = _bone_idx.get(key, -1)
        if idx < 0:
            continue
        var basis := Basis.from_euler(_angles[key] as Vector3, EULER_ORDER_XYZ)
        _skeleton.set_bone_pose_rotation(idx, basis.get_rotation_quaternion())


func _lowest_foot_y() -> float:
    var l: int = _bone_idx.get("ballL", -1)
    var r: int = _bone_idx.get("ballR", -1)
    if l < 0 or r < 0 or _skeleton == null:
        return global_position.y
    var sk := _skeleton.global_transform
    return minf((sk * _skeleton.get_bone_global_pose(l)).origin.y,
                (sk * _skeleton.get_bone_global_pose(r)).origin.y)


# Returns true if this hit finished them off. Interrupts whatever they were
# doing - mid-telegraph or mid-swing - like a real counter-punch.
func take_hit(damage: int = 1) -> bool:
    if state == "defeated":
        return false
    health -= damage
    _state_time = 0.0
    telegraphing = false
    state = "defeated" if health <= 0 else "flinch"
    return state == "defeated"


func _dist_to(p: Vector3) -> float:
    return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _turn_toward(p: Vector3, dt: float, rate: float) -> void:
    var target := atan2(p.x - global_position.x, p.z - global_position.z)
    var delta := target - _facing
    delta = atan2(sin(delta), cos(delta))     # shortest way round
    _facing += delta * minf(1.0, dt * rate)
    rotation.y = _facing


# Returns how much damage this update dealt to the player (0 most frames).
func tick(dt: float, player_pos: Vector3) -> float:
    if _skeleton == null:
        return 0.0
    _state_time += dt
    var rest := PlayerRig.ELBOW_REST
    var arm_rest := PlayerRig.ARM_REST_Y

    if state == "defeated":
        var t := minf(1.0, _state_time / DEFEAT_DURATION)
        rotation.x = -t * (PI / 2.0)
        _model.position.y = -_rest_feet_y - t * 0.6
        if t >= 1.0:
            defeated = true
        return 0.0

    if state == "flinch":
        var t := minf(1.0, _state_time / FLINCH_DURATION)
        var snap := sin(t * PI)
        _set_axis("spine", AX, -0.3 * snap)
        _set_bone("upperArmL", Vector3(0, arm_rest, -0.6 * snap))
        _set_bone("upperArmR", Vector3(0, arm_rest, 0.6 * snap))
        _set_axis("lowerArmL", AZ, rest - 1.1 * snap)
        _set_axis("lowerArmR", AZ, rest - 1.1 * snap)
        if t >= 1.0:
            state = "approach" if _dist_to(player_pos) < AGGRO_RANGE else "idle"
        telegraphing = false
        _finish_pose()
        return 0.0

    var damage_dealt := 0.0
    var dist := _dist_to(player_pos)
    var from_spawn := global_position.distance_to(_spawn_pos)

    if state == "idle":
        _idle_phase += dt * 1.4
        var sway := sin(_idle_phase)
        _set_bone("upperArmL", Vector3(0, arm_rest, sway * 0.05))
        _set_bone("upperArmR", Vector3(0, arm_rest, -sway * 0.05))
        _set_axis("lowerArmL", AZ, rest + sway * 0.06)
        _set_axis("lowerArmR", AZ, rest - sway * 0.06)
        _set_axis("spine", AX, sin(_idle_phase * 0.5) * 0.02)
        if dist < 400.0:
            _turn_toward(player_pos, dt, 2.0)
        if dist < AGGRO_RANGE:
            state = "approach"

    elif state == "approach":
        _turn_toward(player_pos, dt, 3.5)
        # Leashed to the spawn point, so a thug can't be walked across the
        # whole city and the crime stays where its beacon is.
        if dist > ATTACK_RANGE and from_spawn < LEASH_RANGE:
            global_position.x += sin(_facing) * MOVE_SPEED * dt
            global_position.z += cos(_facing) * MOVE_SPEED * dt
            _idle_phase += dt * 8.0
            var stride := sin(_idle_phase)
            _set_bone("upperArmL", Vector3(-0.15, arm_rest, stride * 0.3))
            _set_bone("upperArmR", Vector3(-0.15, arm_rest, -stride * 0.3))
            _set_axis("lowerArmL", AZ, -0.75 + stride * 0.25)
            _set_axis("lowerArmR", AZ, -0.75 - stride * 0.25)
        if dist <= ATTACK_RANGE:
            state = "telegraph"
            _state_time = 0.0
            _attack_did_hit = false
        elif dist > AGGRO_RANGE * 1.4:
            state = "idle"

    elif state == "telegraph":
        _turn_toward(player_pos, dt, 5.0)
        var t := minf(1.0, _state_time / TELEGRAPH_DURATION)
        _set_bone("upperArmR", Vector3(0, arm_rest * 0.4, -1.6 * t))
        _set_axis("lowerArmR", AZ, -0.4 - 1.5 * t)
        _set_axis("lowerArmL", AZ, -1.4 * t)
        _set_axis("spine", AX, -0.15 * t)
        if t >= 1.0:
            state = "attack"
            _state_time = 0.0

    elif state == "attack":
        _turn_toward(player_pos, dt, 5.0)
        var t := minf(1.0, _state_time / ATTACK_DURATION)
        var through := minf(1.0, t / 0.6)
        _set_bone("upperArmR", Vector3(0, arm_rest * 0.2, -1.6 + 2.2 * through))
        _set_axis("lowerArmR", AZ, -1.9 + 1.8 * through)
        _set_axis("spine", AX, -0.15 + 0.35 * through)
        # The hit lands partway through the swing, not on the first frame of
        # it, so the animation and the damage agree with each other.
        if not _attack_did_hit and t >= ATTACK_HIT_T:
            _attack_did_hit = true
            if dist <= ATTACK_RANGE + 0.6:
                damage_dealt = ATTACK_DAMAGE
        if t >= 1.0:
            state = "recover"
            _state_time = 0.0
            _recover_for = randf_range(RECOVER_MIN, RECOVER_MAX)

    elif state == "recover":
        _turn_toward(player_pos, dt, 3.0)
        _set_bone("upperArmR", Vector3(0, arm_rest, 0))
        _set_axis("lowerArmR", AZ, rest)
        _set_axis("lowerArmL", AZ, rest)
        _set_axis("spine", AX, 0.0)
        if _state_time >= _recover_for:
            state = "telegraph" if dist <= ATTACK_RANGE else "approach"
            _state_time = 0.0

    telegraphing = state == "telegraph"
    _finish_pose()
    return damage_dealt


func _finish_pose() -> void:
    _apply_bones()
    _model.position.y = -_rest_feet_y
    force_update_transform()
    var dip := _lowest_foot_y() - global_position.y
    if dip < 0.0:
        _model.position.y -= dip
