extends Node3D
class_name City

# Procedural city, streamed around the player in fixed cells so it can run
# forever in any direction without ever building the whole world. Every cell's
# contents come from a hash of its grid coordinates, so a cell rebuilt after
# you wander away and come back is identical - no popping into a different
# skyline than the one you left.

# Street width decides whether the city is swingable at all. At a 42m grid with
# 9m margins the avenues were ~18m across - narrower than a single swing arc,
# so every web attach ended in a facade regardless of how good the rope physics
# was. ~40m canyons give a 30m rope somewhere to go. Measured: widening the
# grid took chained traversal from 50m to ~420m per 15 seconds.
const CELL := 84.0
const VIEW_CELLS := 6
const BUILDING_MARGIN := 22.0
const MIN_HEIGHT := 18.0
const MAX_HEIGHT := 135.0

# Collision layer 1 is the world. Web raycasts, the camera's occlusion probe
# and the aim ray all query this layer and nothing else, so enemies and the
# player can never be mistaken for a building.
const WORLD_LAYER := 1

# How many buckets the per-building tint and window warmth are quantised into.
# Shared materials only help if many buildings land on the same one.
const TINT_STEPS := 5
const WARM_STEPS := 4

var _cells: Dictionary = {}      # Vector2i -> {"node": Node3D or null, "box": Dictionary or null}
var _facade: ImageTexture
var _ground: StaticBody3D
var _unit_box: BoxMesh
var _cylinder: CylinderMesh
var _facade_mats: Dictionary = {}     # "tint:warm:uvx:uvy" -> StandardMaterial3D
var _prop_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D


func _ready() -> void:
    _facade = _make_facade_texture()
    _init_shared()
    _build_ground()
    update_streaming(0.0, 0.0)


# --- deterministic hash ----------------------------------------------------
# Masked to 32 bits at every step so the result is identical on every platform.
# GDScript ints are 64-bit signed, so without the masks the multiplies would
# run off into values the browser build's 32-bit arithmetic never produced.
static func hash2(ix: int, iz: int, salt: int = 0) -> float:
    var h: int = ix * 374761393 + iz * 668265263 + salt * 1442695040
    h = h & 0xFFFFFFFF
    h = (h ^ (h >> 13)) & 0xFFFFFFFF
    h = (h * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 16)) & 0xFFFFFFFF
    return float(h) / 4294967296.0


# --- look ------------------------------------------------------------------
# Tiled facade: rows of small windows, most dark, some lit warm. One texture
# shared by every building, with per-building UV scaling making them differ.
#
# The same texture drives albedo and emission. Windows are the only bright
# pixels in it, so as an emission map they glow on their own - which is the
# entire look of a night skyline. Lit purely by lamps, every building reads as
# a black silhouette.
func _make_facade_texture() -> ImageTexture:
    var size := 128
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    img.fill(Color("#0b0d18"))

    var cols := 8
    var rows := 10
    var cw := size / cols
    var ch := size / rows
    var lit := [Color("#ffd9a0"), Color("#ffe9c4"), Color("#cfe0ff"), Color("#fff3d0")]

    for r in range(rows):
        for c in range(cols):
            var on := hash2(c + 1, r + 1, 7) > 0.62
            var col: Color = lit[int(hash2(c, r, 13) * lit.size()) % lit.size()] if on else Color("#141826")
            for py in range(r * ch + 2, (r + 1) * ch - 2):
                for px in range(c * cw + 2, (c + 1) * cw - 2):
                    if px >= 0 and px < size and py >= 0 and py < size:
                        img.set_pixel(px, py, col)

    return ImageTexture.create_from_image(img)


func _build_ground() -> void:
    _ground = StaticBody3D.new()
    _ground.collision_layer = WORLD_LAYER
    _ground.name = "Ground"

    var mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(2400, 2400)
    mesh.mesh = plane
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("#4a4256")
    mat.roughness = 0.95
    mat.metallic = 0.0
    mesh.material_override = mat
    _ground.add_child(mesh)

    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    # A thin slab rather than a WorldBoundaryShape3D: an infinite plane would
    # also catch rays cast from above a rooftop and report the street as the
    # first hit.
    box.size = Vector3(2400, 2, 2400)
    shape.shape = box
    shape.position = Vector3(0, -1, 0)
    _ground.add_child(shape)

    add_child(_ground)


# --- shared render resources ----------------------------------------------
# One unit cube scaled per instance, plus a small cache of facade materials.
#
# The first version built a fresh BoxMesh and a fresh StandardMaterial3D for
# every building, so at 13x13 streamed cells roughly 170 unique meshes and 170
# unique materials were resident at all times - each its own shader setup, none
# of them able to batch with anything. Bucketing the tint, the window warmth
# and the UV tiling into a cache collapses that to a few dozen shared
# materials, which is what makes the rooftop clutter below affordable.
func _init_shared() -> void:
    _unit_box = BoxMesh.new()
    _unit_box.size = Vector3.ONE

    _cylinder = CylinderMesh.new()
    _cylinder.top_radius = 0.5
    _cylinder.bottom_radius = 0.5
    _cylinder.height = 1.0
    _cylinder.radial_segments = 12

    # Unlit concrete and metal. Rooftop plant is never the thing you look at;
    # it just has to break the silhouette.
    _prop_mat = StandardMaterial3D.new()
    _prop_mat.albedo_color = Color("#2d2f3a")
    _prop_mat.roughness = 0.9
    _prop_mat.metallic = 0.1

    _lamp_mat = StandardMaterial3D.new()
    _lamp_mat.albedo_color = Color("#ffcf9a")
    _lamp_mat.emission_enabled = true
    _lamp_mat.emission = Color("#ffb860")
    _lamp_mat.emission_energy_multiplier = 3.2

    # Aviation warning lights. Deliberately over-bright: with glow on they
    # bloom into the fog and give the tall buildings a readable top edge from
    # right across the city, which is exactly what you need when you are
    # picking a web anchor at 60 m/s.
    _beacon_mat = StandardMaterial3D.new()
    _beacon_mat.albedo_color = Color("#ff4040")
    _beacon_mat.emission_enabled = true
    _beacon_mat.emission = Color("#ff2020")
    _beacon_mat.emission_energy_multiplier = 6.0


func _facade_material(tint_step: int, warm_step: int, uv_x: int, uv_y: int) -> StandardMaterial3D:
    var key := "%d:%d:%d:%d" % [tint_step, warm_step, uv_x, uv_y]
    if _facade_mats.has(key):
        return _facade_mats[key]

    var mat := StandardMaterial3D.new()
    var tint := 0.8 + float(tint_step) / float(TINT_STEPS - 1) * 0.5
    var warm := float(warm_step) / float(WARM_STEPS - 1)

    mat.albedo_color = Color("#3d4a6b") * tint
    mat.roughness = 0.85
    mat.metallic = 0.05
    mat.albedo_texture = _facade
    # The same texture drives albedo and emission - windows are the only bright
    # pixels in it, so as an emission map they light themselves. Varying the
    # emission colour per building is what stops a street reading as one
    # uniform sheet of glass: cool offices beside warm apartments is most of
    # what makes a real skyline look like many separate buildings.
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.95 - warm * 0.2, 0.9 - warm * 0.45)
    mat.emission_energy_multiplier = 0.7 + warm * 0.35
    mat.emission_texture = _facade
    mat.uv1_scale = Vector3(float(uv_x), float(uv_y), 1.0)

    _facade_mats[key] = mat
    return mat


func _prop(body: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale: Vector3) -> void:
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = mat
    mi.position = pos
    mi.scale = scale
    body.add_child(mi)


# Rooftop clutter. A city of bare extruded boxes reads as placeholder geometry
# however good the lighting is; water towers and vent housings are what make a
# roof look like a place rather than the top of a cuboid. It matters more here
# than in most games because you spend the whole time above the roofline.
#
# These are visual only. The collision model is still one box per building, so
# you can walk through a water tower - giving each prop a body would mean
# teaching resolve_horizontal_collision about several boxes per cell, which is
# not worth it for decoration you are near for a couple of seconds.
func _add_roof_detail(body: Node3D, ix: int, iz: int, height: float, sx: float, sz: float) -> void:
    var inset_x := maxf(1.0, sx / 2.0 - 5.0)
    var inset_z := maxf(1.0, sz / 2.0 - 5.0)

    if hash2(ix, iz, 21) > 0.55:
        var wx := (hash2(ix, iz, 22) - 0.5) * 2.0 * inset_x
        var wz := (hash2(ix, iz, 23) - 0.5) * 2.0 * inset_z
        _prop(body, _unit_box, _prop_mat, Vector3(wx, height + 0.6, wz), Vector3(4.4, 1.2, 4.4))
        _prop(body, _cylinder, _prop_mat, Vector3(wx, height + 3.6, wz), Vector3(3.6, 4.8, 3.6))

    if hash2(ix, iz, 24) > 0.4:
        var ax := (hash2(ix, iz, 25) - 0.5) * 2.0 * inset_x
        var az := (hash2(ix, iz, 26) - 0.5) * 2.0 * inset_z
        _prop(body, _unit_box, _prop_mat, Vector3(ax, height + 0.8, az), Vector3(5.2, 1.6, 3.0))

    if height > 85.0 and hash2(ix, iz, 27) > 0.45:
        _prop(body, _unit_box, _prop_mat, Vector3(0, height + 7.0, 0), Vector3(0.35, 14.0, 0.35))
        _prop(body, _unit_box, _beacon_mat, Vector3(0, height + 14.2, 0), Vector3(0.7, 0.7, 0.7))

    # Corner beacons on anything tall enough to be a hazard. Flush to the roof
    # so there is nothing to clip through when you land on one.
    if height > 60.0:
        var bx := sx / 2.0 - 1.2
        var bz := sz / 2.0 - 1.2
        _prop(body, _unit_box, _beacon_mat, Vector3(bx, height + 0.15, bz), Vector3(0.8, 0.3, 0.8))
        _prop(body, _unit_box, _beacon_mat, Vector3(-bx, height + 0.15, -bz), Vector3(0.8, 0.3, 0.8))


# Street lamps along the two avenues this cell fronts onto. Emissive geometry
# with no OmniLight behind it: with glow enabled the heads bloom convincingly,
# and a real light per lamp across 169 streamed cells would be hundreds of
# shadowless point lights for scenery you mostly fly over.
func _add_street_lamps(body: Node3D, ix: int, iz: int) -> void:
    var edge := CELL / 2.0 - 4.0
    var spots := []
    if hash2(ix, iz, 31) > 0.35:
        spots.append(Vector3(-edge, 0, 0))
    if hash2(ix, iz, 32) > 0.35:
        spots.append(Vector3(0, 0, -edge))
    for spot: Vector3 in spots:
        _prop(body, _unit_box, _prop_mat, spot + Vector3(0, 3.5, 0), Vector3(0.28, 7.0, 0.28))
        _prop(body, _unit_box, _lamp_mat, spot + Vector3(0, 7.1, 0), Vector3(1.4, 0.3, 0.7))


func _make_building(ix: int, iz: int) -> Dictionary:
    if ix == 0 and iz == 0:
        return {}                              # plaza at spawn
    if hash2(ix, iz, 3) < 0.12:
        return {}                              # occasional open lot

    var height: float = MIN_HEIGHT + pow(hash2(ix, iz, 1), 2.2) * (MAX_HEIGHT - MIN_HEIGHT)
    var footprint := CELL - BUILDING_MARGIN * 2.0
    var size_x: float = footprint * (0.7 + hash2(ix, iz, 4) * 0.3)
    var size_z: float = footprint * (0.7 + hash2(ix, iz, 5) * 0.3)
    var cx: float = ix * CELL + (hash2(ix, iz, 6) - 0.5) * 3.0
    var cz: float = iz * CELL + (hash2(ix, iz, 8) - 0.5) * 3.0

    # The body sits at street level rather than at its own centre, so rooftop
    # props can be parented at y = height directly, and the non-uniform scale
    # on the facade mesh cannot leak down into them.
    var body := StaticBody3D.new()
    body.collision_layer = WORLD_LAYER
    body.position = Vector3(cx, 0.0, cz)

    var mesh := MeshInstance3D.new()
    mesh.mesh = _unit_box
    mesh.position = Vector3(0, height / 2.0, 0)
    mesh.scale = Vector3(size_x, height, size_z)
    mesh.material_override = _facade_material(
        int(hash2(ix, iz, 9) * TINT_STEPS) % TINT_STEPS,
        int(hash2(ix, iz, 11) * WARM_STEPS) % WARM_STEPS,
        int(maxf(1.0, roundf(size_x / 7.0))),
        int(maxf(2.0, roundf(height / 7.0))))
    body.add_child(mesh)

    var shape := CollisionShape3D.new()
    var col_box := BoxShape3D.new()
    col_box.size = Vector3(size_x, height, size_z)
    shape.shape = col_box
    shape.position = Vector3(0, height / 2.0, 0)
    body.add_child(shape)

    _add_roof_detail(body, ix, iz, height, size_x, size_z)
    _add_street_lamps(body, ix, iz)

    # The web-shoot ray needs the roof height of whatever it hit, so it can put
    # the anchor above the roofline instead of on the facade. Stashing it on
    # the body means the raycast result carries it directly.
    body.set_meta("roof_height", height)
    add_child(body)

    return {
        "node": body,
        "box": {
            "min_x": cx - size_x / 2.0,
            "max_x": cx + size_x / 2.0,
            "min_z": cz - size_z / 2.0,
            "max_z": cz + size_z / 2.0,
            "height": height,
        },
    }


# --- streaming -------------------------------------------------------------
func update_streaming(px: float, pz: float) -> void:
    var cx := int(round(px / CELL))
    var cz := int(round(pz / CELL))
    _ground.position = Vector3(cx * CELL, 0, cz * CELL)

    for ix in range(cx - VIEW_CELLS, cx + VIEW_CELLS + 1):
        for iz in range(cz - VIEW_CELLS, cz + VIEW_CELLS + 1):
            var key := Vector2i(ix, iz)
            if _cells.has(key):
                continue
            var made := _make_building(ix, iz)
            # Empty cells are remembered too, so a plaza isn't re-rolled and
            # re-tested every frame you stand next to it.
            _cells[key] = made if not made.is_empty() else {"node": null, "box": null}

    for key: Vector2i in _cells.keys():
        if absi(key.x - cx) > VIEW_CELLS + 1 or absi(key.y - cz) > VIEW_CELLS + 1:
            var cell: Dictionary = _cells[key]
            if cell.get("node") != null:
                (cell["node"] as Node3D).queue_free()
            _cells.erase(key)


func _box_at(x: float, z: float) -> Variant:
    var key := Vector2i(int(round(x / CELL)), int(round(z / CELL)))
    var cell: Variant = _cells.get(key)
    if cell == null:
        return null
    return (cell as Dictionary).get("box")


# Boxes in the 3x3 cell neighbourhood of a point.
func _nearby_boxes(x: float, z: float) -> Array:
    var out: Array = []
    var ix := int(round(x / CELL))
    var iz := int(round(z / CELL))
    for dx in range(-1, 2):
        for dz in range(-1, 2):
            var cell: Variant = _cells.get(Vector2i(ix + dx, iz + dz))
            if cell == null:
                continue
            var box: Variant = (cell as Dictionary).get("box")
            if box != null:
                out.append(box)
    return out


func ground_height_at(x: float, z: float) -> float:
    var box: Variant = _box_at(x, z)
    if box == null:
        return 0.0
    var b: Dictionary = box
    if x >= b["min_x"] and x <= b["max_x"] and z >= b["min_z"] and z <= b["max_z"]:
        return b["height"]
    return 0.0


# Nearest climbable wall surface within `reach` of a point, or an empty
# dictionary. Returns the outward face normal, the point on the face, and the
# building's roof height so the climber knows where the wall ends.
#
# Only the four vertical faces count: the top is a roof you walk on, and a
# point above the roofline has no wall beside it at all.
func wall_probe(x: float, y: float, z: float, reach: float) -> Dictionary:
    var best: Dictionary = {}
    for box: Dictionary in _nearby_boxes(x, z):
        if y > box["height"] - 0.2 or y < 0.0:
            continue
        var in_z: bool = z >= box["min_z"] and z <= box["max_z"]
        var in_x: bool = x >= box["min_x"] and x <= box["max_x"]
        var faces: Array = []
        if in_z:
            faces.append({"d": absf(x - box["min_x"]), "n": Vector3(-1, 0, 0), "p": Vector3(box["min_x"], y, z)})
            faces.append({"d": absf(x - box["max_x"]), "n": Vector3(1, 0, 0), "p": Vector3(box["max_x"], y, z)})
        if in_x:
            faces.append({"d": absf(z - box["min_z"]), "n": Vector3(0, 0, -1), "p": Vector3(x, y, box["min_z"])})
            faces.append({"d": absf(z - box["max_z"]), "n": Vector3(0, 0, 1), "p": Vector3(x, y, box["max_z"])})
        if faces.is_empty():
            continue

        var face: Dictionary = faces[0]
        for f: Dictionary in faces:
            if f["d"] < face["d"]:
                face = f
        if face["d"] > reach:
            continue
        if best.is_empty() or face["d"] < best["distance"]:
            best = {
                "distance": face["d"],
                "normal": face["n"],
                "point": face["p"],
                "top": box["height"],
            }
    return best


# Push a point back out of any building footprint it has ended up inside.
# `ref_y` is the height the mover was at *before* this step: buildings shorter
# than that are roofs underfoot, not walls in front, and must not shove the
# player sideways off their own rooftop.
#
# Returns the displacement applied. The caller needs it to cancel the velocity
# heading into the wall - repositioning alone leaves the mover grinding along
# the facade at full speed, still "moving" as far as the physics is concerned
# while going nowhere. That bug pinned the player at 49 m/s with zero progress.
func resolve_horizontal_collision(pos: Vector3, radius: float, ref_y: float) -> Dictionary:
    var push := Vector3.ZERO
    var p := pos
    for box: Dictionary in _nearby_boxes(p.x, p.z):
        if box["height"] <= ref_y + 0.05:
            continue
        var min_x: float = box["min_x"] - radius
        var max_x: float = box["max_x"] + radius
        var min_z: float = box["min_z"] - radius
        var max_z: float = box["max_z"] + radius
        if p.x < min_x or p.x > max_x or p.z < min_z or p.z > max_z:
            continue

        # Leave by the nearest face.
        var opts := [
            {"d": p.x - min_x, "axis": 0, "to": min_x},
            {"d": max_x - p.x, "axis": 0, "to": max_x},
            {"d": p.z - min_z, "axis": 2, "to": min_z},
            {"d": max_z - p.z, "axis": 2, "to": max_z},
        ]
        var best: Dictionary = opts[0]
        for o: Dictionary in opts:
            if o["d"] < best["d"]:
                best = o
        if best["axis"] == 0:
            push.x += best["to"] - p.x
            p.x = best["to"]
        else:
            push.z += best["to"] - p.z
            p.z = best["to"]

    return {"position": p, "push": push}


func random_spawn_point(px: float, pz: float, min_dist: float, max_dist: float) -> Variant:
    for attempt in range(24):
        var angle := randf() * TAU
        var dist := min_dist + randf() * (max_dist - min_dist)
        var x := px + cos(angle) * dist
        var z := pz + sin(angle) * dist
        var box: Variant = _box_at(x, z)
        if box != null and attempt < 18:
            var b: Dictionary = box
            return Vector3((b["min_x"] + b["max_x"]) / 2.0, b["height"], (b["min_z"] + b["max_z"]) / 2.0)
        if box == null:
            return Vector3(x, 0, z)
    return null
