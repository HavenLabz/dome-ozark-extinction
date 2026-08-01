extends Node3D
class_name OzarkWorld
## Assembles the Ozark vertical slice at runtime:
##   terrain → forest scatter → water source → abandoned structure → resource
##   cache → navmesh bake → creature spawn → player placement.
##
## Everything snaps to the generated terrain surface, so tuning the terrain
## numbers reshapes the whole world. Data-driven spawns (North Star): add a
## species .tres and a spawn line, no new code.

@export var tree_count: int = 320
@export var player_start := Vector2(0.0, 20.0)   # (x, z) on the map
@export var spawn_seed: int = 4711

## What lives here and how many. Pure data — extend to grow the ecosystem.
@export var grazer_data: CreatureData
@export var raptor_data: CreatureData
@export var grazer_count: int = 6
@export var raptor_count: int = 3

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var creatures_root: Node3D = $Creatures

const CREATURE_SCENE := preload("res://scenes/creatures/creature_base.tscn")
## Physics frames to wait for the NavigationServer to sync the baked region
## into the map before creatures query it.
const NAV_SYNC_FRAMES := 20

var terrain: TerrainGenerator
var nav_map: RID                     # the dome's dedicated navigation map
var _rng := RandomNumberGenerator.new()
var _water_level: float = -1.5


func _ready() -> void:
	_rng.seed = spawn_seed

	# 1. Ground — a large, open Ozark valley so wildlife spreads out naturally.
	terrain = TerrainGenerator.new()
	terrain.name = "Terrain"
	terrain.world_size = 440.0
	terrain.resolution = 120
	terrain.height_amp = 7.0         # gentle Ozark rolling hills (bluffs are separate)
	terrain.water_level = _water_level  # so shoreline sand lines up with the water
	nav_region.add_child(terrain)
	terrain.build()

	# 2. Forest, water, ruins, cache
	_scatter_forest()
	_scatter_grass()
	_build_water()
	_build_structure(Vector2(-30.0, -25.0))
	_build_resource_cache(Vector2(-24.0, -20.0))
	_build_bluffs()
	_build_cave(Vector2(95.0, -70.0))
	_build_campfires()
	_add_birds()

	# Let the freshly-created static colliders register with the physics server
	# before we parse them into a navmesh (else the bake sees no geometry).
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 3. Navmesh over the assembled static geometry
	await _bake_navigation()

	# 4. Inhabitants + player
	_place_player()
	_spawn_wildlife()

	# Headless self-check: run with `-- --smoke` to print a report and quit.
	if "--smoke" in OS.get_cmdline_user_args():
		get_tree().create_timer(3.0).timeout.connect(_smoke_report)
	# Beauty-shot capture: run with `-- --shot <path>` to save a PNG and quit.
	if "--shot" in OS.get_cmdline_user_args():
		_capture_screenshot()


func _capture_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--shot")
	var path := args[idx + 1] if idx + 1 < args.size() else "user://dome_shot.png"
	# Elevated vantage looking across terrain, water, and forest.
	# Night shot: force night, light a campfire, frame it.
	if "--shotnight" in args:
		var dn := get_node_or_null("DayNight") as DayNightCycle
		if dn:
			dn.time_of_day = 0.92
			dn._apply()
		var fire: Node3D = null
		for c in get_children():
			if c is Campfire:
				(c as Campfire).interact()  # light it
				fire = c
				break
		var ncam := Camera3D.new()
		add_child(ncam)
		ncam.fov = 70.0
		if fire:
			ncam.global_position = fire.global_position + Vector3(4, 2.2, 4)
			ncam.look_at(fire.global_position + Vector3.UP * 0.6, Vector3.UP)
		ncam.current = true
		await get_tree().create_timer(2.5).timeout
		var img_n := get_viewport().get_texture().get_image()
		img_n.save_png(path)
		print("[shot] saved %s (%dx%d)" % [path, img_n.get_width(), img_n.get_height()])
		get_tree().quit()
		return

	# Weapon shot: use the player's own camera (which holds the viewmodel).
	if "--shotweapon" in args:
		if "--ads" in args:
			var pl := get_tree().get_first_node_in_group("player")
			if pl and pl.has_method("get_active_weapon"):
				var wpn = pl.get_active_weapon()
				if wpn:
					wpn.set_ads(true)
				pl.get_node("Head/Camera3D").fov = 50.0
		await get_tree().create_timer(2.5).timeout
		var img_w := get_viewport().get_texture().get_image()
		img_w.save_png(path)
		print("[shot] saved %s (%dx%d)" % [path, img_w.get_width(), img_w.get_height()])
		get_tree().quit()
		return

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 68.0
	var creatures := creatures_root.get_children()
	if "--shotcreature" in args and creatures.size() > 0:
		# Full-body portrait, framed by the creature's size. Optional index arg.
		var ci := 0
		var ai := args.find("--shotcreature")
		if ai + 1 < args.size() and args[ai + 1].is_valid_int():
			ci = clampi(int(args[ai + 1]), 0, creatures.size() - 1)
		var cr := creatures[ci] as Creature
		var h: float = cr.data.body_size.y
		var dist := maxf(7.0, h * 2.4)
		var tp := cr.global_position + Vector3.UP * (h * 0.45)
		cam.global_position = cr.global_position + Vector3(dist * 0.7, h * 0.7, dist * 0.75)
		cam.look_at(tp, Vector3.UP)
	elif "--shotground" in args:
		# Player's-eye view — the real in-game experience.
		var g := terrain.surface_point(player_start.x, player_start.y)
		cam.global_position = g + Vector3.UP * 1.6
		cam.look_at(g + Vector3(6, 1.0, -18), Vector3.UP)
	else:
		cam.global_position = Vector3(60, terrain.height_at(60, 90) + 55.0, 110)
		cam.look_at(Vector3(-10, 0, -30), Vector3.UP)
	cam.current = true
	# Let shaders, shadows, and volumetric fog settle.
	await get_tree().create_timer(2.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit()


# ---------------------------------------------------------------------------
# Forest
# ---------------------------------------------------------------------------

func _scatter_forest() -> void:
	var half := terrain.world_size * 0.5 - 4.0
	for i in tree_count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var p := terrain.surface_point(x, z)
		if p.y < _water_level + 0.4:
			continue  # no trees in the water
		# Keep the player's landing zone clear.
		if Vector2(x, z).distance_to(player_start) < 6.0:
			continue
		# Real Ozark forest is oak-hickory dominant with shortleaf pine mixed in.
		var scale := _rng.randf_range(0.8, 1.5)
		if _rng.randf() < 0.62:
			nav_region.add_child(_make_broadleaf_tree(p, scale))
		else:
			nav_region.add_child(_make_tree(p, scale))


func _make_tree(base: Vector3, scale: float) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.collision_layer = 1
	tree.collision_mask = 0
	tree.position = base
	tree.rotation.y = _rng.randf_range(0.0, TAU)

	var trunk_h := 4.5 * scale
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18 * scale
	trunk_mesh.bottom_radius = 0.42 * scale
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_h * 0.5
	var bark := _rng.randf_range(-0.03, 0.03)
	trunk.material_override = _solid_mat(Color(0.30 + bark, 0.22 + bark, 0.14))
	tree.add_child(trunk)

	# Three stacked, wind-swayed canopy tiers of decreasing size.
	var fmat := _make_foliage_material(
		Color(0.10, 0.20, 0.09).lerp(Color(0.16, 0.28, 0.10), _rng.randf()),
		Color(0.24, 0.42, 0.18).lerp(Color(0.34, 0.46, 0.16), _rng.randf()))
	var tiers := 3
	for i in tiers:
		var f := i / float(tiers)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = (2.4 - 1.3 * f) * scale
		cm.height = 2.6 * scale
		cone.mesh = cm
		cone.position.y = trunk_h + (0.6 + 1.6 * i) * scale
		cone.material_override = fmat
		tree.add_child(cone)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.42 * scale
	shape.height = trunk_h
	col.shape = shape
	col.position.y = trunk_h * 0.5
	tree.add_child(col)
	return tree


## Dense wind-swayed grass via a single MultiMesh (one draw call).
## Each tuft is a crossed pair of quads so it reads as grass from any angle.
func _scatter_grass(blade_count: int = 45000) -> void:
	var blade := _make_grass_tuft_mesh(0.28, 0.42)
	var mat := _make_foliage_material(Color(0.18, 0.27, 0.10), Color(0.36, 0.48, 0.19))
	mat.set_shader_parameter("height_ref", 0.42)
	mat.set_shader_parameter("sway_strength", 0.06)
	blade.surface_set_material(0, mat)

	var half := terrain.world_size * 0.5 - 4.0
	var xforms: Array[Transform3D] = []
	for i in blade_count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var p := terrain.surface_point(x, z)
		if p.y < _water_level + 0.6:
			continue  # no grass in water
		var sc := _rng.randf_range(0.6, 1.5)
		# Small random tilt so blades don't read as uniform flat cards.
		var basis := Basis.from_euler(Vector3(
			_rng.randf_range(-0.18, 0.18), _rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.18, 0.18))).scaled(Vector3(sc, sc, sc))
		xforms.append(Transform3D(basis, p))  # base sits on the ground

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Two perpendicular quads rising from y=0 to y=h — a grass tuft.
func _make_grass_tuft_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0), Vector3(w * 0.5, h, 0), Vector3(-w * 0.5, h, 0)],
		[Vector3(0, 0, -w * 0.5), Vector3(0, 0, w * 0.5), Vector3(0, h, w * 0.5), Vector3(0, h, -w * 0.5)],
	]
	for q in quads:
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(0, 0))
			st.add_vertex(q[idx])
	st.generate_normals()
	return st.commit()


## A few ambient birds circling overhead for life and scale.
func _add_birds() -> void:
	var flock := BirdFlock.new()
	flock.name = "Birds"
	flock.center = Vector3(0, 34, 0)
	add_child(flock)


## Rounded broadleaf (oak/hickory) with occasional autumn color — the Ozark
## forest's dominant tree, contrasting the conical pines.
func _make_broadleaf_tree(base: Vector3, scale: float) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.collision_layer = 1
	tree.collision_mask = 0
	tree.position = base
	tree.rotation.y = _rng.randf_range(0.0, TAU)

	var trunk_h := 3.4 * scale
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.22 * scale
	tm.bottom_radius = 0.5 * scale
	tm.height = trunk_h
	trunk.mesh = tm
	trunk.position.y = trunk_h * 0.5
	var bark := _rng.randf_range(-0.03, 0.03)
	trunk.material_override = _solid_mat(Color(0.31 + bark, 0.23 + bark, 0.15))
	tree.add_child(trunk)

	# Canopy color: mostly green, ~28% autumn gold/red (real Ozark fall).
	var bottom: Color
	var top: Color
	if _rng.randf() < 0.28:
		bottom = Color(0.34, 0.20, 0.06)
		top = Color(0.72, 0.44, 0.12).lerp(Color(0.68, 0.20, 0.10), _rng.randf())
	else:
		bottom = Color(0.12, 0.24, 0.09)
		top = Color(0.27, 0.43, 0.16).lerp(Color(0.36, 0.46, 0.15), _rng.randf())
	var fmat := _make_foliage_material(bottom, top)
	fmat.set_shader_parameter("height_ref", 0.7)
	fmat.set_shader_parameter("sway_strength", 0.14)

	# Rounded canopy from a few overlapping blobs.
	var canopy_y := trunk_h + 1.2 * scale
	for i in _rng.randi_range(3, 4):
		var blob := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.5
		sph.height = 1.0
		blob.mesh = sph
		var r := _rng.randf_range(1.7, 2.5) * scale
		blob.scale = Vector3(r, r * 0.85, r)
		blob.position = Vector3(_rng.randf_range(-1.0, 1.0) * scale,
			canopy_y + _rng.randf_range(-0.3, 0.7) * scale, _rng.randf_range(-1.0, 1.0) * scale)
		blob.material_override = fmat
		tree.add_child(blob)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5 * scale
	shape.height = trunk_h
	col.shape = shape
	col.position.y = trunk_h * 0.5
	tree.add_child(col)
	return tree


func _make_foliage_material(bottom: Color, top: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wind_foliage.gdshader")
	mat.set_shader_parameter("color_bottom", bottom)
	mat.set_shader_parameter("color_top", top)
	mat.set_shader_parameter("height_ref", 6.0)
	mat.set_shader_parameter("sway_strength", 0.12)
	return mat


# ---------------------------------------------------------------------------
# Water source (visual plane + drinkable shoreline)
# ---------------------------------------------------------------------------

func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain.world_size, terrain.world_size)
	plane.subdivide_width = 80   # enough vertices for the wave displacement
	plane.subdivide_depth = 80
	water.mesh = plane
	water.position.y = _water_level
	water.extra_cull_margin = 4.0  # waves push verts past the flat AABB
	var wshader := load("res://shaders/water.gdshader") as Shader
	if wshader:
		var mat := ShaderMaterial.new()
		mat.shader = wshader
		mat.render_priority = 1
		water.material_override = mat
		water.transparency = 0.0
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.18, 0.33, 0.42, 0.65)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water.material_override = m
	add_child(water)

	# A drinkable spot at the lowest nearby ground — a real, working interaction.
	var low := _find_low_point()
	var drink := preload("res://scenes/world/water_source.tscn").instantiate()
	drink.position = Vector3(low.x, _water_level, low.y)
	add_child(drink)


func _find_low_point() -> Vector2:
	var best := Vector2.ZERO
	var best_h := 999.0
	for i in 40:
		var x := _rng.randf_range(-60.0, 60.0)
		var z := _rng.randf_range(-60.0, 60.0)
		var h := terrain.height_at(x, z)
		if h < best_h:
			best_h = h
			best = Vector2(x, z)
	return best


# ---------------------------------------------------------------------------
# Abandoned research structure + resource cache (exploration landmarks)
# ---------------------------------------------------------------------------

func _build_structure(at: Vector2) -> void:
	var ground := terrain.surface_point(at.x, at.y)
	var shack := StaticBody3D.new()
	shack.name = "AbandonedStation"
	shack.collision_layer = 1
	shack.position = ground
	var wall_mat := _solid_mat(Color(0.34, 0.33, 0.30))

	# floor
	_add_box(shack, Vector3(7, 0.3, 6), Vector3(0, 0.15, 0), wall_mat)
	# back + two sides, front wall left of a doorway gap
	_add_box(shack, Vector3(7, 3, 0.3), Vector3(0, 1.5, -3), wall_mat)
	_add_box(shack, Vector3(0.3, 3, 6), Vector3(-3.5, 1.5, 0), wall_mat)
	_add_box(shack, Vector3(0.3, 3, 6), Vector3(3.5, 1.5, 0), wall_mat)
	_add_box(shack, Vector3(2.5, 3, 0.3), Vector3(-2.25, 1.5, 3), wall_mat)
	# sagging roof
	_add_box(shack, Vector3(7.4, 0.3, 6.4), Vector3(0, 3.0, 0), wall_mat)
	add_child(shack)


func _build_campfires() -> void:
	const CAMPFIRE_SCENE := preload("res://scenes/world/campfire.tscn")
	for at in [player_start + Vector2(3.0, -2.0), Vector2(-27.0, -21.0)]:
		var fire := CAMPFIRE_SCENE.instantiate()
		add_child(fire)
		fire.global_position = terrain.surface_point(at.x, at.y)


func _build_resource_cache(at: Vector2) -> void:
	var ground := terrain.surface_point(at.x, at.y)
	var crate := StaticBody3D.new()
	crate.name = "SupplyCache"
	crate.collision_layer = 1
	crate.position = ground
	_add_box(crate, Vector3(1.2, 1.2, 1.2), Vector3(0, 0.6, 0),
			_solid_mat(Color(0.5, 0.42, 0.2)))
	add_child(crate)


## Limestone bluffs — the Ozarks' eroded dolomite/limestone outcrops (the
## region's "mountains"). Stacked, tapering strata of pale rock.
func _build_bluffs() -> void:
	var rock := _solid_mat(Color(0.62, 0.60, 0.54))
	rock.roughness = 1.0
	var spots := [Vector2(95, 45), Vector2(-130, 90), Vector2(140, -100),
		Vector2(-90, -140), Vector2(45, 160), Vector2(-160, -40)]
	for at in spots:
		var g := terrain.surface_point(at.x, at.y)
		var bluff := StaticBody3D.new()
		bluff.collision_layer = 1
		bluff.position = g
		var w := _rng.randf_range(10.0, 20.0)
		var cum := 0.0
		for i in _rng.randi_range(3, 5):
			var h := _rng.randf_range(2.6, 4.6)
			var t := i / 5.0
			var sz := Vector3(w * (1.0 - t * 0.5), h, w * 0.7 * (1.0 - t * 0.4))
			_add_box(bluff, sz, Vector3(_rng.randf_range(-1.5, 1.5), cum + h * 0.5 - 1.0,
				_rng.randf_range(-1.5, 1.5)), rock)
			cum += h
		nav_region.add_child(bluff)   # navmesh routes creatures around it


## A karst cave — the Ozarks are riddled with them ("The Cave State"). A rock
## chamber with an entrance you can walk into, lit dimly for exploration.
func _build_cave(at: Vector2) -> void:
	var g := terrain.surface_point(at.x, at.y)
	var cave := StaticBody3D.new()
	cave.name = "Cave"
	cave.collision_layer = 1
	cave.position = g
	var rock := _solid_mat(Color(0.5, 0.48, 0.44))
	rock.roughness = 1.0
	# Chamber walls (entrance gap faces -Z), roof, and an exterior mound.
	_add_box(cave, Vector3(11, 5, 1.2), Vector3(0, 2.5, 5.5), rock)      # back
	_add_box(cave, Vector3(1.2, 5, 11), Vector3(5.5, 2.5, 0), rock)      # right
	_add_box(cave, Vector3(1.2, 5, 11), Vector3(-5.5, 2.5, 0), rock)     # left
	_add_box(cave, Vector3(4.0, 5, 1.2), Vector3(-3.5, 2.5, -5.5), rock) # front-left
	_add_box(cave, Vector3(4.0, 5, 1.2), Vector3(3.5, 2.5, -5.5), rock)  # front-right
	_add_box(cave, Vector3(12, 1.2, 12), Vector3(0, 5.2, 0), rock)       # roof
	_add_box(cave, Vector3(16, 7, 5), Vector3(0, 3.5, 8), rock)          # exterior mound
	# Dim interior light so the cave is explorable.
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.0, 0)
	light.light_color = Color(0.55, 0.68, 0.85)
	light.light_energy = 1.6
	light.omni_range = 14.0
	cave.add_child(light)
	nav_region.add_child(cave)


## Adds a visual box AND its collision box directly to `body`.
## (CollisionShape3D must be a direct child of the physics body to register.)
func _add_box(body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	body.add_child(col)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _bake_navigation() -> void:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.5             # coarser cells keep the bake fast on the big map
	navmesh.cell_height = 0.5           # match the navigation map to avoid edge errors
	navmesh.agent_radius = 0.5          # exact multiple of cell_size (no precision loss)
	navmesh.agent_height = 2.0          # exact multiple of cell_height
	navmesh.agent_max_climb = 0.5
	navmesh.agent_max_slope = 50.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES

	# Bake via the region node: it parses the region geometry (terrain + trees +
	# ruins) and fills the navmesh resource. Upward-facing terrain normals make
	# Recast mark the ground walkable.
	nav_region.navigation_mesh = navmesh
	nav_region.bake_navigation_mesh(false)

	# The scene's shared world navigation map would not accept the baked region
	# reliably (its polygons never synced into the query structure, regardless of
	# explicit pushes or wait time). A dedicated server-created map does — so give
	# the dome its own map, put the baked mesh on it, and point every creature
	# agent at it (see _spawn_species). This is also cleanly modular: each dome
	# owns its own navigation map.
	nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(nav_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(nav_map, navmesh.cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, navmesh.cell_height)
	NavigationServer3D.map_set_active(nav_map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	NavigationServer3D.region_set_map(region, nav_map)

	# Give the NavigationServer time to sync the region into the map before agents
	# query it. The sync takes several physics frames; querying too early returns
	# an empty map — this timing race was the root cause of the earlier bug.
	for _f in NAV_SYNC_FRAMES:
		await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _place_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := terrain.surface_point(player_start.x, player_start.y)
	player.global_position = p + Vector3.UP * 0.2


## The dome's ecosystem — grazers + predators + apex. Add a line to grow it.
## [path, count, is_pack]. Herbivores/lone predators spread across the valley;
## raptors spawn as one coordinated pack (intelligent group hunters).
const ROSTER := [
	# Real modern Ozark fauna — the base ecosystem the dinosaurs are layered onto.
	["res://data/creatures/whitetail_deer.tres", 6, false],
	["res://data/creatures/wild_turkey.tres", 4, false],
	["res://data/creatures/black_bear.tres", 2, false],
	# Resurrected prehistoric creatures, sharing the same wilderness.
	["res://data/creatures/brachiosaurus.tres", 3, false],
	["res://data/creatures/gallimimus.tres", 4, false],
	["res://data/creatures/triceratops.tres", 3, false],
	["res://data/creatures/velociraptor.tres", 5, true],   # pack hunters
	["res://data/creatures/allosaurus.tres", 2, false],
	["res://data/creatures/spinosaurus.tres", 1, false],
	["res://data/creatures/tyrannosaurus.tres", 1, false],
]

var _placed: Array[Vector2] = []  # spawn XZ positions, for separation


func _spawn_wildlife() -> void:
	for entry in ROSTER:
		_spawn_species(load(entry[0]), entry[1], entry[2])


## Minimum distance a species spawns from the player's landing zone — apex and
## predators stay far so encounters are earned, not immediate (Jurassic-Park pacing).
func _min_player_dist(data: CreatureData) -> float:
	if data.is_apex:
		return 150.0
	if data.is_aggressive:
		return 100.0
	return 45.0


func _spawn_species(data: CreatureData, count: int, is_pack: bool) -> void:
	if data == null:
		return
	if is_pack:
		# One pack territory; members cluster together and hunt as a group.
		var center := _find_spawn_point(data, 40.0)
		for i in count:
			_spawn_one(data, center + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-16, 16)))
	else:
		# Spread individuals far apart so the wilderness feels open and wild.
		for i in count:
			_spawn_one(data, _find_spawn_point(data, 55.0))


## Find an XZ spawn: on land, beyond the player safe radius, and `separation`
## away from other creatures. Returns the best candidate found.
func _find_spawn_point(data: CreatureData, separation: float) -> Vector2:
	var half := terrain.world_size * 0.5 - 18.0
	var min_pd := _min_player_dist(data)
	var fallback := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
	for attempt in 48:
		var v := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if terrain.height_at(v.x, v.y) < _water_level + 0.6:
			continue
		if v.distance_to(player_start) < min_pd:
			continue
		fallback = v
		var ok := true
		for pl in _placed:
			if v.distance_to(pl) < separation:
				ok = false
				break
		if ok:
			return v
	return fallback


func _spawn_one(data: CreatureData, pos2: Vector2) -> void:
	var p := terrain.surface_point(pos2.x, pos2.y)
	if p.y < _water_level + 0.4:
		p.y = _water_level + 0.4
	var c := CREATURE_SCENE.instantiate() as Creature
	c.data = data
	creatures_root.add_child(c)
	c.global_position = p + Vector3.UP * 0.2
	c.use_navigation_map(nav_map)  # route on the dome's dedicated map
	_placed.append(pos2)


## Behavioral self-test: proves the slice is genuinely playable — geometry,
## pathing, perception→hunt, perception→flee, and the down→trophy loop — then
## quits with a non-zero exit code if anything fails.
func _smoke_report() -> void:
	var results: Array = []  # [label, ok]
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var creatures := creatures_root.get_children()

	# --- Geometry / spawn ---
	var nm := nav_region.navigation_mesh
	results.append(["Navmesh baked (%d polys)" % (nm.get_polygon_count() if nm else 0),
		nm != null and nm.get_polygon_count() > 0])
	results.append(["Creatures spawned (%d)" % creatures.size(), creatures.size() > 0])
	results.append(["Player grounded", player != null and player.is_on_floor()])

	# --- Navmesh routing: the dome's map must resolve a real path.
	var pa := terrain.surface_point(-20, -20)
	var pb := terrain.surface_point(30, 25)
	var route := NavigationServer3D.map_get_path(nav_map, pa, pb, true)
	results.append(["Navmesh resolves path (%d waypoints)" % route.size(), route.size() >= 2])

	# --- Pathing: creatures wandering the navmesh should physically move.
	# Sample the whole population over a window > the max idle wait (4s).
	var start_positions: Array[Vector3] = []
	for c in creatures:
		start_positions.append((c as Node3D).global_position)
	await get_tree().create_timer(8.0).timeout   # > max idle wait, big-map travel
	var max_moved := 0.0
	var movers := 0
	for i in creatures.size():
		var d := start_positions[i].distance_to((creatures[i] as Node3D).global_position)
		max_moved = maxf(max_moved, d)
		if d > 0.5:
			movers += 1
	results.append(["Creatures path the navmesh (%d/%d moved, max %.1fm)" % [
		movers, creatures.size(), max_moved], movers >= creatures.size() / 2])

	# --- Perception → HUNT: drop the player next to a predator ---
	var raptor := _first_of_diet(creatures, CreatureData.Diet.CARNIVORE)
	if raptor:
		player.global_position = raptor.global_position + Vector3(4, 0, 0)
		await get_tree().create_timer(1.5).timeout
		results.append(["Predator reacts to player (%s)" % raptor.get_state_name(),
			raptor.get_state() in [Creature.State.HUNT, Creature.State.ATTACK, Creature.State.INVESTIGATE]])

	# --- Perception → FLEE: drop the player next to prey ---
	var grazer := _first_of_diet(creatures, CreatureData.Diet.HERBIVORE)
	if grazer:
		player.global_position = grazer.global_position + Vector3(5, 0, 0)
		await get_tree().create_timer(1.2).timeout
		results.append(["Prey flees from player (%s)" % grazer.get_state_name(),
			grazer.get_state() == Creature.State.FLEE])

	# --- Hunt loop: down a creature → trophy drop → recover → score ---
	if grazer:
		var before := GameState.trophy_score
		grazer.take_damage(9999.0, player.global_position)
		await get_tree().physics_frame
		results.append(["Creature dies when depleted", grazer.get_state() == Creature.State.DEAD])
		var trophy := _find_child_of_type(creatures_root, "TrophyPickup")
		results.append(["Trophy drops on death", trophy != null])
		if trophy and trophy.has_method("interact"):
			trophy.interact()
			results.append(["Recovering trophy scores (%d)" % GameState.trophy_score,
				GameState.trophy_score > before])

	# --- Weapon: fire consumes ammo; reload refills ---
	if player and player.has_method("get_active_weapon"):
		var wpn = player.get_active_weapon()
		if wpn:
			var a0: Vector2i = wpn.get_ammo()
			wpn.try_fire(false)
			await get_tree().physics_frame
			var a1: Vector2i = wpn.get_ammo()
			results.append(["Weapon fires + consumes ammo (%d→%d)" % [a0.x, a1.x], a1.x == a0.x - 1])
		else:
			results.append(["Weapon equipped", false])

	# --- Survival drain (heal first: predators may have killed the player above) ---
	GameState.survival_active = true
	GameState.near_fire = false
	GameState.health = 100.0
	GameState.hunger = 90.0
	var hunger0 := GameState.hunger
	await get_tree().create_timer(1.0).timeout
	results.append(["Survival drains hunger (%.1f→%.1f)" % [hunger0, GameState.hunger],
		GameState.hunger < hunger0])

	# --- Day/night advances ---
	var dn := get_node_or_null("DayNight") as DayNightCycle
	if dn:
		var t0 := dn.time_of_day
		await get_tree().create_timer(0.5).timeout
		results.append(["Day/night cycle advances", dn.time_of_day != t0])
	else:
		results.append(["Day/night node present", false])

	# --- Report ---
	print("\n===== OZARK BEHAVIORAL SMOKE TEST =====")
	var fails := 0
	for r in results:
		print("[%s] %s" % ["PASS" if r[1] else "FAIL", r[0]])
		if not r[1]:
			fails += 1
	print("--------------------------------------")
	print("RESULT: %d passed, %d failed" % [results.size() - fails, fails])
	print("======================================\n")
	get_tree().quit(0 if fails == 0 else 1)


func _first_of_diet(nodes: Array, diet: CreatureData.Diet) -> Creature:
	for n in nodes:
		if n is Creature and (n as Creature).data.diet == diet:
			return n as Creature
	return null


func _find_child_of_type(parent: Node, type_name: String) -> Node:
	for c in parent.get_children():
		var sc: Script = c.get_script()
		if sc and sc.get_global_name() == type_name:
			return c
	return null


func _solid_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
