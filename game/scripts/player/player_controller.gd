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


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = default_fov
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
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.19, 0.24, 0.18)   # olive field jacket
	jacket.roughness = 0.85
	var pants := StandardMaterial3D.new()
	pants.albedo_color = Color(0.28, 0.26, 0.20)    # tan cargo pants
	pants.roughness = 0.9
	var boots := StandardMaterial3D.new()
	boots.albedo_color = Color(0.08, 0.07, 0.06)
	boots.roughness = 0.7
	var vest := StandardMaterial3D.new()
	vest.albedo_color = Color(0.10, 0.11, 0.10)     # chest rig
	vest.roughness = 0.8

	var body := Node3D.new()
	body.name = "FPBody"
	# Hang below the eye line; the head node sits at eye height.
	body.position = Vector3(0.0, -0.15, 0.0)
	head.add_child(body)

	_body_box(body, Vector3(0.42, 0.5, 0.26), Vector3(0.0, -0.62, 0.05), jacket)   # torso
	_body_box(body, Vector3(0.34, 0.22, 0.2), Vector3(0.0, -0.5, 0.02), vest)      # chest rig
	# Legs + boots (slightly splayed).
	for s in [-1.0, 1.0]:
		_body_box(body, Vector3(0.16, 0.6, 0.18), Vector3(s * 0.12, -1.2, 0.02), pants)
		_body_box(body, Vector3(0.17, 0.14, 0.3), Vector3(s * 0.12, -1.55, -0.04), boots)


func _body_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	# Don't let the body block the camera's near plane when looking straight down.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


func _build_weapons() -> void:
	if weapon_loadout.is_empty():
		weapon_loadout = [
			load("res://data/weapons/ar15.tres"),
			load("res://data/weapons/m1911.tres"),
		]
	for wd in weapon_loadout:
		var w := WEAPON_SCENE.new() as Weapon
		w.data = wd
		w.visible = false
		camera.add_child(w)
		w.shot_hit.connect(func(on_creature): hitmarker.emit(on_creature))
		_weapons.append(w)
	if not _weapons.is_empty():
		_switch_weapon(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

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


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_stance(delta)
	_handle_movement(delta)
	_regen_stamina(delta)
	move_and_slide()
	_update_interact_prompt()
	_handle_weapons(delta)


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
	return _is_sprinting and _stance == Stance.STAND


## Damage entry point — creatures call this when they land a hit.
func apply_damage(amount: float) -> void:
	GameState.apply_damage(amount)


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------

func _current_weapon() -> Weapon:
	return _weapons[_weapon_idx] if _weapon_idx >= 0 else null


## Public accessor (HUD / tests).
func get_active_weapon() -> Weapon:
	return _current_weapon()


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

	_recover_recoil(delta)


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
