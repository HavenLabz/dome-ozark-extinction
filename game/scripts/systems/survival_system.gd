extends Node
## Passive survival drain — hunger, hydration, and starvation/dehydration damage.
## Attach as child of Main (or autoload later if preferred).

@export var hunger_drain_per_sec: float = 0.35
@export var hydration_drain_per_sec: float = 0.45
@export var starvation_damage_per_sec: float = 2.0
@export var dehydration_damage_per_sec: float = 3.0
@export var low_threshold: float = 5.0


func _process(delta: float) -> void:
	GameState.hunger -= hunger_drain_per_sec * delta
	GameState.hydration -= hydration_drain_per_sec * delta

	if GameState.hunger <= low_threshold:
		GameState.apply_damage(starvation_damage_per_sec * delta)
	if GameState.hydration <= low_threshold:
		GameState.apply_damage(dehydration_damage_per_sec * delta)
