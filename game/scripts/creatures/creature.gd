extends CharacterBody3D
class_name Creature
## Wildlife AI foundation — a living animal, not an enemy (North Star: Wildlife First).
##
## One script drives every species; behavior is read from `CreatureData`, so the
## world grows by adding data. Senses live in `Perception`, pathing in
## `NavigationAgent3D`. Behavior is a finite state machine with clear enter/exit
## hooks so new states (Feed, Drink, Sleep, Mate, Migrate) drop in without
## rewrites.
##
## Foundation states implemented (fully, no fakes — North Star Hard Rule #2):
##   IDLE, WANDER, INVESTIGATE, FLEE, HUNT, ATTACK, DEAD.

signal state_changed(new_state: State)
signal health_changed(current: float, maximum: float)
signal died(creature: Creature)

enum State { IDLE, WANDER, INVESTIGATE, FLEE, HUNT, ATTACK, DEAD }

@export var data: CreatureData
## Optional: preassigned home. If null, home is wherever the creature spawns.
@export var trophy_scene: PackedScene

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var perception: Perception = $Perception
@onready var body_mesh: MeshInstance3D = $BodyMesh

var _state: State = State.IDLE
var _state_time: float = 0.0          # seconds spent in the current state
var _health: float = 100.0
var _home: Vector3
var _target: Node3D                   # the player, when sensed
var _last_known_pos: Vector3          # where we last sensed the target
var _time_since_sensed: float = 999.0
var _attack_timer: float = 0.0
var _idle_wait: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _rig: CreatureRig
var _model: Node3D          # set instead of _rig when a real model is used
var _anim: AnimationPlayer  # the model's animations, when present
var _track_accum: float = 0.0
var _last_track_pos: Vector3
## Per-animal gait variation so a herd never moves in lockstep.
var _speed_mult: float = 1.0
## Score multiplier from the best shot placement landed on this animal
## (1.0 body, 1.25 vitals, 1.5 head) — applied to its trophy value on recovery.
var _kill_bonus: float = 1.0
var _call_t: float = 0.0            # ambient vocalization timer
## A wounded animal flees, bleeds a trail you can track, and slowly bleeds out —
## so a hit that doesn't drop it still rewards the hunter who follows.
var _wounded: bool = false
var _blood_accum: float = 0.0
var _blood_last: Vector3
## The ground speed the CURRENT gait animation is meant for. The model's leg
## cycle is scaled to actual speed against this, so feet track the ground
## (no foot-sliding). 0 = not a locomotion state (idle/attack), don't scale.
var _anim_ref_speed: float = 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group("wildlife")   # so the motion-tracker radar can ping us
	if data == null:
		push_warning("Creature has no CreatureData assigned; using defaults.")
		data = CreatureData.new()
	_health = data.max_health
	perception.configure(data)
	_build_visual()
	# Defer initial setup: the spawner sets our position AFTER add_child, so
	# capture home/territory in _post_ready (else _home would be the origin and
	# creatures would all wander toward the map center).
	call_deferred("_post_ready")


func _post_ready() -> void:
	_home = global_position          # now correctly positioned by the spawner
	_last_track_pos = global_position
	_speed_mult = _rng.randf_range(0.86, 1.14)
	_call_t = _rng.randf_range(2.0, 16.0)   # stagger so the dome isn't a chorus
	health_changed.emit(_health, data.max_health)
	_enter_state(State.IDLE)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_state_time += delta
	_time_since_sensed += delta
	_attack_timer = maxf(0.0, _attack_timer - delta)

	_sense_target()

	match _state:
		State.IDLE: _tick_idle(delta)
		State.WANDER: _tick_wander(delta)
		State.INVESTIGATE: _tick_investigate(delta)
		State.FLEE: _tick_flee(delta)
		State.HUNT: _tick_hunt(delta)
		State.ATTACK: _tick_attack(delta)

	_apply_gravity(delta)
	move_and_slide()

	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if _rig:
		_rig.animate(ground_speed, delta)
	elif _anim:
		_sync_gait(ground_speed)

	_maybe_drop_track(delta)
	_maybe_call(delta)
	_maybe_bleed(delta)


## A wounded animal bleeds a trail and slowly bleeds out — track it to finish it.
func _maybe_bleed(delta: float) -> void:
	if not _wounded or _state == State.DEAD:
		return
	# Slow bleed-out (scaled to the animal's size), so a solid hit pays off even
	# if it didn't drop on the spot.
	_health = maxf(0.0, _health - data.max_health * 0.02 * delta)
	health_changed.emit(_health, data.max_health)
	if _health <= 0.0:
		_die()
		return
	if not is_on_floor():
		return
	var flat := Vector2(global_position.x - _blood_last.x, global_position.z - _blood_last.z)
	_blood_accum += flat.length()
	_blood_last = global_position
	if _blood_accum >= 2.0 and Vector2(velocity.x, velocity.z).length() > 0.4:
		_blood_accum = 0.0
		_spawn_blood()


## A fading blood splash on the ground the player can follow.
func _spawn_blood() -> void:
	var fp := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	fp.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.03, 0.02, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fp.material_override = mat
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(fp)
	fp.global_position = global_position + Vector3.UP * 0.03
	fp.rotation = Vector3(-PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)
	var tw := fp.create_tween()
	tw.tween_interval(30.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 10.0)
	tw.tween_callback(fp.queue_free)


## Occasional positional vocalization — herbivores chirp, predators roar (pitch
## scales down with size, so a T-Rex is a deep bellow and a raptor a screech).
func _maybe_call(delta: float) -> void:
	_call_t -= delta
	if _call_t > 0.0:
		return
	# Predators call more when hunting; everyone is quieter at rest.
	var hunting := _state == State.HUNT or _state == State.ATTACK
	_call_t = _rng.randf_range(4.0, 9.0) if hunting else _rng.randf_range(9.0, 20.0)
	var name := "chirp" if data.diet == CreatureData.Diet.HERBIVORE else "roar"
	var pitch := clampf(2.2 / maxf(data.body_size.y, 0.5), 0.45, 1.8)
	Sfx.play_at(name, global_position + Vector3.UP * data.body_size.y * 0.6, pitch, 6.0)


## Match the model's leg-cycle playback to how fast it's actually moving so the
## feet grip the ground instead of skating. Idle/attack (ref 0) plays at 1x.
func _sync_gait(ground_speed: float) -> void:
	if _anim_ref_speed <= 0.01:
		_anim.speed_scale = 1.0
		return
	_anim.speed_scale = clampf(ground_speed / _anim_ref_speed, 0.35, 2.2)


# ---------------------------------------------------------------------------
# Perception → awareness
# ---------------------------------------------------------------------------

func _sense_target() -> void:
	var player := _find_player()
	if player == null:
		return
	# Nocturnal predators: sharper senses at night and in storms.
	var predator := data.diet != CreatureData.Diet.HERBIVORE
	var boost := 1.5 if predator and (GameState.is_night or GameState.storm_intensity > 0.5) else 1.0
	perception.sight_range = data.sight_range * boost
	perception.hearing_range = data.hearing_range * boost
	var loud := _is_player_loud(player)
	var facing := -global_transform.basis.z
	if perception.can_see(player, facing) or perception.can_hear(player, loud):
		_target = player
		_last_known_pos = player.global_position
		_time_since_sensed = 0.0
		_react_to_sensed_target()


## Decide what a fresh sighting means for THIS species.
func _react_to_sensed_target() -> void:
	if _state == State.DEAD:
		return
	if data.diet == CreatureData.Diet.HERBIVORE:
		# Prey animals bolt once a threat is inside their comfort distance.
		if global_position.distance_to(_last_known_pos) <= data.flee_distance:
			if _state != State.FLEE:
				_change_state(State.FLEE)
	else:
		# Predators/omnivores close in — and commit straight to the hunt after
		# dark or in a storm, when they're emboldened.
		if _state in [State.IDLE, State.WANDER]:
			var bold := data.is_aggressive or GameState.is_night or GameState.storm_intensity > 0.5
			_change_state(State.HUNT if bold else State.INVESTIGATE)


func _is_player_loud(player: Node) -> bool:
	# The player controller exposes `is_sprinting` when moving fast.
	return player.has_method("is_making_noise") and player.is_making_noise()


func _find_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

func _tick_idle(delta: float) -> void:
	var decel := data.walk_speed * 4.0 * delta
	velocity.x = move_toward(velocity.x, 0.0, decel)
	velocity.z = move_toward(velocity.z, 0.0, decel)
	if _state_time >= _idle_wait:
		_change_state(State.WANDER)


func _tick_wander(delta: float) -> void:
	# Judge arrival by real distance, not is_navigation_finished() — the latter
	# reports "finished" on the same frame the target is set (before the path
	# exists), which would bail out before the creature ever moves.
	if global_position.distance_to(nav.target_position) <= 1.5:
		_change_state(State.IDLE)
		return
	if _state_time > 12.0:  # unreachable target — give up and re-roll
		_change_state(State.IDLE)
		return
	_steer_along_path(data.walk_speed, delta)


func _tick_investigate(delta: float) -> void:
	# Curiosity: walk toward where the target was last sensed.
	if _time_since_sensed > data.alert_memory:
		_change_state(State.WANDER)  # lost interest → drift home
		return
	nav.target_position = _last_known_pos
	if global_position.distance_to(_last_known_pos) <= 2.5:
		# Reached the spot. Aggressive types commit; others lose their nerve.
		if data.is_aggressive:
			_change_state(State.HUNT)
		else:
			_change_state(State.WANDER)
		return
	_steer_along_path(data.walk_speed, delta)


func _tick_flee(delta: float) -> void:
	var threat := _last_known_pos
	var dist := global_position.distance_to(threat)
	# Safe once the threat is far AND we haven't sensed it for a while.
	if dist > data.flee_distance * 1.75 and _time_since_sensed > data.alert_memory:
		_change_state(State.IDLE)
		return
	# Re-pick a flee point directly away from the threat periodically (not every
	# frame — the path needs time to compute) or once the current one is reached.
	if _state_time_expired(1.0) or global_position.distance_to(nav.target_position) < 2.0:
		var away := (global_position - threat)
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		nav.target_position = global_position + away.normalized() * 12.0
		_state_time = 0.0
	_steer_along_path(data.run_speed, delta)


func _tick_hunt(delta: float) -> void:
	if _target == null or _time_since_sensed > data.alert_memory:
		# Lost the trail — go check the last spot before giving up.
		_change_state(State.INVESTIGATE)
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist <= data.attack_range:
		_change_state(State.ATTACK)
		return
	nav.target_position = _target.global_position
	_steer_along_path(data.run_speed, delta)


func _tick_attack(delta: float) -> void:
	var decel := data.run_speed * 5.0 * delta
	velocity.x = move_toward(velocity.x, 0.0, decel)
	velocity.z = move_toward(velocity.z, 0.0, decel)
	if _target == null:
		_change_state(State.HUNT)
		return
	var dist := global_position.distance_to(_target.global_position)
	if dist > data.attack_range * 1.3:
		_change_state(State.HUNT)
		return
	_face_toward(_target.global_position, delta)
	if _attack_timer <= 0.0:
		_attack_timer = data.attack_cooldown
		_deal_attack_damage()


# ---------------------------------------------------------------------------
# Combat + death
# ---------------------------------------------------------------------------

## Public API — weapons, hazards, or other creatures call this. `hit_point` (if
## given) enables shot placement: head and vital hits hurt more and score more.
## Returns the zone hit ("HEAD" / "VITAL" / "BODY" / "") for HUD feedback.
func take_damage(amount: float, from_position: Vector3 = global_position, hit_point: Vector3 = Vector3.INF) -> String:
	if _state == State.DEAD:
		return ""
	var zone := ""
	var dmg_mult := 1.0
	if hit_point.x != INF and data.body_size.y > 0.1:
		var rel := (hit_point.y - global_position.y) / data.body_size.y   # 0 feet .. 1 crown
		if rel > 0.8:
			zone = "HEAD"; dmg_mult = 2.5; _kill_bonus = 1.5
		elif rel > 0.48:
			zone = "VITAL"; dmg_mult = 1.6; _kill_bonus = maxf(_kill_bonus, 1.25)
		else:
			zone = "BODY"
	_health = maxf(0.0, _health - amount * dmg_mult)
	health_changed.emit(_health, data.max_health)
	_last_known_pos = from_position
	_time_since_sensed = 0.0
	if not _wounded:
		_blood_last = global_position
	_wounded = true
	if _health <= 0.0:
		_die()
		return zone
	# Being hurt overrides calm behavior.
	if data.diet == CreatureData.Diet.HERBIVORE or not data.is_aggressive:
		_change_state(State.FLEE)
	else:
		_target = _find_player()
		_change_state(State.HUNT)
	return zone


## A gunshot went off nearby — prey bolt, predators come to investigate.
func hear_shot(from: Vector3) -> void:
	if _state == State.DEAD:
		return
	_last_known_pos = from
	_time_since_sensed = 0.0
	if data.diet == CreatureData.Diet.HERBIVORE:
		_change_state(State.FLEE)
	elif _state in [State.IDLE, State.WANDER]:
		_change_state(State.INVESTIGATE)


func _deal_attack_damage() -> void:
	if _target != null and _target.has_method("apply_damage"):
		_target.apply_damage(data.attack_damage)


func _die() -> void:
	_change_state(State.DEAD)
	velocity = Vector3.ZERO
	# Drop from the physics/creature layers so it no longer blocks or is chased.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if _anim:
		_play_anim("Death")            # real model has a death animation
	elif _rig:
		_rig.rotation_degrees.z = 90.0 # procedural rig just topples over
		_rig.position.y = 0.4
	var pitch := clampf(2.2 / maxf(data.body_size.y, 0.5), 0.45, 1.8) * 0.8   # pained, lower
	Sfx.play_at("chirp" if data.diet == CreatureData.Diet.HERBIVORE else "roar", global_position + Vector3.UP, pitch, 5.0)
	_spawn_trophy()
	died.emit(self)


func _spawn_trophy() -> void:
	if trophy_scene == null:
		return
	var trophy := trophy_scene.instantiate()
	get_parent().add_child(trophy)
	trophy.global_position = global_position + Vector3.UP * 0.3
	if trophy.has_method("setup_from_creature"):
		trophy.setup_from_creature(data)
	if trophy.has_method("set_bonus"):
		trophy.set_bonus(_kill_bonus)


# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------

func _steer_along_path(speed: float, delta: float) -> void:
	# Resilient locomotion: follow the navmesh path when one exists (it routes
	# around trees/ruins), but fall back to steering straight at the goal when the
	# navigation map has no usable path. Either way the creature keeps moving;
	# CharacterBody3D collision makes it slide around obstacles in the fallback.
	# Follow the navmesh path (it routes around trees/ruins) by heading for the
	# first path point that is meaningfully ahead HORIZONTALLY. The navmesh sits
	# below the agent's feet, so the nearest path points are "underfoot" (only a Y
	# offset) — skipping them by horizontal distance avoids steering straight down
	# and stalling. Falls back to the goal if the path has no usable waypoint.
	var pos := global_position
	var wp := nav.target_position
	for p in nav.get_current_navigation_path():
		var d := p - pos
		d.y = 0.0
		if d.length() > 1.5:
			wp = p
			break

	var target_speed := speed * _speed_mult
	var dir := wp - pos
	dir.y = 0.0
	if dir.length() < 0.4:
		# Ease to a stop rather than halting on a dime.
		var decel := target_speed * 3.5 * delta
		velocity.x = move_toward(velocity.x, 0.0, decel)
		velocity.z = move_toward(velocity.z, 0.0, decel)
		return
	dir = dir.normalized()
	# Turn first, then drive forward along the way we're actually facing, and only
	# reach full speed once roughly aligned — animals slow through sharp turns
	# instead of sliding sideways at top speed.
	_face_toward(pos + dir, delta)
	var facing := -global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var align := clampf(facing.dot(dir), 0.0, 1.0)
	var want := facing * target_speed * lerpf(0.45, 1.0, align)
	var accel := target_speed / 0.35 * delta   # reach cruising speed in ~0.35s
	velocity.x = move_toward(velocity.x, want.x, accel)
	velocity.z = move_toward(velocity.z, want.z, accel)


func _maybe_drop_track(_delta: float) -> void:
	if not is_on_floor():
		return
	var flat := Vector2(global_position.x - _last_track_pos.x, global_position.z - _last_track_pos.z)
	_track_accum += flat.length()
	_last_track_pos = global_position
	var spacing := maxf(1.2, data.body_size.z * 0.55)
	if _track_accum >= spacing and Vector2(velocity.x, velocity.z).length() > 0.5:
		_track_accum = 0.0
		_spawn_track()


## Leaves a fading footprint the player can track (hunting depth).
func _spawn_track() -> void:
	var fp := MeshInstance3D.new()
	var q := QuadMesh.new()
	var sz := clampf(data.body_size.x * 0.5, 0.2, 1.1)
	q.size = Vector2(sz, sz * 1.6)
	fp.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.09, 0.06, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fp.material_override = mat
	# Parent to the scene root, NOT the Creatures node (keeps that node creatures-only).
	var host := get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(fp)
	fp.global_position = global_position + Vector3.UP * 0.04
	fp.rotation = Vector3(-PI * 0.5, rotation.y, 0.0)
	# Fade out and self-remove so tracks read as fresh vs. old.
	var tw := fp.create_tween()
	tw.tween_interval(20.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 8.0)
	tw.tween_callback(fp.queue_free)


func _face_toward(world_point: Vector3, delta: float) -> void:
	var to := world_point - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	# Rig forward is -Z, so aim -Z along `to` (atan2(-x,-z)), not +Z — otherwise
	# the creature faces away from motion and appears to walk backwards.
	var desired := atan2(-to.x, -to.z)
	rotation.y = rotate_toward(rotation.y, desired, data.turn_speed * delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _pick_wander_target() -> void:
	# Sample a point near the current spot so movement reads as short, natural
	# steps — grazers browse in tight loops, others roam a bit wider — instead of
	# marching in a straight line to the edge of the territory.
	var step := 18.0 if data.diet == CreatureData.Diet.HERBIVORE else 32.0
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(4.0, step)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius
	# Keep it inside the home territory so animals don't drift off.
	var goal := global_position + offset
	if goal.distance_to(_home) > data.territory_radius:
		goal = _home + (goal - _home).normalized() * data.territory_radius
	nav.target_position = goal


func _state_time_expired(seconds: float) -> bool:
	return _state_time >= seconds


# ---------------------------------------------------------------------------
# State machine plumbing
# ---------------------------------------------------------------------------

func _change_state(new_state: State) -> void:
	if new_state == _state:
		return
	_exit_state(_state)
	_enter_state(new_state)


func _enter_state(new_state: State) -> void:
	_state = new_state
	_state_time = 0.0
	_anim_ref_speed = 0.0
	match new_state:
		State.IDLE:
			# Grazers linger and browse; predators are restless and move on sooner.
			if data.diet == CreatureData.Diet.HERBIVORE:
				_idle_wait = _rng.randf_range(4.0, 9.0)
			else:
				_idle_wait = _rng.randf_range(1.5, 4.0)
			# In bad weather, wildlife hunkers down instead of roaming.
			if GameState.storm_intensity > 0.6:
				_idle_wait *= 2.5
			_play_anim("Idle")
		State.WANDER:
			_pick_wander_target()
			_anim_ref_speed = data.walk_speed
			_play_anim("Walk")
		State.INVESTIGATE:
			_anim_ref_speed = data.walk_speed
			_play_anim("Walk")
		State.FLEE, State.HUNT:
			_anim_ref_speed = data.run_speed
			_play_anim("Run")
		State.ATTACK:
			_play_anim("Attack")
	state_changed.emit(new_state)


func _exit_state(_old_state: State) -> void:
	pass


# ---------------------------------------------------------------------------
# Appearance — stylized procedural rig (seed for final sculpted models)
# ---------------------------------------------------------------------------

## Real CC0 animated models (Quaternius) mapped by species; the rest fall back
## to the procedural rig. Predators without a dedicated model reuse the T-Rex.
const MODEL_PATHS := {
	&"velociraptor": "res://assets/creatures/velociraptor.glb",
	&"tyrannosaurus": "res://assets/creatures/trex.glb",
	&"triceratops": "res://assets/creatures/triceratops.glb",
	&"brachiosaurus": "res://assets/creatures/apatosaurus.glb",
	&"parasaurolophus": "res://assets/creatures/parasaurolophus.glb",
	&"stegosaurus": "res://assets/creatures/stegosaurus.glb",
	&"allosaurus": "res://assets/creatures/trex.glb",
	&"spinosaurus": "res://assets/creatures/trex.glb",
	# Real modern Ozark fauna (CC0).
	&"whitetail_deer": "res://assets/creatures/deer.glb",
	&"black_bear": "res://assets/creatures/bear.glb",
}

## Species whose models ship with their own textures — never tint these.
const REAL_FAUNA := [&"whitetail_deer", &"black_bear"]


func _build_visual() -> void:
	if body_mesh:
		body_mesh.visible = false  # hide the old debug box
	var scene: PackedScene = data.model_scene   # explicit override wins
	if scene == null and MODEL_PATHS.has(data.species_id):
		var p: String = MODEL_PATHS[data.species_id]
		if ResourceLoader.exists(p):
			scene = load(p)
	if scene != null:
		_model = scene.instantiate()
		add_child(_model)
		_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		# Dinosaurs import as flat, untextured meshes — tint them their species
		# colour for variety. Real Ozark fauna (deer/bear/etc.) ship with their
		# own textures, so leave those alone.
		if not REAL_FAUNA.has(data.species_id):
			_tint_model(data.placeholder_color)
		_fit_model()
		_play_anim("Idle")
		return
	_rig = CreatureRig.new()
	add_child(_rig)
	_rig.build(data)


## Tint an imported model with the species colour (they import flat grey).
## A darker belly-ish variant would need per-surface data; one tone reads clean.
func _tint_model(color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# Fresh imports have no override materials, so iterate the mesh's own
		# surfaces and override each one.
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, mat)


## Scale a real model to the species size, sit it on the ground, and face -Z.
func _fit_model() -> void:
	_model.rotation.y = PI            # Quaternius models face +Z; our forward is -Z
	await get_tree().process_frame    # let global transforms settle
	var a := _world_aabb(_model)
	if a.size.y > 0.01:
		_model.scale *= clampf(data.body_size.y / a.size.y, 0.02, 60.0)
	await get_tree().process_frame
	var b := _world_aabb(_model)
	if b.size.y > 0.0:
		_model.global_position.y += global_position.y - b.position.y   # feet to ground


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


## Play the model animation whose name ends with `suffix` (e.g. "Walk").
func _play_anim(suffix: String) -> void:
	if _anim == null:
		return
	for a in _anim.get_animation_list():
		if a.to_lower().ends_with(suffix.to_lower()):
			if _anim.current_animation != a:
				_anim.play(a)
			return


# ---------------------------------------------------------------------------
# Introspection (used by debug HUD / tests)
# ---------------------------------------------------------------------------

## Route this creature on a specific navigation map (the dome's dedicated map).
func use_navigation_map(map: RID) -> void:
	if map.is_valid():
		nav.set_navigation_map(map)


## Field-guide readout shown when scanned through binoculars.
func get_scan_text() -> String:
	var threat := "Passive grazer"
	if data.is_apex:
		threat = "APEX — EXTREME"
	elif data.is_aggressive:
		threat = "Predator — High"
	elif data.diet == CreatureData.Diet.OMNIVORE:
		threat = "Dangerous if provoked"
	var stars := ""
	for i in data.rarity:
		stars += "*"
	return "%s\nThreat: %s\nTrophy: %d  %s" % [data.display_name, threat, data.trophy_value, stars]


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return State.keys()[_state]


func get_health() -> float:
	return _health
