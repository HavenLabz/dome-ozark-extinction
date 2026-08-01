extends Area3D
class_name CachePickup
## A hidden supply cache tucked in the woods and around the dome's landmarks.
## Find them all to unlock the legendary edge (weapons hit harder). Interactable
## like a trophy (same layer 16); the player's ray calls interact().

var _collected: bool = false


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0


func interact() -> void:
	if _collected:
		return
	_collected = true
	GameState.find_cache()
	Sfx.play("chime", 1.3, -3.0)
	queue_free()


func get_prompt_text() -> String:
	return "Open hidden cache  [E]   (%d/%d found)" % [GameState.caches_found, GameState.caches_total]
