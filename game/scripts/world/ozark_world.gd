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
## Biome fields: large-scale noise that carves the Ozarks into dense forest,
## open glades/balds, and everything between, so tree + flora density varies
## across the map instead of being a uniform sprinkle.
var _forest_noise := FastNoiseLite.new()
var _moist_noise := FastNoiseLite.new()


func _ready() -> void:
	_rng.seed = spawn_seed
	_forest_noise.seed = spawn_seed
	_forest_noise.frequency = 0.0045          # ~220-unit forest/glade patches
	_forest_noise.fractal_octaves = 3
	_moist_noise.seed = spawn_seed + 7
	_moist_noise.frequency = 0.006

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
	_scatter_flora()     # ferns, wildflowers, shrubs, fungi, reeds — the Eden layer
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

	# Scope shot: force the rifle's scope optic + overlay.
	if "--shotscope" in args:
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("get_active_weapon"):
			var wpn = pl.get_active_weapon()
			if wpn:
				wpn.cycle_optic(); wpn.cycle_optic()  # iron -> reflex -> scope
				wpn.visible = false
			pl.get_node("Head/Camera3D").fov = 20.0
		var hud := get_node_or_null("HUD")
		if hud and hud.has_method("_on_scope_changed"):
			hud._on_scope_changed(true, "4x Hunting Scope")
		await get_tree().create_timer(2.5).timeout
		var img_s := get_viewport().get_texture().get_image()
		img_s.save_png(path)
		print("[shot] saved %s (%dx%d)" % [path, img_s.get_width(), img_s.get_height()])
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

## Biome density at (x,z): 1 = dense forest, 0 = open glade/bald.
func _forest_density(x: float, z: float) -> float:
	return clampf(_forest_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)

## Moisture at (x,z): 1 = wet bottomland (hardwoods), 0 = dry ridge (pine).
func _moisture(x: float, z: float) -> float:
	return clampf(_moist_noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)


func _scatter_forest() -> void:
	# Shortleaf pines and oak-hickory hardwoods, both built procedurally from
	# thousands of individual needles/leaves. Density follows the biome field:
	# dense stands in the forest zones, sparse in the glades and balds.

	# --- Conifer (shortleaf pine) shared assets ---
	var conifer_needles: Array[ArrayMesh] = []
	for v in 3:
		conifer_needles.append(_make_conifer_needle_mesh(9.0, 2.2 + 0.45 * v, 0.9 + 0.2 * v))
	var conifer_trunk := CylinderMesh.new()
	conifer_trunk.bottom_radius = 0.34
	conifer_trunk.top_radius = 0.07
	conifer_trunk.height = 9.0
	var conifer_mat := _make_foliage_material(Color(0.05, 0.12, 0.05), Color(0.17, 0.31, 0.12))
	conifer_mat.set_shader_parameter("height_ref", 9.0)
	conifer_mat.set_shader_parameter("sway_strength", 0.09)

	# --- Deciduous (oak/hickory) shared assets: canopies of individual leaves ---
	var decid_canopies: Array[ArrayMesh] = []
	decid_canopies.append(_make_broadleaf_canopy_mesh(3.3, 0.0))    # full summer green
	decid_canopies.append(_make_broadleaf_canopy_mesh(3.1, 0.35))   # turning (autumn)
	decid_canopies.append(_make_broadleaf_canopy_mesh(3.6, 0.12))   # mostly green
	var decid_trunk := CylinderMesh.new()
	decid_trunk.bottom_radius = 0.44
	decid_trunk.top_radius = 0.16
	decid_trunk.height = 5.5
	# White gradient → the baked per-leaf vertex colour is the actual colour.
	var decid_mat := _make_foliage_material(Color.WHITE, Color.WHITE)
	decid_mat.set_shader_parameter("height_ref", 8.0)
	decid_mat.set_shader_parameter("sway_strength", 0.16)

	var bark_mat := _solid_mat(Color(0.24, 0.17, 0.11))
	bark_mat.roughness = 0.95
	var oak_bark := _solid_mat(Color(0.29, 0.22, 0.15))
	oak_bark.roughness = 0.95

	# Oversample candidates and accept by local forest density, so trees cluster
	# into real stands with open ground between — biome variety, "Minecraft" style.
	var half := terrain.world_size * 0.5 - 4.0
	var candidates := tree_count * 4
	for i in candidates:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var p := terrain.surface_point(x, z)
		if p.y < _water_level + 0.4:
			continue  # no trees in the water
		if Vector2(x, z).distance_to(player_start) < 6.0:
			continue  # keep the landing zone clear
		var fd := _forest_density(x, z)
		if _rng.randf() > clampf(fd * 1.15, 0.05, 1.0):
			continue  # thin out toward the glades
		var scale := _rng.randf_range(0.8, 1.5)
		# Pines favour dry ridges; hardwoods favour wetter bottomland.
		var moist := _moisture(x, z)
		var elev := clampf((p.y - _water_level) / 12.0, 0.0, 1.0)
		var conifer_chance := 0.26 + elev * 0.34 + (1.0 - moist) * 0.16
		if _rng.randf() < conifer_chance:
			nav_region.add_child(_make_conifer_tree(
				p, conifer_needles.pick_random(), conifer_trunk, conifer_mat, bark_mat, scale))
		else:
			nav_region.add_child(_make_deciduous_tree(
				p, decid_canopies.pick_random(), decid_trunk, decid_mat, oak_bark, scale))


## A hardwood: shared trunk + a canopy of individual leaves, per-tree scale/spin.
func _make_deciduous_tree(base: Vector3, canopy: ArrayMesh, trunk_mesh: Mesh,
		foliage_mat: Material, bark_mat: Material, scale: float) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.collision_layer = 1
	tree.collision_mask = 0
	tree.position = base
	tree.rotation.y = _rng.randf_range(0.0, TAU)

	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = bark_mat
	trunk.scale = Vector3(scale, scale, scale)
	trunk.position.y = 5.5 * scale * 0.5
	tree.add_child(trunk)

	var foliage := MeshInstance3D.new()
	foliage.mesh = canopy
	foliage.material_override = foliage_mat
	foliage.scale = Vector3(scale, scale, scale)
	foliage.position.y = 5.2 * scale     # canopy sits on top of the trunk
	tree.add_child(foliage)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.44 * scale
	shape.height = 5.5 * scale
	col.shape = shape
	col.position.y = 5.5 * scale * 0.5
	tree.add_child(col)
	return tree


## A hardwood canopy: hundreds of small leaf quads filling a rounded crown, with
## a share of autumn colour. Built once, shared across every tree of the variant.
##   radius  — crown radius
##   autumn  — fraction of leaves that turn gold/red
func _make_broadleaf_canopy_mesh(radius: float, autumn: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green_lo := Color(0.07, 0.18, 0.05)
	var green_hi := Color(0.24, 0.40, 0.13)
	var gold := Color(0.74, 0.52, 0.12)
	var red := Color(0.62, 0.18, 0.10)
	var center_y := radius
	var leaves := int(1300.0 * (radius / 3.3))
	for i in leaves:
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.65, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var rr := radius * _rng.randf_range(0.5, 1.0)
		var c := Vector3(dir.x * rr, center_y + dir.y * rr * 0.85, dir.z * rr)
		var lit := clampf(c.y / (radius * 1.85), 0.0, 1.0)
		var col := green_lo.lerp(green_hi, lit)
		if _rng.randf() < autumn:
			col = gold.lerp(red, _rng.randf()) * _rng.randf_range(0.8, 1.1)
		else:
			col = col * _rng.randf_range(0.8, 1.12)
		var t := dir.cross(Vector3.UP)
		if t.length() < 0.01:
			t = Vector3(1, 0, 0)
		t = t.normalized()
		var b := dir.cross(t).normalized()
		var sz := _rng.randf_range(0.12, 0.2)
		var p0 := c - t * sz - b * sz
		var p1 := c + t * sz - b * sz
		var p2 := c + t * sz + b * sz
		var p3 := c - t * sz + b * sz
		for v in [p0, p1, p2, p0, p2, p3]:
			st.set_color(col)
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A detailed shortleaf-pine: shared needle + trunk meshes, per-tree scale/spin.
func _make_conifer_tree(base: Vector3, needles: ArrayMesh, trunk_mesh: Mesh,
		foliage_mat: Material, bark_mat: Material, scale: float) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.collision_layer = 1
	tree.collision_mask = 0
	tree.position = base
	tree.rotation.y = _rng.randf_range(0.0, TAU)

	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = bark_mat
	trunk.scale = Vector3(scale, scale, scale)
	trunk.position.y = 9.0 * scale * 0.5
	tree.add_child(trunk)

	var foliage := MeshInstance3D.new()
	foliage.mesh = needles
	foliage.material_override = foliage_mat
	foliage.scale = Vector3(scale, scale, scale)
	tree.add_child(foliage)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34 * scale
	shape.height = 9.0 * scale
	col.shape = shape
	col.position.y = 9.0 * scale * 0.5
	tree.add_child(col)
	return tree


## One conifer's foliage: hundreds of drooping needle-sprays filling a cone, each
## spray a fan of thin tapered needles. Built once, shared across every pine.
##   height   — full tree height (trunk + crown)
##   base_r   — crown radius at its widest (near the bottom)
##   fullness — needle density / length multiplier
func _make_conifer_needle_mesh(height: float, base_r: float, fullness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage_start := height * 0.13
	var sprays := int(1150.0 * fullness)
	for s in sprays:
		# Bias sprays toward the bottom so the crown is fuller below (real conifer).
		var t := pow(_rng.randf(), 0.78)
		var y := lerpf(foliage_start, height * 0.99, t)
		var cone_t := (y - foliage_start) / (height - foliage_start)   # 0 base .. 1 tip
		var cone_r := base_r * (1.0 - cone_t * 0.9)
		var ang := _rng.randf_range(0.0, TAU)
		var r := cone_r * _rng.randf_range(0.25, 1.0)
		var center := Vector3(cos(ang) * r, y, sin(ang) * r)
		# Branch direction: outward and gently drooping.
		var outward := Vector3(cos(ang), 0.0, sin(ang))
		var dir := (outward + Vector3(0.0, -0.38, 0.0)).normalized()
		var needles := _rng.randi_range(5, 9)
		for n in needles:
			var ndir := dir.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
			ndir = (ndir + Vector3(0.0, _rng.randf_range(-0.22, 0.12), 0.0)).normalized()
			var side := ndir.cross(Vector3.UP)
			if side.length() < 0.01:
				side = Vector3(1, 0, 0)
			side = side.normalized()
			var length := _rng.randf_range(0.24, 0.44) * fullness
			var tip := center + ndir * length
			var w := 0.024
			var bl := center - side * w
			var br := center + side * w
			# Two crossed triangles per needle-spray point so it reads full from any
			# angle instead of vanishing edge-on.
			var up := side.cross(ndir).normalized() * w
			for v in [bl, br, tip, center - up, center + up, tip]:
				st.set_uv(Vector2(0, 0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Instance a real tree GLB, auto-fit it to target_h, drop it on the ground, and
## give it a simple trunk collider so the player and creatures can't walk through.
func _make_glb_tree(base: Vector3, scene: PackedScene, target_h: float, trunk_radius: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = base
	body.rotation.y = _rng.randf_range(0.0, TAU)

	var model := scene.instantiate()
	body.add_child(model)

	# Measure the model in its own local space (no need to be in the tree yet).
	var acc := {}
	_accum_aabb(model, Transform3D.IDENTITY, acc)
	var box: AABB = acc.get("b", AABB(Vector3.ZERO, Vector3.ONE))
	var h := maxf(0.05, box.size.y)
	var s := target_h / h
	if model is Node3D:
		(model as Node3D).scale = Vector3(s, s, s)
		# Sit the model's lowest point exactly on the ground.
		(model as Node3D).position.y = -box.position.y * s

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = trunk_radius
	shape.height = target_h
	col.shape = shape
	col.position.y = target_h * 0.5
	body.add_child(col)
	return body


## Recursively merge every child mesh's AABB into acc["b"], in root-local space.
func _accum_aabb(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var local_xf := xf
	if node is Node3D:
		local_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var box: AABB = local_xf * (node as MeshInstance3D).mesh.get_aabb()
		acc["b"] = (acc["b"] as AABB).merge(box) if acc.has("b") else box
	for c in node.get_children():
		_accum_aabb(c, local_xf, acc)


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
## Each instance is a small clump of thin tapered blades — reads as real grass,
## not flat cards. Density + per-clump size/tilt variation sell the field.
func _scatter_grass(clump_count: int = 80000) -> void:
	var blade := _make_grass_clump_mesh()
	# Natural, slightly desaturated Ozark green (base darker, tips lit).
	var mat := _make_foliage_material(Color(0.16, 0.26, 0.09), Color(0.38, 0.50, 0.19))
	mat.set_shader_parameter("height_ref", 0.5)
	mat.set_shader_parameter("sway_strength", 0.05)
	mat.set_shader_parameter("sky_lit", 1.0)   # skylit so grass reads lush, not black
	blade.surface_set_material(0, mat)

	var half := terrain.world_size * 0.5 - 4.0
	var xforms: Array[Transform3D] = []
	for i in clump_count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var p := terrain.surface_point(x, z)
		if p.y < _water_level + 0.6:
			continue  # no grass in water
		# Thickest in the open glades, thinner under dense shaded canopy.
		if _rng.randf() > clampf(1.0 - _forest_density(x, z) * 0.55, 0.35, 1.0):
			continue
		# Vary height and footprint per clump so the field isn't uniform.
		var sc := _rng.randf_range(0.55, 1.35)
		var wide := _rng.randf_range(0.85, 1.2)
		var basis := Basis.from_euler(Vector3(
			_rng.randf_range(-0.08, 0.08), _rng.randf_range(0.0, TAU),
			_rng.randf_range(-0.08, 0.08))).scaled(Vector3(sc * wide, sc, sc * wide))
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


## A clump of several thin, tapered, slightly-bent blades fanning from the base.
## The pointed tips (not rectangular tops) are what make it read as grass rather
## than crossed cards. One shared mesh; per-clump variety comes from the instance
## transform. Built once at load.
func _make_grass_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 7
	for i in blades:
		var yaw := _rng.randf_range(0.0, TAU)
		var off := Vector3(_rng.randf_range(-0.07, 0.07), 0.0, _rng.randf_range(-0.07, 0.07))
		var h := _rng.randf_range(0.34, 0.55)
		var bw := _rng.randf_range(0.035, 0.055)   # base width
		var tw := 0.006                            # tip (near-point)
		var lean := Vector3(sin(yaw), 0.0, cos(yaw)) * _rng.randf_range(0.06, 0.16) * h
		var side := Vector3(cos(yaw), 0.0, -sin(yaw))
		var mid := off + Vector3(0, h * 0.5, 0) + lean * 0.45
		var tip := off + Vector3(0, h, 0) + lean
		# Two stacked quads (base→mid, mid→tip) give the blade a gentle curve.
		var b_l := off - side * bw * 0.5
		var b_r := off + side * bw * 0.5
		var m_l := mid - side * bw * 0.32
		var m_r := mid + side * bw * 0.32
		var t_l := tip - side * tw
		var t_r := tip + side * tw
		for tri in [[b_l, b_r, m_r], [b_l, m_r, m_l], [m_l, m_r, t_r], [m_l, t_r, t_l]]:
			for v in tri:
				st.set_uv(Vector2(0, 0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------------------
# Biodiversity — the "Garden of Eden" ground flora
#
# A palette of procedural native-plant types (ferns, wildflowers in six colours,
# shrubs, forest herbs, fungi, waterside reeds) scattered by the tens of
# thousands via MultiMesh (one draw call per type) and placed by biome so the
# forest floor reads as lush and varied rather than a bare lawn. All share one
# vertex-coloured material; per-plant colour is baked into each mesh.
# ---------------------------------------------------------------------------

func _scatter_flora() -> void:
	var mat := _make_vcolor_material()

	var fern := _make_fern_mesh()
	var bush := _make_bush_mesh()
	var shroom := _make_mushroom_mesh()
	var reed := _make_reed_mesh()
	var herb := _make_herb_mesh()

	# Wildflowers in several real Ozark colours (bloodroot white, coreopsis gold,
	# wild bergamot lavender, phlox pink, fire pink red, butterfly-weed orange).
	var flower_cols := [
		Color(0.95, 0.95, 0.90), Color(0.96, 0.82, 0.18), Color(0.66, 0.42, 0.82),
		Color(0.92, 0.46, 0.62), Color(0.86, 0.18, 0.14), Color(0.97, 0.58, 0.14),
	]

	# Understory species cluster in the forest; wildflowers fill the open glades;
	# reeds line the water — density follows the biome, not a uniform sprinkle.
	_scatter_plant(fern, mat, 17000, "wet_shade", "forest")
	_scatter_plant(herb, mat, 12000, "land", "forest")
	_scatter_plant(bush, mat, 7000, "land", "any")
	_scatter_plant(shroom, mat, 8000, "land", "forest")
	_scatter_plant(reed, mat, 6000, "waterline", "any")
	for c in flower_cols:
		_scatter_plant(_make_flower_mesh(c), mat, 4000, "land", "open")


## One vertex-coloured, double-sided matte material shared by all ground flora.
func _make_vcolor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.93
	m.specular = 0.08
	return m


## Scatter up to `count` instances of `mesh` under a placement filter (biome) and
## a density preference (`prefer`: "forest" clusters in tree cover, "open" fills
## the glades, "any" is neutral) so each species lives where it should.
func _scatter_plant(mesh: ArrayMesh, mat: Material, count: int, biome: String, prefer: String = "any") -> void:
	var half := terrain.world_size * 0.5 - 4.0
	var xforms: Array[Transform3D] = []
	for i in count:
		var x := _rng.randf_range(-half, half)
		var z := _rng.randf_range(-half, half)
		var p := terrain.surface_point(x, z)
		var above := p.y - _water_level
		match biome:
			"waterline":
				if above < 0.15 or above > 1.7:
					continue
			"wet_shade":
				if above < 0.5 or above > 6.0:
					continue
			_:  # "land"
				if above < 0.8:
					continue
		if Vector2(x, z).distance_to(player_start) < 4.0:
			continue
		# Density preference by biome field.
		var fd := _forest_density(x, z)
		var w := 1.0
		if prefer == "forest":
			w = clampf(fd * 1.35, 0.06, 1.0)
		elif prefer == "open":
			w = clampf((1.0 - fd) * 1.35, 0.06, 1.0)
		if _rng.randf() > w:
			continue
		var sc := _rng.randf_range(0.6, 1.1)
		var basis := Basis.from_euler(Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3(sc, sc, sc))
		xforms.append(Transform3D(basis, p))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Flora"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Fern — a rosette of arching fronds, each lined with paired leaflets.
func _make_fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.09, 0.20, 0.07)
	var tip_col := Color(0.28, 0.44, 0.16)
	var fronds := _rng.randi_range(5, 8)
	for f in fronds:
		var yaw := _rng.randf_range(0.0, TAU)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var length := _rng.randf_range(0.4, 0.7)
		var segs := 9
		for s in segs:
			var u := s / float(segs)
			var pos := out * (length * u) + Vector3(0.0, length * (0.45 * sin(u * 2.4) + 0.05), 0.0)
			var col := base_col.lerp(tip_col, u)
			var ll := (1.0 - u) * 0.13 + 0.02
			for sgn: float in [-1.0, 1.0]:
				var tip := pos + side * sgn * ll + out * ll * 0.4 + Vector3(0.0, ll * 0.35, 0.0)
				st.set_color(col); st.add_vertex(pos)
				st.set_color(col); st.add_vertex(pos + out * ll * 0.35 + Vector3(0.0, 0.006, 0.0))
				st.set_color(col.lerp(tip_col, 0.3)); st.add_vertex(tip)
	st.generate_normals()
	return st.commit()


## Wildflower — thin cross-quad stem topped with a ring of coloured petals.
func _make_flower_mesh(petal: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.16, 0.30, 0.11)
	var center := Color(0.96, 0.80, 0.22)
	var h := _rng.randf_range(0.26, 0.46)
	var sw := 0.012
	var top := Vector3(0.0, h, 0.0)
	for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		st.set_color(stem); st.add_vertex(-axis * sw)
		st.set_color(stem); st.add_vertex(axis * sw)
		st.set_color(stem); st.add_vertex(top + axis * sw * 0.3)
	var petals := 6
	for pi in petals:
		var a := TAU * pi / petals
		var d := Vector3(cos(a), 0.0, sin(a))
		var s := d.cross(Vector3.UP).normalized() * 0.028
		var pl := _rng.randf_range(0.06, 0.095)
		var inner := top + Vector3(0.0, 0.006, 0.0)
		var outer := top + d * pl + Vector3(0.0, 0.012, 0.0)
		st.set_color(center); st.add_vertex(inner)
		st.set_color(petal); st.add_vertex(inner + d * pl * 0.5 - s)
		st.set_color(petal); st.add_vertex(inner + d * pl * 0.5 + s)
		st.set_color(petal); st.add_vertex(inner + d * pl * 0.5 - s)
		st.set_color(petal); st.add_vertex(outer)
		st.set_color(petal); st.add_vertex(inner + d * pl * 0.5 + s)
	st.generate_normals()
	return st.commit()


## Shrub — a dome of small leaf quads.
func _make_bush_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := 130
	var radius := 0.42
	for i in leaves:
		var dir := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.15, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
		var c := dir * radius * _rng.randf_range(0.5, 1.0) + Vector3(0.0, radius * 0.75, 0.0)
		var lit := clampf(c.y / (radius * 1.5), 0.0, 1.0)
		var col := Color(0.08, 0.19, 0.06).lerp(Color(0.22, 0.38, 0.13), lit) * _rng.randf_range(0.82, 1.12)
		var t := dir.cross(Vector3.UP)
		if t.length() < 0.01:
			t = Vector3(1, 0, 0)
		t = t.normalized()
		var b := dir.cross(t).normalized()
		var sz := _rng.randf_range(0.045, 0.085)
		var p0 := c - t * sz - b * sz
		var p1 := c + t * sz - b * sz
		var p2 := c + t * sz + b * sz
		var p3 := c - t * sz + b * sz
		for v in [p0, p1, p2, p0, p2, p3]:
			st.set_color(col); st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Fungi — a small cluster of capped mushrooms.
func _make_mushroom_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps := _rng.randi_range(2, 4)
	var cap_cols := [Color(0.68, 0.16, 0.12), Color(0.55, 0.40, 0.24), Color(0.86, 0.80, 0.62), Color(0.80, 0.50, 0.20)]
	var stem_col := Color(0.90, 0.88, 0.78)
	for m in caps:
		var off := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12))
		var sh := _rng.randf_range(0.05, 0.13)
		var sr := 0.014
		for axis in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			st.set_color(stem_col); st.add_vertex(off - axis * sr)
			st.set_color(stem_col); st.add_vertex(off + axis * sr)
			st.set_color(stem_col); st.add_vertex(off + Vector3(0.0, sh, 0.0))
		var cr := sh * _rng.randf_range(0.55, 0.95)
		var cy := off + Vector3(0.0, sh, 0.0)
		var apex := cy + Vector3(0.0, cr * 0.8, 0.0)
		var cc: Color = cap_cols[_rng.randi() % cap_cols.size()]
		var seg := 8
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			st.set_color(cc); st.add_vertex(apex)
			st.set_color(cc); st.add_vertex(cy + Vector3(cos(a0) * cr, 0.0, sin(a0) * cr))
			st.set_color(cc); st.add_vertex(cy + Vector3(cos(a1) * cr, 0.0, sin(a1) * cr))
	st.generate_normals()
	return st.commit()


## Waterside reeds — tall blades with the odd brown cattail head.
func _make_reed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.19, 0.30, 0.10)
	var tip_col := Color(0.42, 0.50, 0.22)
	var blades := _rng.randi_range(5, 9)
	for i in blades:
		var yaw := _rng.randf_range(0.0, TAU)
		var h := _rng.randf_range(0.9, 1.5)
		var lean := Vector3(cos(yaw), 0.0, sin(yaw)) * _rng.randf_range(0.05, 0.22) * h
		var side := Vector3(-sin(yaw), 0.0, cos(yaw)) * 0.022
		var top := Vector3(0.0, h, 0.0) + lean
		st.set_color(base_col); st.add_vertex(-side)
		st.set_color(base_col); st.add_vertex(side)
		st.set_color(tip_col); st.add_vertex(top)
	if _rng.randf() < 0.7:
		var hh := _rng.randf_range(0.7, 1.15)
		var brown := Color(0.34, 0.21, 0.10)
		var cy := Vector3(0.0, hh, 0.0)
		var r := 0.03
		var apex := cy + Vector3(0.0, 0.2, 0.0)
		var seg := 6
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			st.set_color(brown); st.add_vertex(cy + Vector3(cos(a0) * r, 0.0, sin(a0) * r))
			st.set_color(brown); st.add_vertex(cy + Vector3(cos(a1) * r, 0.0, sin(a1) * r))
			st.set_color(brown); st.add_vertex(apex)
	st.generate_normals()
	return st.commit()


## Broadleaf forest herb — a low rosette of a few big leaves.
func _make_herb_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.10, 0.22, 0.07)
	var tip_col := Color(0.20, 0.34, 0.11)
	var leaves := _rng.randi_range(4, 7)
	for i in leaves:
		var yaw := TAU * i / leaves + _rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(yaw), 0.0, sin(yaw))
		var L := _rng.randf_range(0.16, 0.32)
		var mid := d * L * 0.5 + Vector3(0.0, L * 0.5, 0.0)
		var tip := d * L + Vector3(0.0, L * 0.62, 0.0)
		var side := d.cross(Vector3.UP).normalized() * L * 0.24
		var b0 := Vector3(0.0, 0.02, 0.0)
		st.set_color(base_col); st.add_vertex(b0)
		st.set_color(tip_col); st.add_vertex(mid - side)
		st.set_color(tip_col); st.add_vertex(mid + side)
		st.set_color(tip_col); st.add_vertex(mid - side)
		st.set_color(tip_col); st.add_vertex(tip)
		st.set_color(tip_col); st.add_vertex(mid + side)
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
	["res://data/creatures/parasaurolophus.tres", 3, false],
	["res://data/creatures/stegosaurus.tres", 2, false],
	["res://data/creatures/triceratops.tres", 3, false],
	["res://data/creatures/gallimimus.tres", 3, false],
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
