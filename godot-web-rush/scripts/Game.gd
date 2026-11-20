extends Node3D
class_name Game

# Scene wiring and the mode state machine. Main.tscn holds the structural
# nodes; everything procedural (the city's buildings, the character's rig, the
# crime beacons, the HUD's controls) is built at runtime by the scripts that
# own it.

enum Mode { MENU, PLAYING, PAUSED, GAMEOVER }

const SPAWN := Vector3(0, 1, 18)

# Speed blur ramp. Nothing below the floor - a blur that is always slightly on
# just looks like a dirty screen - and it tops out well before the ~68 m/s a
# good chain of swings actually reaches, so the fastest flying is the most
# smeared without the effect saturating and then flattening out.
const BLUR_SPEED_FLOOR := 22.0
const BLUR_SPEED_REF := 62.0
const BLUR_MAX := 0.16

var mode: Mode = Mode.MENU

var city: City
var input_mgr: InputManager
var rig: PlayerRig
var controller: PlayerController
var crimes: CrimeSystem
var camera: Camera3D
var hud: Node
var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial
var _blur_amount := 0.0


func _ready() -> void:
    camera = $Camera3D
    city = $City
    crimes = $CrimeSystem
    hud = $HUDLayer

    input_mgr = InputManager.new()
    input_mgr.name = "InputManager"
    add_child(input_mgr)

    rig = PlayerRig.new()
    rig.name = "PlayerRig"
    add_child(rig)

    crimes.city = city
    _aim_lights()

    controller = PlayerController.new()
    controller.name = "PlayerController"
    controller.city = city
    controller.input = input_mgr
    controller.rig = rig
    controller.crimes = crimes
    controller.camera = camera
    controller.web_line = _make_web_line()
    controller.anchor_marker = _make_anchor_marker()
    add_child(controller)

    controller.died.connect(_on_died)
    controller.perfect_dodge.connect(func() -> void: hud.flash("PERFECT DODGE", false))
    controller.perfect_release.connect(func() -> void: hud.flash("PERFECT RELEASE", true))
    controller.landed.connect(_on_landed)
    crimes.crime_stopped.connect(func() -> void: hud.crime_stopped_toast())

    _build_speed_blur()

    controller.reset_to(SPAWN)
    controller.set_physics_process(false)
    hud.show_menu()


# A full-screen quad on its own CanvasLayer, under the HUD's layer so the blur
# smears the world and not the text over it.
func _build_speed_blur() -> void:
    var layer := CanvasLayer.new()
    layer.layer = -1
    add_child(layer)

    _blur_mat = ShaderMaterial.new()
    _blur_mat.shader = load("res://shaders/speed_blur.gdshader")

    _blur_rect = ColorRect.new()
    _blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    _blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _blur_rect.material = _blur_mat
    _blur_rect.visible = false
    layer.add_child(_blur_rect)


# Written here rather than as a basis matrix in the scene file: a light's
# direction is the thing that matters, and "point -Z at this offset from the
# origin" says it exactly, where nine serialised matrix components do not.
func _aim_lights() -> void:
    ($KeyLight as DirectionalLight3D).look_at_from_position(
        Vector3.ZERO, Vector3(120, -90, 60), Vector3.UP)
    ($RimLight as DirectionalLight3D).look_at_from_position(
        Vector3.ZERO, Vector3(-90, -60, -110), Vector3.UP)


func _make_web_line() -> MeshInstance3D:
    var line := MeshInstance3D.new()
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(1, 1, 1, 0.85)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.vertex_color_use_as_albedo = false
    line.material_override = mat
    # The line's two vertices are rebuilt in world space every frame, so
    # frustum culling against a stale AABB would blink it out at the exact
    # moments it matters most.
    line.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
    line.visible = false
    add_child(line)
    return line


func _make_anchor_marker() -> MeshInstance3D:
    var marker := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.4
    sphere.height = 0.8
    marker.mesh = sphere
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color.WHITE
    marker.material_override = mat
    marker.visible = false
    add_child(marker)
    return marker


func _process(dt: float) -> void:
    if mode != Mode.PLAYING:
        return

    controller.frame_update(dt)
    controller.update_camera(dt)
    city.update_streaming(controller.pos.x, controller.pos.z)

    _update_speed_blur(dt)

    var info := crimes.tick(dt, controller.pos)
    if info["player_damage"] > 0.0:
        controller.take_damage(info["player_damage"])

    hud.update_hud({
        "height": controller.pos.y,
        "speed": controller.vel.length(),
        "health": controller.health,
        "max_health": controller.max_health,
        "state": controller.state,
        "on_wall": controller.on_wall,
        "diving": controller.diving,
        "aiming": controller.aiming,
        "aim_locked": controller.aim_target != null and (controller.aim_target as Dictionary)["locked"],
        "yaw": input_mgr.yaw,
    }, info)


func _update_speed_blur(dt: float) -> void:
    var speed := controller.vel.length()
    var target := clampf((speed - BLUR_SPEED_FLOOR) / (BLUR_SPEED_REF - BLUR_SPEED_FLOOR), 0.0, 1.0) * BLUR_MAX
    # Eased rather than set directly: speed changes abruptly at an attach or a
    # release, and snapping the blur with it pops.
    _blur_amount = lerpf(_blur_amount, target, 1.0 - exp(-5.0 * dt))

    _blur_rect.visible = _blur_amount > 0.002
    if not _blur_rect.visible:
        return

    # Put the centre of the smear where the player is actually heading, by
    # projecting the velocity onto the camera plane. Pinned to screen centre
    # the effect is symmetrical and reads as a zoom; led toward the direction
    # of travel it reads as being carried.
    var centre := Vector2(0.5, 0.5)
    if speed > 1.0:
        var ahead := controller.pos + controller.vel.normalized() * 40.0
        if not camera.is_position_behind(ahead):
            var screen := camera.unproject_position(ahead)
            var vp := get_viewport().get_visible_rect().size
            if vp.x > 0.0 and vp.y > 0.0:
                var uv := screen / vp
                # Clamped close to the middle: a smear centred off in the
                # corner of the screen looks like a glitch, not momentum.
                centre = Vector2(clampf(uv.x, 0.25, 0.75), clampf(uv.y, 0.25, 0.75))

    _blur_mat.set_shader_parameter("amount", _blur_amount)
    _blur_mat.set_shader_parameter("centre", centre)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
        if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
            if mode == Mode.PLAYING:
                pause()
            elif mode == Mode.PAUSED:
                resume()


func _on_landed(fall_speed: float) -> void:
    input_mgr.rumble(minf(1.0, fall_speed / 45.0), minf(1.0, fall_speed / 28.0), 110)


func _on_died() -> void:
    mode = Mode.GAMEOVER
    controller.set_physics_process(false)
    input_mgr.exit_lock()
    hud.show_gameover(crimes.stopped_count)


func start() -> void:
    mode = Mode.PLAYING
    controller.set_physics_process(true)
    input_mgr.request_lock()
    hud.show_playing()


func pause() -> void:
    if mode != Mode.PLAYING:
        return
    mode = Mode.PAUSED
    controller.set_physics_process(false)
    input_mgr.exit_lock()
    input_mgr.stop_rumble()
    hud.show_pause()


func resume() -> void:
    if mode != Mode.PAUSED:
        return
    mode = Mode.PLAYING
    controller.set_physics_process(true)
    input_mgr.request_lock()
    hud.show_playing()


func restart() -> void:
    crimes.reset()
    controller.reset_to(SPAWN)
    city.update_streaming(SPAWN.x, SPAWN.z)
    start()


func quit_to_menu() -> void:
    mode = Mode.MENU
    crimes.reset()
    controller.set_physics_process(false)
    controller.reset_to(SPAWN)
    input_mgr.exit_lock()
    input_mgr.stop_rumble()
    hud.show_menu()
