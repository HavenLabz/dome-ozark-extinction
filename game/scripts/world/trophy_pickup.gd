extends Area3D
class_name TrophyPickup
## A recoverable trophy dropped by a downed creature.
## Completes the hunt loop: hunt → down → recover → progress (GameState).
## Player looks at it and presses Interact to collect.

@onready var mesh: MeshInstance3D = $Mesh

var _trophy_id: StringName = &"unknown_trophy"
var _display_name: String = "Unknown Trophy"
var _value: int = 0
var _collected: bool = false


func setup_from_creature(data: CreatureData) -> void:
	_trophy_id = data.trophy_id
	_display_name = "%s Trophy" % data.display_name
	_value = data.trophy_value
	# Tint the marker to match the species so drops read at a glance.
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.placeholder_color.lightened(0.2)
		mat.emission_enabled = true
		mat.emission = data.placeholder_color
		mat.emission_energy_multiplier = 0.6
		mesh.material_override = mat


## Called by the player's interaction ray.
func interact() -> void:
	if _collected:
		return
	_collected = true
	GameState.collect_trophy(_trophy_id, _value)
	queue_free()


func get_prompt_text() -> String:
	return "Recover %s  [E]" % _display_name
