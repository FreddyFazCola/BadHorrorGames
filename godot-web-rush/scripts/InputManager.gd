extends Node
class_name InputManager

# Input is read straight off the device rather than through Godot's InputMap.
#
# That's deliberate: the swing needs the *analogue* value of R2 (rope tension
# follows the pull, and the trigger is a threshold press on mouse and keyboard
# but a continuous axis on a controller), and it needs mouse-look deltas that
# aren't quantised into an action's 0..1 strength. Reading the hardware keeps
# the two schemes in one place and makes the mapping match the code exactly.
# Remapping is the obvious next step and would move this to InputMap actions.

const TRIGGER_PRESS := 0.3
const LOOK_SENSITIVITY := 0.0022
const STICK_LOOK_SPEED := 2.4
const STICK_DEADZONE := 0.18

var yaw := 0.0
var pitch := 0.0
var locked := false

# Edge-triggered presses are latched here and consumed by the controller, so a
# press is never missed because it happened between physics steps and never
# handled twice.
var _jump_pressed := false
var _punch_pressed := false
var _zip_pressed := false
var _dodge_pressed := false

var _raw_mouse_down := false
var _gp_web_value := 0.0
var _gp_aim_value := 0.0
var _device := -1

var _prev_buttons := {}
var _rumble_until := 0.0

# Rope tension, 0..1, written every swing step. Godot has no API for the
# DualSense's adaptive triggers (see README), so this currently only drives
# ordinary vibration - but it stays exposed so a GDExtension can pick it up
# without touching the physics.
var trigger_tension := 0.0


func _ready() -> void:
    for dev in Input.get_connected_joypads():
        _device = dev
        break
    Input.joy_connection_changed.connect(_on_joy_changed)


func _on_joy_changed(device: int, connected: bool) -> void:
    if connected and _device < 0:
        _device = device
    elif not connected and device == _device:
        _device = -1
        for dev in Input.get_connected_joypads():
            _device = dev
            break


# --- pointer lock ----------------------------------------------------------
func request_lock() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    locked = true


func exit_lock() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    locked = false


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and locked:
        var motion := event as InputEventMouseMotion
        yaw -= motion.relative.x * LOOK_SENSITIVITY
        pitch = clampf(pitch - motion.relative.y * LOOK_SENSITIVITY, -1.45, 1.45)

    elif event is InputEventMouseButton:
        var btn := event as InputEventMouseButton
        if btn.button_index == MOUSE_BUTTON_LEFT:
            _raw_mouse_down = btn.pressed
        elif btn.button_index == MOUSE_BUTTON_RIGHT:
            _gp_aim_value = 1.0 if btn.pressed else 0.0

    elif event is InputEventKey:
        var key := event as InputEventKey
        if not key.pressed or key.echo:
            return
        match key.physical_keycode:
            KEY_SPACE: _jump_pressed = true
            KEY_E: _punch_pressed = true
            KEY_Q: _zip_pressed = true
            KEY_C: _dodge_pressed = true


func _notification(what: int) -> void:
    # Losing focus with keys held leaves them latched down forever: alt-tab
    # away mid-sprint and you come back still sprinting with no key pressed.
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _raw_mouse_down = false
        _gp_web_value = 0.0
        _gp_aim_value = 0.0
        _jump_pressed = false
        _punch_pressed = false
        _zip_pressed = false
        _dodge_pressed = false


# --- gamepad ---------------------------------------------------------------
func poll_gamepad(delta: float) -> void:
    if _device < 0:
        return

    _gp_web_value = Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_RIGHT)
    var l2 := Input.get_joy_axis(_device, JOY_AXIS_TRIGGER_LEFT)
    if l2 > TRIGGER_PRESS:
        _gp_aim_value = l2

    # Right stick looks. Squared response so small inputs are precise and the
    # outer range still swings the camera fast.
    var rx := Input.get_joy_axis(_device, JOY_AXIS_RIGHT_X)
    var ry := Input.get_joy_axis(_device, JOY_AXIS_RIGHT_Y)
    if absf(rx) > STICK_DEADZONE:
        yaw -= signf(rx) * pow((absf(rx) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 2.0) * STICK_LOOK_SPEED * delta
    if absf(ry) > STICK_DEADZONE:
        var dy := signf(ry) * pow((absf(ry) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 2.0) * STICK_LOOK_SPEED * delta
        pitch = clampf(pitch - dy, -1.45, 1.45)

    # Edge detection on the face buttons. DualSense: Cross jumps, Circle
    # dodges, Square punches, R1 web-zips.
    if _pressed_this_poll(JOY_BUTTON_A):
        _jump_pressed = true
    if _pressed_this_poll(JOY_BUTTON_B):
        _dodge_pressed = true
    if _pressed_this_poll(JOY_BUTTON_X):
        _punch_pressed = true
    if _pressed_this_poll(JOY_BUTTON_RIGHT_SHOULDER):
        _zip_pressed = true


func _pressed_this_poll(button: int) -> bool:
    var down := Input.is_joy_button_pressed(_device, button)
    var was: bool = _prev_buttons.get(button, false)
    _prev_buttons[button] = down
    return down and not was


# --- queries ---------------------------------------------------------------
# Web-shoot held: left mouse OR the gamepad's R2.
#
# This is a function deliberately, and in the browser build it was the single
# most important line in the project. It used to be a plain field that only
# poll_gamepad() ever assigned - and poll_gamepad() returns immediately when no
# gamepad is connected, so on mouse and keyboard it sat at its initial `false`
# forever and *the web never fired at all*. The game shipped unswingable
# because the tests only checked for errors and never asserted that pressing
# the button actually entered the swing state.
func is_web_down() -> bool:
    return _raw_mouse_down or _gp_web_value > TRIGGER_PRESS


func is_aim_down() -> bool:
    return _gp_aim_value > TRIGGER_PRESS


func is_sprint_down() -> bool:
    if Input.is_key_pressed(KEY_SHIFT):
        return true
    if _device >= 0:
        return Input.is_joy_button_pressed(_device, JOY_BUTTON_LEFT_SHOULDER) \
            or Input.is_joy_button_pressed(_device, JOY_BUTTON_LEFT_STICK)
    return false


# x = strafe (+right), z = forward (+forward). Matches the browser build's
# convention so every tuned constant transfers unchanged.
func movement_vector() -> Vector2:
    var x := 0.0
    var z := 0.0
    if Input.is_key_pressed(KEY_W): z += 1.0
    if Input.is_key_pressed(KEY_S): z -= 1.0
    if Input.is_key_pressed(KEY_D): x += 1.0
    if Input.is_key_pressed(KEY_A): x -= 1.0

    if _device >= 0:
        var lx := Input.get_joy_axis(_device, JOY_AXIS_LEFT_X)
        var ly := Input.get_joy_axis(_device, JOY_AXIS_LEFT_Y)
        if absf(lx) > STICK_DEADZONE:
            x += signf(lx) * (absf(lx) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
        if absf(ly) > STICK_DEADZONE:
            z -= signf(ly) * (absf(ly) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)

    return Vector2(clampf(x, -1.0, 1.0), clampf(z, -1.0, 1.0))


func consume_jump() -> bool:
    var v := _jump_pressed
    _jump_pressed = false
    return v


func consume_punch() -> bool:
    var v := _punch_pressed
    _punch_pressed = false
    return v


func consume_zip() -> bool:
    var v := _zip_pressed
    _zip_pressed = false
    return v


func consume_dodge() -> bool:
    var v := _dodge_pressed
    _dodge_pressed = false
    return v


func clear_presses() -> void:
    _jump_pressed = false
    _punch_pressed = false
    _zip_pressed = false
    _dodge_pressed = false


# --- haptics ---------------------------------------------------------------
func rumble(weak: float, strong: float, duration_ms: float) -> void:
    if _device < 0:
        return
    Input.start_joy_vibration(_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration_ms / 1000.0)


func stop_rumble() -> void:
    if _device >= 0:
        Input.stop_joy_vibration(_device)
