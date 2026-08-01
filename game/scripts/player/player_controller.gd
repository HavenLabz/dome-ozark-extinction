extends CharacterBody3D
## First-person player controller — Phase 1 foundation.
## Expandable for injuries, equipment, vehicles, multiplayer later.

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var stamina_drain_sprint: float = 12.0
@export var stamina_regen: float = 18.0

@export_group("Interaction / Weapon (seed)")
## Reach of the "look at it and press E" interaction ray.
@export var interact_range: float = 3.0
## First hitscan tool. This is the seed the real weapon system extends —
## not a placeholder that fakes a feature (North Star Hard Rule #2).
@export var weapon_range: float = 250.0
@export var weapon_damage: float = 40.0

## Emitted when the interaction ray gains/loses a valid target, so a HUD can
## show a context prompt. Passes an empty string when nothing is targeted.
signal interact_prompt_changed(text: String)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _is_crouching: bool = false
var _is_sprinting: bool = false
var _standing_height: float = 1.8
var _crouch_height: float = 1.0
var _current_prompt: String = ""

# Physics-layer masks (see project.godot [layer_names]).
const _MASK_WORLD := 1
const _MASK_CREATURES := 4
const _MASK_INTERACTABLES := 16


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	if event.is_action_pressed("fire"):
		_fire()
	elif event.is_action_pressed("interact"):
		_try_interact()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_crouch()
	_handle_movement(delta)
	_regen_stamina(delta)
	move_and_slide()
	_update_interact_prompt()


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
# Hitscan weapon (seed) + interaction
# ---------------------------------------------------------------------------

func _fire() -> void:
	var hit := _cast_from_camera(weapon_range, _MASK_WORLD | _MASK_CREATURES)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_method("take_damage"):
		collider.take_damage(weapon_damage, global_position)


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
