class_name GrassSystem
extends Node3D

const CHUNK_SIZE: float = 16.0
const DENSITY_RES: int = 128
const MAX_CHUNK_REBUILDS_PER_APPLY: int = 24
const MAX_VISIBLE_REBUILDS_PER_SETTING_CHANGE: int = 28

@export var map_size: float = 256.0
@export var blades_per_chunk: int = 420
@export var density_scale: float = 2.8
@export var lod_distance: float = 72.0
@export var wind_strength: float = 0.5
@export var wind_speed: float = 1.0
@export var wind_direction_deg: float = 35.0
@export var grass_height: float = 0.65
@export var base_color: Color = Color(0.12, 0.22, 0.10, 1.0)
@export var tip_color: Color = Color(0.40, 0.49, 0.28, 1.0)

var _density_image: Image = null
var _terrain: Node = null
var _camera: Camera3D = null
var _chunks: Dictionary = {}
var _shader_mat: ShaderMaterial = null
var _quad_mesh: QuadMesh = null
var _last_cam_chunk: Vector2i = Vector2i(-9999, -9999)

const _SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wind_direction_deg : hint_range(0.0, 359.0) = 35.0;
uniform float grass_height : hint_range(0.1, 3.0) = 0.65;
uniform vec3 base_color : source_color;
uniform vec3 tip_color : source_color;

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

mat3 rot_y(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat3(vec3(c, 0.0, s), vec3(0.0, 1.0, 0.0), vec3(-s, 0.0, c));
}

mat3 rot_axis(vec3 axis, float a) {
    axis = normalize(axis);
    float s = sin(a);
    float c = cos(a);
    float oc = 1.0 - c;
    return mat3(
        vec3(
            oc * axis.x * axis.x + c,
            oc * axis.x * axis.y - axis.z * s,
            oc * axis.z * axis.x + axis.y * s
        ),
        vec3(
            oc * axis.x * axis.y + axis.z * s,
            oc * axis.y * axis.y + c,
            oc * axis.y * axis.z - axis.x * s
        ),
        vec3(
            oc * axis.z * axis.x - axis.y * s,
            oc * axis.y * axis.z + axis.x * s,
            oc * axis.z * axis.z + c
        )
    );
}

void vertex() {
    VERTEX.y += 0.5;
    float t = clamp(VERTEX.y, 0.0, 1.0);
    float t2 = t * t;

    vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float r0 = hash2(root.xz * 0.1371);
    float r1 = hash2(root.zx * 0.0894 + vec2(0.17, 0.41));
    float r2 = hash2(root.xz * 0.0619 + vec2(0.83, 0.27));

    float h_factor = mix(0.35, 1.0, hash2(root.zx * 0.053 + vec2(0.59, 0.21)));
    float blade_h = grass_height * h_factor;
    float width = mix(0.042, 0.068, r0);
    VERTEX.y *= blade_h;
    VERTEX.x *= width * (1.0 - t * 0.80);

    float base_rot = r0 * TAU;
    float stiffness = mix(0.75, 1.20, hash2(root.xz * 0.079 + vec2(0.24, 0.88)));
    float phase = hash2(root.xz * 0.101 + vec2(0.63, 0.14)) * TAU;

    float wind_angle = radians(wind_direction_deg);
    vec2 main_dir = vec2(cos(wind_angle), sin(wind_angle));

    float g1 = sin(TIME * wind_speed * 0.90 + dot(root.xz, main_dir * 0.090) + phase);
    float g2 = sin(TIME * wind_speed * 0.42 + dot(root.xz, main_dir * 0.031) + phase * 0.37);
    float main_amp = (0.35 + 0.65 * abs(g1)) * (0.78 + 0.22 * g2);
    vec2 main_vec = main_dir * main_amp * wind_strength;

    vec2 rand_dir = normalize(vec2(cos(phase * 1.13 + r1 * TAU), sin(phase * 0.87 + r2 * TAU)));
    float independent_wave = sin(TIME * wind_speed * 1.65 + dot(root.xz, rand_dir * 0.18) + phase * 2.10);
    vec2 independent_vec = rand_dir * independent_wave * wind_strength * 0.35;

    float independent_mix = step(0.95, hash2(root.xz * 0.043 + vec2(0.31, 0.73)));
    vec2 wind_vec = mix(main_vec, main_vec * 0.65 + independent_vec, independent_mix);
    wind_vec += vec2(
        sin(TIME * wind_speed * 0.55 + root.x * 0.11 + phase),
        cos(TIME * wind_speed * 0.49 + root.z * 0.10 + phase)
    ) * (wind_strength * 0.06);

    float droop = mix(0.04, 0.16, r2) * t2;
    float bend = length(wind_vec) * t2 * (0.75 / stiffness);
    vec3 bend_axis = vec3(wind_vec.y, 0.0, -wind_vec.x);
    if (dot(bend_axis, bend_axis) < 0.00001) {
        bend_axis = vec3(1.0, 0.0, 0.0);
    }

    float steer = (wind_vec.x + wind_vec.y) * 0.15 * t2;
    mat3 m = rot_axis(bend_axis, -(droop + bend)) * rot_y(base_rot + steer);
    VERTEX = m * VERTEX;
    NORMAL = m * NORMAL;
}

void fragment() {
    float t = 1.0 - UV.y;
    float t2 = t * t;

    vec3 col = mix(base_color, tip_color, t2);
    float ao = mix(0.22, 1.0, t2);
    float tonal = floor(t2 * 3.0 + 0.5) / 3.0;
    col *= mix(0.72, 1.08, tonal) * ao;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, 0.78);

    ALBEDO = col;
    ROUGHNESS = mix(0.96, 0.62, t);
    SPECULAR = 0.0;
}
"""

func initialize(terrain: Node, cam: Camera3D, msize: float) -> void:
    map_size = msize
    _terrain = terrain
    _camera = cam
    _density_image = Image.create(DENSITY_RES, DENSITY_RES, false, Image.FORMAT_RF)
    _density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
    _build_quad_mesh()
    _build_shader_material()
    set_process(true)

func apply_brush(mode: String, world_pos: Vector3, radius: float, strength: float) -> void:
    if _density_image == null:
        return

    var uv: Vector2 = _world_to_density_uv(world_pos.x, world_pos.z)
    var res: float = float(DENSITY_RES)
    var cx: int = int(uv.x * res)
    var cy: int = int(uv.y * res)
    var rpx: float = maxf(radius / map_size * res, 1.5)
    var rsq: float = rpx * rpx
    var is_erase: bool = (mode == "grasserase")

    var dirty_chunks: Dictionary = {}

    for py in range(max(0, int(cy - rpx) - 1), min(DENSITY_RES, int(cy + rpx) + 2)):
        for px in range(max(0, int(cx - rpx) - 1), min(DENSITY_RES, int(cx + rpx) + 2)):
            var ddx: float = float(px - cx)
            var ddy: float = float(py - cy)
            if ddx * ddx + ddy * ddy > rsq:
                continue

            var t: float = 1.0 - sqrt(ddx * ddx + ddy * ddy) / rpx
            var falloff: float = t * t * (3.0 - 2.0 * t)
            var cur: float = _density_image.get_pixel(px, py).r
            var nxt: float = cur

            if is_erase:
                nxt = cur * (1.0 - falloff * strength * 2.10)
            else:
                # Bias toward full painted swathes quickly so one pass feels satisfying.
                nxt = cur + (1.0 - cur) * falloff * strength * 2.65
                nxt = maxf(nxt, falloff * (0.36 + 0.34 * strength))

            nxt = clampf(nxt, 0.0, 1.0)
            if absf(nxt - cur) > 0.0001:
                _density_image.set_pixel(px, py, Color(nxt, 0.0, 0.0, 1.0))
                var wx: float = _density_px_to_world_x(float(px) / res)
                var wz: float = _density_px_to_world_z(float(py) / res)
                dirty_chunks[_world_to_chunk(wx, wz)] = true

    var rebuilt: int = 0
    for key: Variant in dirty_chunks:
        _rebuild_chunk(key as Vector2i)
        rebuilt += 1
        if rebuilt >= MAX_CHUNK_REBUILDS_PER_APPLY:
            break

func set_density_scale(v: float) -> void:
    density_scale = clampf(v, 0.25, 4.0)
    _rebuild_visible_chunks(MAX_VISIBLE_REBUILDS_PER_SETTING_CHANGE)

func set_wind_strength(v: float) -> void:
    wind_strength = v
    if _shader_mat != null:
        _shader_mat.set_shader_parameter("wind_strength", v)

func set_wind_speed(v: float) -> void:
    wind_speed = v
    if _shader_mat != null:
        _shader_mat.set_shader_parameter("wind_speed", v)

func set_wind_direction_deg(v: float) -> void:
    wind_direction_deg = fposmod(v, 360.0)
    if _shader_mat != null:
        _shader_mat.set_shader_parameter("wind_direction_deg", wind_direction_deg)

func set_grass_height(v: float) -> void:
    grass_height = v
    if _shader_mat != null:
        _shader_mat.set_shader_parameter("grass_height", v)

func clear_all() -> void:
    if _density_image != null:
        _density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
    for key: Variant in _chunks:
        var inst: MultiMeshInstance3D = _chunks[key]
        if is_instance_valid(inst):
            inst.queue_free()
    _chunks.clear()
    _last_cam_chunk = Vector2i(-9999, -9999)

func _ready() -> void:
    set_process(false)

func _process(_delta: float) -> void:
    if _camera == null:
        return
    var cam_pos: Vector3 = _camera.global_position
    var cc: Vector2i = _world_to_chunk(cam_pos.x, cam_pos.z)
    if cc != _last_cam_chunk:
        _update_active_chunks(cam_pos)
        _last_cam_chunk = cc

func _build_quad_mesh() -> void:
    _quad_mesh = QuadMesh.new()
    _quad_mesh.size = Vector2(1.0, 1.0)

func _build_shader_material() -> void:
    var shader := Shader.new()
    shader.code = _SHADER_CODE
    _shader_mat = ShaderMaterial.new()
    _shader_mat.shader = shader
    _shader_mat.set_shader_parameter("wind_strength", wind_strength)
    _shader_mat.set_shader_parameter("wind_speed", wind_speed)
    _shader_mat.set_shader_parameter("wind_direction_deg", wind_direction_deg)
    _shader_mat.set_shader_parameter("grass_height", grass_height)
    _shader_mat.set_shader_parameter("base_color", base_color)
    _shader_mat.set_shader_parameter("tip_color", tip_color)

func _update_active_chunks(cam_pos: Vector3) -> void:
    var half: float = map_size * 0.5
    var cam_chunk: Vector2i = _world_to_chunk(cam_pos.x, cam_pos.z)
    var max_r: int = int(ceil(lod_distance / CHUNK_SIZE)) + 1

    var wanted: Dictionary = {}
    for dz in range(-max_r, max_r + 1):
        for dx in range(-max_r, max_r + 1):
            var cc: Vector2i = Vector2i(cam_chunk.x + dx, cam_chunk.y + dz)
            var wx: float = float(cc.x) * CHUNK_SIZE + CHUNK_SIZE * 0.5
            var wz: float = float(cc.y) * CHUNK_SIZE + CHUNK_SIZE * 0.5
            if wx < -half or wx >= half or wz < -half or wz >= half:
                continue
            var dist: float = Vector2(cam_pos.x - wx, cam_pos.z - wz).length()
            if dist <= lod_distance:
                wanted[cc] = true

    for key: Variant in _chunks:
        var inst: MultiMeshInstance3D = _chunks[key]
        if is_instance_valid(inst):
            inst.visible = wanted.has(key)

    for key: Variant in wanted:
        if not _chunks.has(key):
            _rebuild_chunk(key as Vector2i)
        elif is_instance_valid(_chunks[key]):
            _chunks[key].visible = true

func _rebuild_visible_chunks(limit: int) -> void:
    var rebuilt: int = 0
    for key: Variant in _chunks:
        var inst: MultiMeshInstance3D = _chunks[key]
        if not is_instance_valid(inst) or not inst.visible:
            continue
        _rebuild_chunk(key as Vector2i)
        rebuilt += 1
        if rebuilt >= limit:
            break

func _rebuild_chunk(coord: Vector2i) -> void:
    if _terrain == null or _density_image == null or _quad_mesh == null:
        return

    var ox: float = float(coord.x) * CHUNK_SIZE
    var oz: float = float(coord.y) * CHUNK_SIZE
    var res: float = float(DENSITY_RES)

    var uv_min: Vector2 = _world_to_density_uv(ox, oz)
    var uv_max: Vector2 = _world_to_density_uv(ox + CHUNK_SIZE, oz + CHUNK_SIZE)
    var px_a: int = clampi(int(uv_min.x * res), 0, DENSITY_RES - 1)
    var px_b: int = clampi(int(uv_max.x * res), 0, DENSITY_RES - 1)
    var py_a: int = clampi(int(uv_min.y * res), 0, DENSITY_RES - 1)
    var py_b: int = clampi(int(uv_max.y * res), 0, DENSITY_RES - 1)

    var density_sum: float = 0.0
    var density_cnt: int = 0
    for py in range(py_a, py_b + 1):
        for px in range(px_a, px_b + 1):
            density_sum += _density_image.get_pixel(px, py).r
            density_cnt += 1
    var avg_density: float = density_sum / float(max(density_cnt, 1))

    if _chunks.has(coord):
        var old_inst: MultiMeshInstance3D = _chunks[coord]
        if is_instance_valid(old_inst):
            old_inst.queue_free()
        _chunks.erase(coord)

    if avg_density < 0.015:
        return

    var lod_factor: float = 1.0
    if _camera != null:
        var ccx: float = ox + CHUNK_SIZE * 0.5
        var ccz: float = oz + CHUNK_SIZE * 0.5
        var dist: float = Vector2(_camera.global_position.x - ccx, _camera.global_position.z - ccz).length()
        var fade: float = clampf(1.0 - (dist / maxf(lod_distance, 0.001)), 0.0, 1.0)
        lod_factor = lerpf(0.35, 1.0, _smooth01(fade))

    var target_density: float = clampf(avg_density * density_scale, 0.0, 1.0)
    if target_density <= 0.01:
        return

    # Keep chunk complexity bounded; scale down farther chunks for stable frame time.
    var candidate_count: int = int(round(float(blades_per_chunk) * (0.45 + target_density * 1.95) * lod_factor))
    candidate_count = clampi(candidate_count, 0, 1400)
    if candidate_count <= 0:
        return

    var rng := RandomNumberGenerator.new()
    rng.seed = (abs(coord.x * 73856093 ^ coord.y * 19349663)) & 0x7FFFFFFF

    var transforms: Array[Transform3D] = []

    for i in range(candidate_count):
        var lx: float = rng.randf() * CHUNK_SIZE
        var lz: float = rng.randf() * CHUNK_SIZE
        var wx: float = ox + lx
        var wz: float = oz + lz

        var blade_uv: Vector2 = _world_to_density_uv(wx, wz)
        var dpx: int = clampi(int(blade_uv.x * res), 0, DENSITY_RES - 1)
        var dpy: int = clampi(int(blade_uv.y * res), 0, DENSITY_RES - 1)
        var painted_density: float = _density_image.get_pixel(dpx, dpy).r
        # Thick swathes: painted regions heavily favor acceptance.
        var keep_chance: float = clampf(0.08 + painted_density * painted_density * 1.12, 0.0, 1.0)
        if rng.randf() > keep_chance:
            continue

        var th: float = 0.0
        if _terrain != null and _terrain.has_method("sample_height"):
            th = float(_terrain.call("sample_height", wx, wz))

        var t3d := Transform3D()
        t3d.origin = Vector3(wx, th, wz)
        transforms.append(t3d)


    var blade_count: int = transforms.size()
    blade_count = clampi(blade_count, 0, 1400)
    if blade_count <= 0:
        return

    var mm := MultiMesh.new()
    mm.mesh = _quad_mesh
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = false
    mm.use_custom_data = false
    mm.instance_count = blade_count

    for i in range(blade_count):
        mm.set_instance_transform(i, transforms[i])

    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = _shader_mat
    mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mmi)
    _chunks[coord] = mmi

func _smooth01(v: float) -> float:
    var t: float = clampf(v, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

func _world_to_chunk(x: float, z: float) -> Vector2i:
    return Vector2i(int(floor(x / CHUNK_SIZE)), int(floor(z / CHUNK_SIZE)))

func _world_to_density_uv(x: float, z: float) -> Vector2:
    return Vector2((x / map_size) + 0.5, (z / map_size) + 0.5)

func _density_px_to_world_x(u: float) -> float:
    return (u - 0.5) * map_size

func _density_px_to_world_z(v: float) -> float:
    return (v - 0.5) * map_size
