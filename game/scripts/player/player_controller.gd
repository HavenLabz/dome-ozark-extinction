extends CharacterBody3D
## First-person player controller — movement, survival hooks, weapons.
## Expandable for injuries, equipment, vehicles, multiplayer later.

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var stamina_drain_sprint: float = 12.0
@export var stamina_regen: float = 18.0

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

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const _MASK_INTERACTABLES := 16
const _MASK_CREATURES := 4
const WEAPON_SCENE := preload("res://scripts/weapons/weapon.gd")

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _is_crouching: bool = false
var _is_sprinting: bool = false
var _standing_height: float = 1.8
var _crouch_height: float = 1.0
var _current_prompt: String = ""

var _weapons: Array[Weapon] = []
var _weapon_idx: int = -1
var _ads: bool = false
var _scanning: bool = false
var _recoil_pitch: float = 0.0   # accumulated, recovered each frame
var _recoil_yaw: float = 0.0


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = default_fov
	_build_weapons()


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
	elif event.is_action_pressed("extract"):
		var ex := get_tree().get_first_node_in_group("extraction")
		if ex:
			ex.begin_extraction(global_position)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_crouch()
	_handle_movement(delta)
	_regen_stamina(delta)
	move_and_slide()
	_update_interact_prompt()
	_handle_weapons(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not _is_crouching:
		velocity.y = jump_velocity


func _handle_crouch() -> void:
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != _is_crouching:
		_is_crouching = want_crouch
		var shape := collision_shape.shape as CapsuleShape3D
		if shape:
			shape.height = _crouch_height if _is_crouching else _standing_height
			collision_shape.position.y = shape.height * 0.5


func _handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := walk_speed
	_is_sprinting = false
	if _is_crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint") and GameState.stamina > 0.0 and direction != Vector3.ZERO:
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
	if not Input.is_action_pressed("sprint") or _is_crouching:
		GameState.stamina += stamina_regen * delta


# ---------------------------------------------------------------------------
# Creature-facing API
# ---------------------------------------------------------------------------

## True when the player is moving noisily (sprinting). Creatures' hearing uses this.
func is_making_noise() -> bool:
	return _is_sprinting


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

	# Aim-down-sights.
	_ads = Input.is_action_pressed("aim") and captured
	camera.fov = lerpf(camera.fov, ads_fov if _ads else default_fov, clampf(delta * 12.0, 0.0, 1.0))

	if w != null:
		w.set_ads(_ads)   # raise/lower the sights on the viewmodel
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
