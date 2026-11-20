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

var _cells: Dictionary = {}      # Vector2i -> {"node": Node3D or null, "box": Dictionary or null}
var _facade: ImageTexture
var _ground: StaticBody3D
var _building_mesh: BoxMesh


func _ready() -> void:
    _facade = _make_facade_texture()
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

    var body := StaticBody3D.new()
    body.collision_layer = WORLD_LAYER
    body.position = Vector3(cx, height / 2.0, cz)

    var mesh := MeshInstance3D.new()
    var box_mesh := BoxMesh.new()
    box_mesh.size = Vector3(size_x, height, size_z)
    mesh.mesh = box_mesh

    var mat := StandardMaterial3D.new()
    var tint: float = 0.8 + hash2(ix, iz, 9) * 0.5
    mat.albedo_color = Color("#3d4a6b") * tint
    mat.roughness = 0.85
    mat.metallic = 0.05
    mat.albedo_texture = _facade
    mat.emission_enabled = true
    mat.emission = Color.WHITE
    mat.emission_energy_multiplier = 0.85
    mat.emission_texture = _facade
    mat.uv1_scale = Vector3(maxf(1.0, roundf(size_x / 7.0)), maxf(2.0, roundf(height / 7.0)), 1.0)
    mesh.material_override = mat
    body.add_child(mesh)

    var shape := CollisionShape3D.new()
    var col_box := BoxShape3D.new()
    col_box.size = Vector3(size_x, height, size_z)
    shape.shape = col_box
    body.add_child(shape)

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
