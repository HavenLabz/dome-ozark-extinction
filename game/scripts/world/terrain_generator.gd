extends Node3D
class_name TerrainGenerator
## Procedurally builds the Ozark ground: a noise heightfield mesh + matching
## collision. Procedural + data-driven so the slice can grow from ~200 m to the
## full 400-acre Dome by changing numbers, not rewriting (North Star: expandable).
##
## Exposes height_at()/surface_point() so props, water, and creatures snap to
## the real ground instead of guessing.

@export var world_size: float = 200.0   # meters per side (square, centered on origin)
@export var resolution: int = 72         # grid cells per side
@export var height_amp: float = 7.0      # peak hill height above base
@export var hill_frequency: float = 0.012
@export var detail_amp: float = 1.4
@export var detail_frequency: float = 0.06
@export var noise_seed: int = 20380417
@export var ground_color: Color = Color(0.24, 0.31, 0.17)

var _hill := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _built: bool = false

## The generated ground mesh, exposed for navmesh baking.
var terrain_mesh: ArrayMesh


func _ready() -> void:
	_configure_noise()


func _configure_noise() -> void:
	_hill.noise_type = FastNoiseLite.TYPE_PERLIN
	_hill.seed = noise_seed
	_hill.frequency = hill_frequency
	_hill.fractal_octaves = 4
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.seed = noise_seed + 7
	_detail.frequency = detail_frequency
	_detail.fractal_octaves = 2


## Winding river valley (real Ozark spring-fed stream) carved through the hills.
@export var river_amplitude: float = 55.0   # how far the channel meanders in X
@export var river_frequency: float = 0.017
@export var river_half_width: float = 15.0
@export var river_depth: float = 7.0


## World-space ground height at (x, z).
func height_at(x: float, z: float) -> float:
	var h := _hill.get_noise_2d(x, z) * height_amp
	h += _detail.get_noise_2d(x, z) * detail_amp
	# Carve a meandering river valley so the water plane fills a real channel.
	var river_x := river_amplitude * sin(z * river_frequency)
	var d := absf(x - river_x)
	if d < river_half_width:
		var t := d / river_half_width           # 0 at centerline, 1 at bank
		h -= (1.0 - smoothstep(0.0, 1.0, t)) * river_depth
	return h


## X coordinate of the river centerline at depth z (for spawning banks etc.).
func river_center_x(z: float) -> float:
	return river_amplitude * sin(z * river_frequency)


func surface_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


## Generate the visible mesh and its static collision. Idempotent.
func build() -> void:
	if _built:
		return
	_configure_noise()
	var mesh := _build_mesh()
	terrain_mesh = mesh

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1  # world
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)

	_built = true


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := world_size * 0.5
	var step := world_size / float(resolution)

	for ix in range(resolution):
		for iz in range(resolution):
			var x0 := -half + ix * step
			var z0 := -half + iz * step
			var x1 := x0 + step
			var z1 := z0 + step

			var v00 := surface_point(x0, z0)
			var v10 := surface_point(x1, z0)
			var v01 := surface_point(x0, z1)
			var v11 := surface_point(x1, z1)

			var uv_scale := 0.25
			# Wound clockwise-from-above so normals point UP: required for
			# render front-faces, one-sided top collision, and Recast marking
			# the ground walkable.
			# Triangle 1
			_add_vertex(st, v00, uv_scale)
			_add_vertex(st, v11, uv_scale)
			_add_vertex(st, v01, uv_scale)
			# Triangle 2
			_add_vertex(st, v00, uv_scale)
			_add_vertex(st, v10, uv_scale)
			_add_vertex(st, v11, uv_scale)

	st.generate_normals()
	st.set_material(_make_ground_material())
	return st.commit()


func _add_vertex(st: SurfaceTool, v: Vector3, uv_scale: float) -> void:
	st.set_uv(Vector2(v.x, v.z) * uv_scale)
	st.add_vertex(v)


func _make_ground_material() -> Material:
	# Slope/height shaded ground (grass, rock, sand) — no texture assets.
	var shader := load("res://shaders/terrain.gdshader") as Shader
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = ground_color
		fallback.roughness = 0.95
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("water_level", water_level)
	return mat


## Water plane height, so the terrain shader can place shoreline sand.
var water_level: float = -1.5
