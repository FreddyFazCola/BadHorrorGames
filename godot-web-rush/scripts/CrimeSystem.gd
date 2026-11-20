extends Node3D
class_name CrimeSystem

# Spawns "crimes" - a red beacon plus a thug standing under it. The beacon is
# how you spot one while swinging; the thug is what you fight. Thugs fight
# back, so tick() also sums the damage they land each frame and surfaces the
# nearest telegraphing attack as "spidey sense".

const MAX_ACTIVE := 3
const SPAWN_INTERVAL_MIN := 9.0
const SPAWN_INTERVAL_MAX := 18.0
const FIRST_SPAWN_DELAY := 3.5
const SPAWN_MIN_DIST := 35.0
const SPAWN_MAX_DIST := 150.0
const PUNCH_RANGE := 2.6
const BEAM_HEIGHT := 14.0

signal crime_stopped

var city: City
var crimes: Array = []
var stopped_count := 0
var _next_spawn_in := FIRST_SPAWN_DELAY


func _build_marker() -> Dictionary:
    var group := Node3D.new()

    # An open-ended cone, unshaded and additive, so it reads as a shaft of
    # light rather than a solid object - and from directly above, where the
    # beam is edge-on, the ring on the ground is what you see instead.
    var beam := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.25
    cyl.bottom_radius = 0.05
    cyl.height = BEAM_HEIGHT
    cyl.cap_top = false
    cyl.cap_bottom = false
    beam.mesh = cyl
    beam.position.y = BEAM_HEIGHT / 2.0
    var beam_mat := StandardMaterial3D.new()
    beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    beam_mat.albedo_color = Color(1.0, 0.165, 0.165, 0.55)
    beam_mat.no_depth_test = false
    beam.material_override = beam_mat
    group.add_child(beam)

    var ring := MeshInstance3D.new()
    var torus := TorusMesh.new()
    torus.inner_radius = 1.6
    torus.outer_radius = 2.2
    ring.mesh = torus
    ring.position.y = 0.08
    var ring_mat := StandardMaterial3D.new()
    ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ring_mat.albedo_color = Color(1.0, 0.165, 0.165, 0.7)
    ring.material_override = ring_mat
    group.add_child(ring)

    var light := OmniLight3D.new()
    light.light_color = Color(1.0, 0.13, 0.13)
    light.light_energy = 3.0
    light.omni_range = 30.0
    light.position.y = 2.0
    group.add_child(light)

    add_child(group)
    return {"group": group, "beam": beam, "beam_mat": beam_mat, "ring": ring, "light": light}


func tick(dt: float, player_pos: Vector3) -> Dictionary:
    _next_spawn_in -= dt
    if _next_spawn_in <= 0.0 and crimes.size() < MAX_ACTIVE:
        _spawn(player_pos)

    var nearest: Variant = null
    var nearest_dist := INF
    var player_damage := 0.0
    var spidey: Variant = null

    for crime: Dictionary in crimes.duplicate():
        crime["time"] += dt
        var ring: MeshInstance3D = crime["ring"]
        ring.rotation.y += dt * 0.6
        ring.scale = Vector3.ONE * (1.0 + sin(crime["time"] * 3.0) * 0.08)
        var beam_mat: StandardMaterial3D = crime["beam_mat"]
        var c := beam_mat.albedo_color
        c.a = 0.4 + sin(crime["time"] * 5.0) * 0.2
        beam_mat.albedo_color = c
        var light: OmniLight3D = crime["light"]
        light.light_energy = 2.2 + sin(crime["time"] * 7.0) * 1.4

        var enemy: Enemy = crime["enemy"]
        player_damage += enemy.tick(dt, player_pos)

        var group: Node3D = crime["group"]
        var d := group.global_position.distance_to(player_pos)
        if d < nearest_dist:
            nearest_dist = d
            nearest = crime
        if enemy.telegraphing:
            var ed := enemy.global_position.distance_to(player_pos)
            if spidey == null or ed < (spidey as Dictionary)["dist"]:
                spidey = {
                    "dist": ed,
                    "dir_yaw": atan2(enemy.global_position.x - player_pos.x,
                                     enemy.global_position.z - player_pos.z),
                }
        if enemy.defeated:
            _stop(crime)

    var near: Dictionary = nearest if nearest != null else {}
    return {
        "nearest_dist": nearest_dist if nearest != null else null,
        "engaged": nearest != null and nearest_dist < PUNCH_RANGE + 3.0,
        "enemy_health": float((near["enemy"] as Enemy).health) if nearest != null else 0.0,
        "enemy_max_health": float(near.get("enemy_max_health", 0)) if nearest != null else 0.0,
        "active_count": crimes.size(),
        "stopped_count": stopped_count,
        "player_damage": player_damage,
        "spidey_sense": spidey,
    }


func try_punch(player_position: Vector3, damage: int = 1) -> Dictionary:
    var best: Variant = null
    var best_dist := PUNCH_RANGE
    for crime: Dictionary in crimes:
        var enemy: Enemy = crime["enemy"]
        if enemy.state == "defeated":
            continue
        var d := enemy.global_position.distance_to(player_position)
        if d <= best_dist:
            best_dist = d
            best = crime
    if best == null:
        return {"hit": false, "defeated": false}
    var defeated: bool = ((best as Dictionary)["enemy"] as Enemy).take_hit(damage)
    return {"hit": true, "defeated": defeated}


# Is any thug mid-wind-up within `radius`? Drives the perfect dodge.
func is_danger_near(position: Vector3, radius: float) -> bool:
    for crime: Dictionary in crimes:
        var enemy: Enemy = crime["enemy"]
        if enemy.telegraphing and enemy.global_position.distance_to(position) <= radius:
            return true
    return false


# Soft lock-on for aim and web-zip: the nearest live thug within a forgiving
# ~10 degree cone, rather than a literal raycast against their mesh. Aiming at
# a running figure with a hard ray is miserable on a controller.
func find_aim_target(origin: Vector3, dir: Vector3, max_dist: float) -> Variant:
    var best: Variant = null
    var best_dot := 0.985
    for crime: Dictionary in crimes:
        var enemy: Enemy = crime["enemy"]
        if enemy.state == "defeated":
            continue
        var to_enemy := enemy.global_position - origin
        var dist := to_enemy.length()
        if dist > max_dist or dist < 0.5:
            continue
        var dot := (to_enemy / dist).dot(dir)
        if dot > best_dot:
            best_dot = dot
            best = enemy
    return best


func _spawn(player_pos: Vector3) -> void:
    var spot: Variant = city.random_spawn_point(player_pos.x, player_pos.z, SPAWN_MIN_DIST, SPAWN_MAX_DIST)
    _next_spawn_in = randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
    if spot == null:
        return

    var marker := _build_marker()
    var group: Node3D = marker["group"]
    group.global_position = spot as Vector3

    var enemy := Enemy.new()
    add_child(enemy)
    enemy.setup(spot as Vector3)

    marker["enemy"] = enemy
    marker["enemy_max_health"] = Enemy.HIT_POINTS
    marker["time"] = randf() * 10.0
    crimes.append(marker)


func reset() -> void:
    for crime: Dictionary in crimes:
        _dispose(crime)
    crimes.clear()
    stopped_count = 0
    _next_spawn_in = FIRST_SPAWN_DELAY


func _dispose(crime: Dictionary) -> void:
    (crime["group"] as Node3D).queue_free()
    (crime["enemy"] as Enemy).queue_free()


func _stop(crime: Dictionary) -> void:
    _dispose(crime)
    crimes.erase(crime)
    stopped_count += 1
    crime_stopped.emit()
