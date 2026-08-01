extends Node3D
class_name Perception
## Senses for a creature: sight (range + FOV cone + line-of-sight) and
## hearing (range, louder when the target is sprinting).
##
## Modular by design (North Star): the brain asks Perception "can you sense the
## target?" and never touches raycasts itself. Swap or upgrade senses here
## without rewriting behavior.

## Set by the owning creature from its CreatureData.
var sight_range: float = 35.0
var sight_fov_deg: float = 200.0
var hearing_range: float = 20.0

## Physics layers a sight ray is allowed to hit (world = 1, player = 2).
## Anything on these layers between eye and target counts as an occluder.
var vision_mask: int = 0b11

var _space: PhysicsDirectSpaceState3D


func configure(data: CreatureData) -> void:
	sight_range = data.sight_range
	sight_fov_deg = data.sight_fov_deg
	hearing_range = data.hearing_range


## Returns true if the target is currently visible from this creature's eyes.
## `facing` is the creature's forward vector (world space, normalized-ish).
func can_see(target: Node3D, facing: Vector3) -> bool:
	if target == null:
		return false
	var eye := global_position
	var to_target := target.global_position - eye
	var dist := to_target.length()
	if dist > sight_range or dist < 0.001:
		return false

	# Field-of-view cone check on the horizontal plane.
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	if flat_facing.length() > 0.001 and flat_to.length() > 0.001:
		var angle := flat_facing.normalized().angle_to(flat_to.normalized())
		if angle > deg_to_rad(sight_fov_deg * 0.5):
			return false

	return _has_line_of_sight(eye, target)


## Distance-based hearing. Sprinting targets are heard from twice as far.
func can_hear(target: Node3D, target_is_loud: bool) -> bool:
	if target == null:
		return false
	var range_now := hearing_range * (2.0 if target_is_loud else 1.0)
	return global_position.distance_to(target.global_position) <= range_now


func _has_line_of_sight(eye: Vector3, target: Node3D) -> bool:
	if _space == null:
		_space = get_world_3d().direct_space_state
	# Aim at roughly chest height so ground-level noise doesn't block sight.
	var target_point: Vector3 = target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(eye, target_point, vision_mask)
	query.collide_with_areas = false
	var hit := _space.intersect_ray(query)
	if hit.is_empty():
		return true
	# We see the target if the first thing the ray hits IS the target (or its child).
	var collider: Object = hit.get("collider")
	if collider == null:
		return true
	# Clear sight only if the first thing hit is the target itself (or a child
	# collider of it). Anything else means terrain/props occlude the view.
	return collider == target or (collider is Node and target.is_ancestor_of(collider))
