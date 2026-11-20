extends CanvasLayer
class_name HUD

# The HUD and menus are built in code rather than laid out in the scene file.
#
# That is a deliberate trade for this stage of the port: a UI built here is one
# source of truth that cannot drift out of sync with the code that drives it,
# and every anchor and offset is visible next to the thing it positions. Moving
# this into a .tscn and editing it visually is the obvious next step once the
# layout has settled - nothing here depends on it staying in code.

const PANEL_BG := Color(0.04, 0.05, 0.09, 0.93)
const ACCENT := Color("#ff3b4e")
const WEB_BLUE := Color("#6ea8ff")

var _game: Game

var _menu: Control
var _controls: Control
var _pause: Control
var _gameover: Control
var _play: Control

var _stat_height: Label
var _stat_speed: Label
var _health_fill: ColorRect
var _crosshair: Control
var _vignette: ColorRect
var _arrow: Label
var _prompt: Label
var _toast: Label
var _crime_status: Label
var _crime_count: Label
var _crime_bar: ColorRect
var _crime_bar_bg: Control
var _gameover_count: Label
var _tip: Label

var _toast_timer := 0.0
var _tip_timer := 0.0
var _seen_swing := false


func _ready() -> void:
    _game = get_parent() as Game
    _build_play()
    _build_menu()
    _build_controls()
    _build_pause()
    _build_gameover()


# --- helpers ---------------------------------------------------------------
func _label(text: String, size: int, colour: Color = Color.WHITE) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", colour)
    return l


func _button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(300, 46)
    b.add_theme_font_size_override("font_size", 18)
    return b


# A full-screen dim layer with a centred panel. Centred via a ScrollContainer
# so a panel taller than the window can still be reached: in the browser build
# the Controls screen grew past the viewport and its Back button became
# genuinely unclickable, with no way out but a reload.
func _screen(title: String) -> Array:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_STOP

    var dim := ColorRect.new()
    dim.color = Color(0.02, 0.02, 0.05, 0.82)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)

    var scroll := ScrollContainer.new()
    scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root.add_child(scroll)

    var centre := CenterContainer.new()
    centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
    centre.custom_minimum_size = Vector2(0, 600)
    scroll.add_child(centre)

    var panel := PanelContainer.new()
    var style := StyleBoxFlat.new()
    style.bg_color = PANEL_BG
    style.border_color = Color(1, 1, 1, 0.12)
    style.set_border_width_all(1)
    style.set_corner_radius_all(14)
    style.set_content_margin_all(32)
    panel.add_theme_stylebox_override("panel", style)
    centre.add_child(panel)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 14)
    panel.add_child(col)

    var heading := _label(title, 40)
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(heading)

    add_child(root)
    return [root, col]


# --- in-play HUD -----------------------------------------------------------
func _build_play() -> void:
    _play = Control.new()
    _play.set_anchors_preset(Control.PRESET_FULL_RECT)
    _play.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_play)

    # Danger vignette. A red frame at the edge of vision is the "spidey sense"
    # tell: it reads peripherally, without asking you to look away from where
    # you're flying.
    _vignette = ColorRect.new()
    _vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
    _vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var vig := Gradient.new()
    vig.set_color(0, Color(1, 0.1, 0.15, 0.0))
    vig.set_color(1, Color(1, 0.1, 0.15, 0.55))
    var vig_tex := GradientTexture2D.new()
    vig_tex.gradient = vig
    vig_tex.fill = GradientTexture2D.FILL_RADIAL
    vig_tex.fill_from = Vector2(0.5, 0.5)
    vig_tex.fill_to = Vector2(1.0, 0.5)
    var vig_rect := TextureRect.new()
    vig_rect.texture = vig_tex
    vig_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    vig_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    vig_rect.stretch_mode = TextureRect.STRETCH_SCALE
    vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _vignette.add_child(vig_rect)
    _vignette.color = Color(0, 0, 0, 0)
    _vignette.visible = false
    _play.add_child(_vignette)

    # Stats, bottom left.
    var stats := VBoxContainer.new()
    stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    stats.position = Vector2(26, -92)
    stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _play.add_child(stats)
    _stat_height = _label("0.0 m", 20, WEB_BLUE)
    _stat_speed = _label("0.0 m/s", 20, WEB_BLUE)
    stats.add_child(_stat_height)
    stats.add_child(_stat_speed)

    # Health, top left.
    var hp_bg := ColorRect.new()
    hp_bg.color = Color(1, 1, 1, 0.14)
    hp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
    hp_bg.position = Vector2(26, 26)
    hp_bg.size = Vector2(260, 14)
    _play.add_child(hp_bg)
    _health_fill = ColorRect.new()
    _health_fill.color = ACCENT
    _health_fill.position = Vector2.ZERO
    _health_fill.size = Vector2(260, 14)
    hp_bg.add_child(_health_fill)

    # Crimes stopped, top right.
    var crimes_box := VBoxContainer.new()
    crimes_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    crimes_box.position = Vector2(-240, 26)
    crimes_box.alignment = BoxContainer.ALIGNMENT_END
    _play.add_child(crimes_box)
    _crime_count = _label("Crimes stopped: 0", 18)
    _crime_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    crimes_box.add_child(_crime_count)
    _crime_status = _label("", 16, ACCENT)
    _crime_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    crimes_box.add_child(_crime_status)

    _crime_bar_bg = ColorRect.new()
    (_crime_bar_bg as ColorRect).color = Color(1, 1, 1, 0.16)
    _crime_bar_bg.custom_minimum_size = Vector2(200, 8)
    _crime_bar_bg.visible = false
    crimes_box.add_child(_crime_bar_bg)
    _crime_bar = ColorRect.new()
    _crime_bar.color = ACCENT
    _crime_bar.size = Vector2(200, 8)
    _crime_bar_bg.add_child(_crime_bar)

    # Crosshair.
    _crosshair = _label("+", 22, Color(1, 1, 1, 0.65))
    _crosshair.set_anchors_preset(Control.PRESET_CENTER)
    _crosshair.position = Vector2(-7, -16)
    _play.add_child(_crosshair)

    # Arrow pointing at the nearest danger. Rotated to the enemy's bearing
    # relative to where you are looking, so it stays correct as you turn.
    _arrow = _label("▲", 34, ACCENT)
    _arrow.set_anchors_preset(Control.PRESET_CENTER)
    _arrow.position = Vector2(-12, -140)
    _arrow.pivot_offset = Vector2(12, 150)
    _arrow.visible = false
    _play.add_child(_arrow)

    # Contextual prompt, so the moves you can only use *right now* are
    # discoverable without opening the controls screen.
    _prompt = _label("", 17, Color(1, 1, 1, 0.78))
    _prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _prompt.position = Vector2(-300, -74)
    _prompt.custom_minimum_size = Vector2(600, 0)
    _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _play.add_child(_prompt)

    _toast = _label("", 36, Color("#ffd166"))
    _toast.set_anchors_preset(Control.PRESET_CENTER)
    _toast.position = Vector2(-240, -90)
    _toast.custom_minimum_size = Vector2(480, 0)
    _toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast.visible = false
    _play.add_child(_toast)

    _tip = _label("", 17, Color(1, 1, 1, 0.8))
    _tip.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _tip.position = Vector2(-340, 70)
    _tip.custom_minimum_size = Vector2(680, 0)
    _tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _tip.visible = false
    _play.add_child(_tip)

    _play.visible = false


func _build_menu() -> void:
    var made := _screen("WEB RUSH")
    _menu = made[0]
    var col: VBoxContainer = made[1]

    var sub := _label("Swing, crawl, dive, and knock over some thugs.", 18, Color(1, 1, 1, 0.7))
    sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(sub)

    var play := _button("Play")
    play.pressed.connect(func() -> void: _game.start())
    col.add_child(play)

    var controls := _button("Controls")
    controls.pressed.connect(func() -> void:
        _menu.visible = false
        _controls.visible = true)
    col.add_child(controls)


func _build_controls() -> void:
    var made := _screen("Controls")
    _controls = made[0]
    var col: VBoxContainer = made[1]
    _controls.visible = false

    var rows := [
        ["W A S D", "Left stick", "Run"],
        ["Mouse", "Right stick", "Look / aim"],
        ["Left click (hold)", "R2 (hold)", "Shoot a web and swing"],
        ["W while swinging", "Left stick up", "Pump - thrust along your aim, and reel in"],
        ["A / D while swinging", "Left stick", "Steer the arc"],
        ["Space while swinging", "Cross", "Release - flat and fast is a PERFECT RELEASE"],
        ["S in the air", "Left stick down", "Dive - trade height for speed"],
        ["Touch a wall", "-", "Stick to it: W/S climb, A/D crawl, Space jumps off"],
        ["E", "Square", "Punch"],
        ["Q", "R1", "Web-zip to your aim point"],
        ["Right click (hold)", "L2 (hold)", "Aim (soft lock-on, narrowed camera)"],
        ["C", "Circle", "Dodge - time it to your spidey sense"],
        ["Shift", "L1 / L3", "Sprint"],
        ["Esc", "Options", "Pause"],
    ]

    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 26)
    grid.add_theme_constant_override("v_separation", 8)
    col.add_child(grid)
    for row: Array in rows:
        grid.add_child(_label(row[0], 15, WEB_BLUE))
        grid.add_child(_label(row[1], 15, Color(1, 1, 1, 0.55)))
        grid.add_child(_label(row[2], 15))

    var note := _label(
        "A DualSense gets rumble through Godot's gamepad support. The adaptive\n" +
        "triggers do not - see the README; that needs a GDExtension.",
        14, Color(1, 1, 1, 0.5))
    col.add_child(note)

    var back := _button("Back")
    back.pressed.connect(func() -> void:
        _controls.visible = false
        _menu.visible = true)
    col.add_child(back)


func _build_pause() -> void:
    var made := _screen("Paused")
    _pause = made[0]
    var col: VBoxContainer = made[1]
    _pause.visible = false

    var resume := _button("Resume")
    resume.pressed.connect(func() -> void: _game.resume())
    col.add_child(resume)

    var quit := _button("Quit to menu")
    quit.pressed.connect(func() -> void: _game.quit_to_menu())
    col.add_child(quit)


func _build_gameover() -> void:
    var made := _screen("You went down")
    _gameover = made[0]
    var col: VBoxContainer = made[1]
    _gameover.visible = false

    _gameover_count = _label("Crimes stopped: 0", 20, Color("#ffd166"))
    _gameover_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(_gameover_count)

    var retry := _button("Try again")
    retry.pressed.connect(func() -> void: _game.restart())
    col.add_child(retry)

    var quit := _button("Quit to menu")
    quit.pressed.connect(func() -> void: _game.quit_to_menu())
    col.add_child(quit)


# --- mode switching --------------------------------------------------------
func _hide_all() -> void:
    _menu.visible = false
    _controls.visible = false
    _pause.visible = false
    _gameover.visible = false
    _play.visible = false


func show_menu() -> void:
    _hide_all()
    _menu.visible = true
    _crime_count.text = "Crimes stopped: 0"
    _seen_swing = false


func show_playing() -> void:
    _hide_all()
    _play.visible = true


func show_pause() -> void:
    _play.visible = true
    _pause.visible = true


func show_gameover(crimes_stopped: int) -> void:
    _hide_all()
    _play.visible = true
    _gameover.visible = true
    _gameover_count.text = "Crimes stopped: %d" % crimes_stopped


func flash(text: String, is_release: bool) -> void:
    _toast.text = text
    _toast.add_theme_color_override("font_color", Color("#9be7ff") if is_release else Color("#ffd166"))
    _toast.visible = true
    _toast_timer = 0.9


func crime_stopped_toast() -> void:
    flash("CRIME STOPPED", false)


func _process(dt: float) -> void:
    if _toast_timer > 0.0:
        _toast_timer -= dt
        if _toast_timer <= 0.0:
            _toast.visible = false
    if _tip_timer > 0.0:
        _tip_timer -= dt
        if _tip_timer <= 0.0:
            _tip.visible = false


func update_hud(s: Dictionary, crime: Dictionary) -> void:
    _stat_height.text = "%.1f m" % s["height"]
    _stat_speed.text = "%.1f m/s" % s["speed"]

    var pct: float = clampf(s["health"] / s["max_health"], 0.0, 1.0)
    _health_fill.size.x = 260.0 * pct
    _health_fill.color = Color("#ff8a3b") if pct <= 0.3 else ACCENT

    _crosshair.modulate = Color(1, 0.35, 0.4) if s["aim_locked"] else Color(1, 1, 1, 0.9 if s["aiming"] else 0.5)

    var spidey: Variant = crime["spidey_sense"]
    _vignette.visible = spidey != null
    if spidey != null:
        _arrow.visible = true
        # The stored bearing is absolute; subtracting the camera yaw turns it
        # into a direction on screen.
        _arrow.rotation = (spidey as Dictionary)["dir_yaw"] - s["yaw"]
    else:
        _arrow.visible = false

    if s["on_wall"]:
        _prompt.text = "W/S climb  -  A/D crawl  -  Space to jump off"
    elif s["diving"]:
        _prompt.text = "Diving - hold Left Click to swing out of it"
    elif s["state"] == "swing":
        _prompt.text = "Space at the bottom of the arc = perfect release"
    else:
        _prompt.text = ""

    if s["state"] == "swing" and not _seen_swing:
        _seen_swing = true
        _tip.text = "Nice. W pumps the swing, Space launches you out of it, S in the air dives."
        _tip.visible = true
        _tip_timer = 6.0

    _crime_count.text = "Crimes stopped: %d" % crime["stopped_count"]
    if crime["engaged"] and crime["enemy_max_health"] > 0.0:
        _crime_bar_bg.visible = true
        _crime_bar.size.x = 200.0 * (crime["enemy_health"] / crime["enemy_max_health"])
        _crime_status.text = "Press E / Square to punch"
    else:
        _crime_bar_bg.visible = false
        var nd: Variant = crime["nearest_dist"]
        if nd != null and (nd as float) < 400.0:
            _crime_status.text = "Crime in progress - %dm away" % int(nd as float)
        else:
            _crime_status.text = ""
