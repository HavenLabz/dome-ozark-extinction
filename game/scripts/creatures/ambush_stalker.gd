extends CharacterBody3D
class_name AmbushStalker
## The dome's signature terror (inspired by the Three Brothers): a burrowing
## apex that lurks UNDERGROUND, tracking you by sound. Make noise — sprint,
## fire — and it homes in; get close while it's loud-tracked and it ERUPTS from
## the earth in a burst of dirt, savages you, then submerges and relocates. It's
## bolder at night, and extremely tough. It reads your scent gear: a scent mask
## keeps it guessing.

enum S { LURK, EMERGE, ATTACK, SUBMERGE }

const LURK_DEPTH := 6.0        # how far below ground it hides
const EMERGE_NOISE_RANGE := 34.0
const EMERGE_CLOSE_RANGE := 9.0
const MELEE_RANGE := 3.2
const DAMAGE := 34.0
const ATTACK_CD := 1.3

var _state: int = S.LURK
var _t: float = 0.0
var _health: float = 900.0
var _attack_t: float = 0.0
var _player: Node3D
var _model: Node3D
var _terrain: TerrainGenerator
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _target_xz := Vector2.ZERO


func setup(terrain: TerrainGenerator) -> void:
	_terrain = terrain


func _ready() -> void:
	add_to_group("wildlife")
	collision_layer = 4          # creature layer (weapons hit this)
	collision_mask = 1           # collide with world
	_rng.randomize()
	_build_model()
	call_deferred("_post")


func _post() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_enter(S.LURK)


func _build_model() -> void:
	# A real raptor model, tinted to a black armoured horror and scaled up.
	var path := "res://assets/creatures/velociraptor.glb"
	if ResourceLoader.exists(path):
		_model = (load(path) as PackedScene).instantiate()
		add_child(_model)
		_model.rotation.y = PI
		await get_tree().process_frame
		var aabb := _world_aabb(_model)
		if aabb.size.y > 0.01:
			var s := 3.4 / aabb.size.y
			_model.scale = Vector3(s, s, s)
			await get_tree().process_frame
			var b := _world_aabb(_model)
			_model.global_position.y += global_position.y - b.position.y
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.06, 0.06, 0.08)
			mat.metallic = 0.3
			mat.roughness = 0.6
			mat.emission_enabled = true
			mat.emission = Color(0.7, 0.05, 0.03)   # smouldering red skin/eyes
			mat.emission_energy_multiplier = 0.15
			for si in m.mesh.get_surface_count():
				m.set_surface_override_material(si, mat)
	# Add a physics body so it can't fall through the world when surfaced.
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.0
	cap.height = 3.4
	col.shape = cap
	col.position.y = 1.7
	add_child(col)


func _physics_process(delta: float) -> void:
	_t += delta
	_attack_t = maxf(0.0, _attack_t - delta)
	if _player == null:
		return
	# Feed the "being hunted" heartbeat cue.
	var dist := global_position.distance_to(_player.global_position)
	match _state:
		S.ATTACK: GameState.danger = 1.0
		S.EMERGE: GameState.danger = 0.9
		S.SUBMERGE: GameState.danger = 0.25
		_: GameState.danger = clampf(1.0 - dist / 45.0, 0.0, 0.65)
	match _state:
		S.LURK: _tick_lurk(delta)
		S.EMERGE: _tick_emerge(delta)
		S.ATTACK: _tick_attack(delta)
		S.SUBMERGE: _tick_submerge(delta)


func _tick_lurk(delta: float) -> void:
	# Creep, submerged, toward the player's ground position.
	var pp := _player.global_position
	var here := global_position
	var to := Vector3(pp.x - here.x, 0.0, pp.z - here.z)
	var dist := to.length()
	var speed := 7.0 if GameState.is_night else 5.0
	if dist > 1.0:
		var dir := to.normalized()
		global_position += dir * speed * delta
	# Stay buried under the surface.
	global_position.y = _ground_y(global_position) - LURK_DEPTH

	# Trigger: player is loud within range, or simply very close.
	var loud: bool = _player.has_method("is_making_noise") and _player.is_making_noise()
	var noise_r := EMERGE_NOISE_RANGE * (1.3 if GameState.is_night else 1.0)
	if (loud and dist < noise_r) or dist < EMERGE_CLOSE_RANGE:
		_enter(S.EMERGE)


func _tick_emerge(delta: float) -> void:
	# Rise fast out of the ground.
	var target_y := _ground_y(global_position)
	global_position.y = move_toward(global_position.y, target_y, 22.0 * delta)
	_face_player(delta)
	if global_position.y >= target_y - 0.1:
		_enter(S.ATTACK)


func _tick_attack(delta: float) -> void:
	global_position.y = _ground_y(global_position)
	var pp := _player.global_position
	var to := Vector3(pp.x - global_position.x, 0.0, pp.z - global_position.z)
	var dist := to.length()
	_face_player(delta)
	if dist > MELEE_RANGE:
		global_position += to.normalized() * 11.0 * delta   # lunge
	elif _attack_t <= 0.0:
		_attack_t = ATTACK_CD
		if _player.has_method("apply_damage"):
			_player.apply_damage(DAMAGE)
	# Give up the surface assault after a while or if the player breaks contact.
	if _t > 7.0 or dist > 22.0:
		_enter(S.SUBMERGE)


func _tick_submerge(delta: float) -> void:
	global_position.y = move_toward(global_position.y, _ground_y(global_position) - LURK_DEPTH, 16.0 * delta)
	if global_position.y <= _ground_y(global_position) - LURK_DEPTH + 0.1:
		_enter(S.LURK)


func _enter(s: int) -> void:
	_state = s
	_t = 0.0
	if _model:
		_model.visible = s == S.EMERGE or s == S.ATTACK
	if s == S.EMERGE:
		Sfx.play_at("roar", global_position + Vector3.UP, 0.5, 8.0)
		_dirt_burst()


## Weapons call this. Very tough; only vulnerable while surfaced.
func take_damage(amount: float, _from: Vector3 = global_position, _hit: Vector3 = Vector3.INF) -> String:
	if _state == S.LURK or _state == S.SUBMERGE:
		return ""   # can't be hurt underground
	_health -= amount
	if _health <= 0.0:
		Sfx.play_at("roar", global_position + Vector3.UP, 0.4, 8.0)
		GameState.collect_trophy(&"stalker_trophy", 1500)
		GameState.danger = 0.0
		queue_free()
	return "BODY"


func _dirt_burst() -> void:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.2
	pm.scale_max = 0.5
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 0.2, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.23, 0.15)
	mesh.material = mat
	p.draw_pass_1 = mesh
	add_child(p)
	p.global_position = global_position + Vector3(0, 0.3, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _face_player(delta: float) -> void:
	var to := _player.global_position - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	var desired := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, desired, 5.0 * delta)


func _ground_y(at: Vector3) -> float:
	return _terrain.surface_point(at.x, at.z).y if _terrain else 0.0


func _world_aabb(root: Node) -> AABB:
	var out := AABB()
	var started := false
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var world := vi.global_transform * vi.get_aabb()
		if not started:
			out = world
			started = true
		else:
			out = out.merge(world)
	return out
