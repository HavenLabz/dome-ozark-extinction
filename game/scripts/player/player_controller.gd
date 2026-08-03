extends CharacterBody3D
## First-person player controller — movement, survival hooks, weapons.
## Expandable for injuries, equipment, vehicles, multiplayer later.

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.0
@export var prone_speed: float = 1.2
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var stamina_drain_sprint: float = 12.0
@export var stamina_regen: float = 18.0

enum Stance { STAND, CROUCH, PRONE }

@export_group("Interaction")
## Reach of the "look at it and press E" interaction ray.
@export var interact_range: float = 3.0

@export_group("Weapons")
@export var weapon_loadout: Array[WeaponData] = []
@export var default_fov: float = 75.0
@export var ads_fov: float = 50.0

## Emitted when the interaction ray gains/loses a valid target (HUD prompt).
signal interact_prompt_changed(text: String)
## Emitted when the active weapon changes (HUD binds to the new weapon).
signal weapon_changed(weapon: Weapon)
## Emitted with a creature's field-guide text while scanning through binoculars
## (empty string clears it).
signal scan_info_changed(text: String)
## Emitted when a shot connects, so the HUD can flash a hitmarker.
signal hitmarker(on_creature: bool)
## Emitted on a well-placed hit ("HEAD" / "VITAL") for a HUD callout.
signal crit_hit(zone: String)
## Emitted when the scope overlay should show/hide (true when ADS with a scope).
signal scope_changed(active: bool, optic_name: String)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const _MASK_INTERACTABLES := 16
const _MASK_CREATURES := 4
const WEAPON_SCENE := preload("res://scripts/weapons/weapon.gd")

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stance: int = Stance.STAND
var _is_sprinting: bool = false
var _current_prompt: String = ""
# Capsule heights and eye heights per stance.
const _CAP_H := {Stance.STAND: 1.8, Stance.CROUCH: 1.1, Stance.PRONE: 0.5}
const _EYE_Y := {Stance.STAND: 1.6, Stance.CROUCH: 0.95, Stance.PRONE: 0.4}

var _weapons: Array[Weapon] = []
var _weapon_idx: int = -1
var _ads: bool = false
var _holding_breath: bool = false
var _scope_active: bool = false
var _scanning: bool = false
var _recoil_pitch: float = 0.0   # accumulated, recovered each frame
var _recoil_yaw: float = 0.0


var _flashlight: SpotLight3D
var _step_t: float = 0.0
var _blinds_built: int = 0
var _shake: float = 0.0            # camera trauma (fire/impact), decays
var _bob_t: float = 0.0            # head-bob phase
var _base_cam_pos: Vector3
var _rng := RandomNumberGenerator.new()
# First-person legs from the rigged character, walked procedurally (the model
# ships with no locomotion clips). Upper body hidden so it never clips the cam.
var _skel: Skeleton3D
var _leg_bones := {}          # key -> {"idx": int, "rest": Quaternion}
var _stride: float = 0.0
var _force_pose: bool = false  # debug: --shotlegs keeps upper body + walks in place

## Emitted when the player is hurt, so the HUD can flash a damage vignette.
signal damaged(amount: float)


## Add camera trauma (screen shake). Clamped so it can't runaway.
func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = default_fov
	_base_cam_pos = camera.position
	_build_weapons()
	# Flashlight gear (toggle L) — points where you look; off by default.
	_flashlight = SpotLight3D.new()
	_flashlight.light_color = Color(1.0, 0.97, 0.9)
	_flashlight.light_energy = 6.0
	_flashlight.spot_range = 40.0
	_flashlight.spot_angle = 32.0
	_flashlight.spot_attenuation = 0.6
	_flashlight.visible = false
	camera.add_child(_flashlight)
	_build_body()


## A first-person clothed body — torso, legs, boots — parented to the yaw head so
## it turns with you but stays upright when you look down (you see your own gear).
func _build_body() -> void:
	var scene := load("res://assets/character.glb") as PackedScene
	if scene == null:
		return
	var body := scene.instantiate() as Node3D
	body.name = "FPBody"
	head.add_child(body)
	# Fit to ~1.85m from the model's actual assembled size, feet on the ground.
	var box := _model_local_aabb(body, Transform3D.IDENTITY)
	var s := 1.85 / maxf(box.size.y, 0.01)
	body.scale = Vector3(s, s, s)
	body.position = Vector3(0.0, -_EYE_Y[Stance.STAND] - box.position.y * s, 0.12)
	body.rotation.y = PI          # face the way we look (-Z)

	_skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel == null:
		return
	# Stop the imported AnimationPlayer (it only holds an A-pose) so our manual
	# bone poses actually stick.
	var ap := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		ap.active = false
	# Hide the upper body (spine → torso/arms/head) so the FP camera stays clean —
	# only hips + legs remain, CoD-style first-person legs.
	_force_pose = "--shotlegs" in OS.get_cmdline_user_args()
	var sp := _skel.find_bone("spine1_01")
	if sp >= 0 and not _force_pose:
		_skel.set_bone_pose_scale(sp, Vector3(0.001, 0.001, 0.001))
	# Cache leg bones + their rest rotations for the procedural walk.
	for key in {"lthigh": "l leg_047", "rthigh": "r leg_051", "lknee": "l knee_048", "rknee": "r knee_052"}:
		var idx := _skel.find_bone({"lthigh": "l leg_047", "rthigh": "r leg_051", "lknee": "l knee_048", "rknee": "r knee_052"}[key])
		if idx >= 0:
			_leg_bones[key] = {"idx": idx, "rest": _skel.get_bone_pose_rotation(idx)}


## Combined mesh AABB of a model in its own local space (no tree needed).
func _model_local_aabb(node: Node, xf: Transform3D) -> AABB:
	var acc := {}
	_accum_model_aabb(node, xf, acc)
	return acc.get("b", AABB(Vector3.ZERO, Vector3.ONE))


func _accum_model_aabb(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var lx := xf
	if node is Node3D:
		lx = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var b: AABB = lx * (node as MeshInstance3D).mesh.get_aabb()
		acc["b"] = (acc["b"] as AABB).merge(b) if acc.has("b") else b
	for c in node.get_children():
		_accum_model_aabb(c, lx, acc)


## Procedural walk/run cycle on the FP legs — thighs swing opposite, knees bend
## on the back-swing, amplitude scales with speed. (Real Mixamo clips would drop
## in over this.) ponytail: flexion axis is X; tune sign if a leg bends backward.
func _animate_legs(delta: float) -> void:
	if _skel == null or _leg_bones.is_empty():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := is_on_floor() and speed > 0.4 and _stance != Stance.PRONE
	if moving:
		_stride += delta * (4.0 + speed * 1.3)
	if _force_pose:
		_stride = PI * 0.5   # debug: freeze at max leg-split to check the axis
	var amp := (0.7 if _force_pose else clampf(speed / 6.0, 0.0, 1.0) * 0.7)
	var sw := sin(_stride) * amp
	_pose_leg("lthigh", sw)
	_pose_leg("rthigh", -sw)
	_pose_leg("lknee", maxf(0.0, -sw) * 1.1)
	_pose_leg("rknee", maxf(0.0, sw) * 1.1)


func _pose_leg(key: String, angle: float) -> void:
	var b: Dictionary = _leg_bones.get(key, {})
	if b.is_empty():
		return
	var idx: int = b["idx"]
	# Flex about the skeleton's left-right axis (X) so the leg swings fore/aft.
	# That world axis, expressed in the parent bone's frame, is what a local pose
	# rotation must use — the bone's own local X points down the limb (twist).
	var pidx := _skel.get_bone_parent(idx)
	var pbasis := (_skel.get_bone_global_pose(pidx).basis if pidx >= 0 else Basis())
	var axis := (pbasis.inverse() * Vector3.RIGHT).normalized()
	_skel.set_bone_pose_rotation(idx, Quaternion(axis, angle) * (b["rest"] as Quaternion))


func _build_weapons() -> void:
	# Use the loadout chosen on the deployment screen, if any.
	if not GameState.loadout_weapons.is_empty():
		weapon_loadout = []
		for p in GameState.loadout_weapons:
			var wd := load(p) as WeaponData
			if wd:
				weapon_loadout.append(wd)
	if weapon_loadout.is_empty():
		weapon_loadout = [
			load("res://data/weapons/ar15.tres"),
			load("res://data/weapons/m1911.tres"),
		]
	for wd in weapon_loadout:
		_spawn_weapon(wd)
	if not _weapons.is_empty():
		_switch_weapon(0)


func _spawn_weapon(wd: WeaponData) -> Weapon:
	var w := WEAPON_SCENE.new() as Weapon
	w.data = wd
	w.visible = false
	camera.add_child(w)
	w.shot_hit.connect(func(on_creature): hitmarker.emit(on_creature))
	w.zone_hit.connect(func(zone): crit_hit.emit(zone))
	_weapons.append(w)
	return w


## Add a weapon found in the world (fallen soldier / outpost). Returns false if
## the player already carries it (caller can then hand over ammo instead).
func add_weapon(wd: WeaponData) -> bool:
	if wd == null:
		return false
	for w in _weapons:
		if w.data and w.data.weapon_id == wd.weapon_id:
			return false
	_spawn_weapon(wd)
	_switch_weapon(_weapons.size() - 1)
	weapon_changed.emit(_current_weapon())
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	# Scroll wheel cycles through carried weapons.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("reload"):
		var w := _current_weapon()
		if w:
			w.reload()
	elif event.is_action_pressed("weapon_1"):
		_switch_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		_switch_weapon(1)
	elif event.is_action_pressed("optic_cycle"):
		var w := _current_weapon()
		if w:
			w.cycle_optic()
	elif event.is_action_pressed("flashlight"):
		_flashlight.visible = not _flashlight.visible
	elif event.is_action_pressed("extract"):
		var ex := get_tree().get_first_node_in_group("extraction")
		if ex:
			ex.begin_extraction(global_position)
	elif event.is_action_pressed("supply_drop"):
		_call_supply_drop()
	elif event.is_action_pressed("build"):
		_build_blind()


## Place a hunting blind ahead of the player — three walls + roof, open toward
## the way you're facing. Its walls block creatures' line of sight (they raycast
## against world geometry), so it's real concealment for an ambush. Limit 3.
func _build_blind() -> void:
	if _blinds_built >= 3:
		scan_info_changed.emit("Blind limit reached (3).")
		get_tree().create_timer(2.0).timeout.connect(func(): scan_info_changed.emit(""))
		return
	_blinds_built += 1
	var yaw: float = head.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var base := global_position + fwd * 2.2
	base.y = global_position.y - 0.9   # roughly ground at feet

	var blind := StaticBody3D.new()
	blind.collision_layer = 1
	blind.collision_mask = 0
	blind.position = base
	blind.rotation.y = yaw
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.22, 0.13)   # burlap / branches
	mat.roughness = 0.95
	# back + two sides + a low roof, open front (local -Z faces outward).
	_blind_panel(blind, Vector3(1.8, 1.7, 0.12), Vector3(0, 0.85, 0.9), mat)   # back
	_blind_panel(blind, Vector3(0.12, 1.7, 1.8), Vector3(-0.9, 0.85, 0), mat)  # left
	_blind_panel(blind, Vector3(0.12, 1.7, 1.8), Vector3(0.9, 0.85, 0), mat)   # right
	_blind_panel(blind, Vector3(1.8, 0.12, 1.9), Vector3(0, 1.7, 0), mat)      # roof
	get_tree().current_scene.add_child(blind)
	scan_info_changed.emit("Hunting blind built. (%d/3)" % _blinds_built)
	get_tree().create_timer(2.0).timeout.connect(func(): scan_info_changed.emit(""))


func _blind_panel(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	mesh.position = pos
	mesh.material_override = mat
	parent.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	parent.add_child(col)


## The one supply drop per hunt (Carnivores-style): refills every weapon and
## tops up rations. Once per deployment.
func _call_supply_drop() -> void:
	if GameState.supply_used:
		scan_info_changed.emit("Supply drop already used this hunt.")
	else:
		GameState.supply_used = true
		for w in _weapons:
			w.resupply()
		GameState.hunger = minf(100.0, GameState.hunger + 25.0)
		GameState.hydration = minf(100.0, GameState.hydration + 25.0)
		scan_info_changed.emit("SUPPLY DROP — ammunition and rations resupplied.")
	get_tree().create_timer(3.0).timeout.connect(func(): scan_info_changed.emit(""))


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_stance(delta)
	_handle_movement(delta)
	_regen_stamina(delta)
	move_and_slide()
	_update_interact_prompt()
	_handle_weapons(delta)
	_handle_footsteps(delta)
	_animate_legs(delta)
	_update_camera_fx(delta)


## Screen shake + subtle head-bob, applied as a camera-local offset each frame.
func _update_camera_fx(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 1.8)
	var shake := Vector3.ZERO
	if _shake > 0.0:
		var s := _shake * _shake * 0.12
		shake = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * s
	var bob := Vector3.ZERO
	var speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed > 0.6 and not _ads:
		_bob_t += delta * (10.0 if _is_sprinting else 7.0)
		var amp := (0.035 if _is_sprinting else 0.02)
		bob = Vector3(cos(_bob_t) * amp, absf(sin(_bob_t)) * amp, 0.0)
	camera.position = _base_cam_pos + shake + bob


func _handle_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 0.6 or _stance == Stance.PRONE:
		_step_t = 0.15
		return
	_step_t -= delta
	if _step_t <= 0.0:
		# Faster cadence when moving faster; softer when crouched.
		_step_t = clampf(3.2 / maxf(speed, 1.0), 0.28, 0.6)
		Sfx.play("step", _rng.randf_range(0.9, 1.1), -20.0 if _stance == Stance.CROUCH else -14.0)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and _stance == Stance.STAND:
		velocity.y = jump_velocity


func _handle_stance(delta: float) -> void:
	# Prone toggles (Z); crouch is hold (Ctrl); prone wins over crouch.
	if Input.is_action_just_pressed("prone"):
		_stance = Stance.STAND if _stance == Stance.PRONE else Stance.PRONE
	elif _stance != Stance.PRONE:
		_stance = Stance.CROUCH if Input.is_action_pressed("crouch") else Stance.STAND
	elif Input.is_action_just_pressed("jump"):
		_stance = Stance.STAND   # jump key stands you up from prone

	# Resize capsule + smoothly lower the eye height.
	var shape := collision_shape.shape as CapsuleShape3D
	if shape:
		var h: float = _CAP_H[_stance]
		shape.height = h
		collision_shape.position.y = h * 0.5
	head.position.y = lerpf(head.position.y, _EYE_Y[_stance], clampf(delta * 12.0, 0.0, 1.0))


func _stance_speed() -> float:
	match _stance:
		Stance.CROUCH: return crouch_speed
		Stance.PRONE: return prone_speed
		_: return walk_speed


func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := _stance_speed()
	_is_sprinting = false
	# Sprint only while standing.
	if _stance == Stance.STAND and Input.is_action_pressed("sprint") and not _ads \
			and GameState.stamina > 0.0 and direction != Vector3.ZERO:
		speed = sprint_speed
		_is_sprinting = true
		GameState.stamina -= stamina_drain_sprint * delta

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)


func _regen_stamina(delta: float) -> void:
	if not _is_sprinting:
		GameState.stamina += stamina_regen * delta


# ---------------------------------------------------------------------------
# Creature-facing API
# ---------------------------------------------------------------------------

## True when the player is moving noisily. Sprinting is loud; prone is silent.
## Creatures' hearing uses this (COD-style stealth via stance).
func is_making_noise() -> bool:
	# The scent mask (deployment gear) keeps you quiet even at a sprint.
	if GameState.gear.get("scent", false):
		return false
	return _is_sprinting and _stance == Stance.STAND


## Damage entry point — creatures call this when they land a hit.
func apply_damage(amount: float) -> void:
	GameState.apply_damage(amount)
	add_shake(clampf(amount / 40.0, 0.15, 0.6))
	damaged.emit(amount)


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

func _current_weapon() -> Weapon:
	return _weapons[_weapon_idx] if _weapon_idx >= 0 else null


## Public accessor (HUD / tests).
func get_active_weapon() -> Weapon:
	return _current_weapon()


func _cycle_weapon(dir: int) -> void:
	if _weapons.size() <= 1:
		return
	_switch_weapon((_weapon_idx + dir + _weapons.size()) % _weapons.size())


func _switch_weapon(idx: int) -> void:
	if idx < 0 or idx >= _weapons.size() or idx == _weapon_idx:
		return
	if _current_weapon():
		_current_weapon().visible = false
	_weapon_idx = idx
	var w := _current_weapon()
	w.visible = true
	weapon_changed.emit(w)


func _handle_weapons(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var w := _current_weapon()

	# Binoculars (hold B): deep zoom + scan creatures; weapon lowered, no firing.
	if captured and Input.is_action_pressed("binoculars"):
		camera.fov = lerpf(camera.fov, 20.0, clampf(delta * 10.0, 0.0, 1.0))
		if w:
			w.visible = false
		_scan_through_binoculars()
		_recover_recoil(delta)
		return
	if w and not w.visible:
		w.visible = true
	if _scanning:
		_scanning = false
		scan_info_changed.emit("")

	# Aim-down-sights + hold-breath (steady, Shift while aiming).
	_ads = Input.is_action_pressed("aim") and captured
	_holding_breath = _ads and Input.is_action_pressed("sprint")
	var target_fov := default_fov
	if _ads and w != null:
		target_fov = w.optic_fov() * (0.85 if _holding_breath else 1.0)
	elif _is_sprinting:
		target_fov = default_fov + 8.0   # speed-rush FOV kick
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 12.0, 0.0, 1.0))

	# Scope overlay when aiming a scoped optic; the viewmodel hides so it reads clean.
	var scoped_now := _ads and w != null and w.optic_scoped()
	if scoped_now != _scope_active:
		_scope_active = scoped_now
		scope_changed.emit(scoped_now, w.optic_name() if w else "")

	if w != null:
		w.set_ads(_ads and not scoped_now)   # hide viewmodel in scope; iron/reflex keep it
		w.set_steady(_holding_breath)
		w.visible = not scoped_now
	if w != null and captured:
		var wants_fire := false
		if w.data.fire_mode == WeaponData.FireMode.AUTO:
			wants_fire = Input.is_action_pressed("fire")
		else:
			wants_fire = Input.is_action_just_pressed("fire")
		if wants_fire and w.try_fire(_ads):
			_add_recoil(w.data)
			add_shake(clampf(w.data.recoil_pitch * 6.0, 0.06, 0.4))
			_alert_wildlife()

	_recover_recoil(delta)


## A shot rings out — nearby prey bolt, predators investigate, birds scatter.
func _alert_wildlife() -> void:
	var here := global_position
	for c in get_tree().get_nodes_in_group("wildlife"):
		if is_instance_valid(c) and c.has_method("hear_shot") and here.distance_to(c.global_position) < 80.0:
			c.hear_shot(here)
	var birds := get_tree().get_first_node_in_group("birds")
	if birds and birds.has_method("startle"):
		birds.startle()


func _scan_through_binoculars() -> void:
	var hit := _cast_from_camera(400.0, 1 | _MASK_CREATURES)  # world blocks the view
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	var text := ""
	if collider != null and collider.has_method("get_scan_text"):
		text = collider.get_scan_text()
	_scanning = true
	scan_info_changed.emit(text)


func _add_recoil(wd: WeaponData) -> void:
	var f := wd.ads_factor if _ads else 1.0
	if _holding_breath:
		f *= 0.6   # steady aim tames the kick
	var kp := wd.recoil_pitch * f
	var ky := wd.recoil_yaw * f * (1.0 if randf() > 0.5 else -1.0)
	camera.rotation.x = clampf(camera.rotation.x + kp, deg_to_rad(-89.0), deg_to_rad(89.0))
	head.rotation.y += ky
	_recoil_pitch += kp
	_recoil_yaw += ky


func _recover_recoil(delta: float) -> void:
	if is_zero_approx(_recoil_pitch) and is_zero_approx(_recoil_yaw):
		return
	var rate := 8.0 * delta
	var rp := _recoil_pitch * clampf(rate, 0.0, 1.0)
	var ry := _recoil_yaw * clampf(rate, 0.0, 1.0)
	camera.rotation.x -= rp
	head.rotation.y -= ry
	_recoil_pitch -= rp
	_recoil_yaw -= ry


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _try_interact() -> void:
	var hit := _cast_from_camera(interact_range, _MASK_INTERACTABLES)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	if collider != null and collider.has_method("interact"):
		collider.interact()


func _update_interact_prompt() -> void:
	var hit := _cast_from_camera(interact_range, _MASK_INTERACTABLES)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	var text := ""
	if collider != null and collider.has_method("get_prompt_text"):
		text = collider.get_prompt_text()
	if text != _current_prompt:
		_current_prompt = text
		interact_prompt_changed.emit(text)


## Ray from the camera center outward. Returns the raw physics hit dictionary.
func _cast_from_camera(distance: float, mask: int) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * distance
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)
