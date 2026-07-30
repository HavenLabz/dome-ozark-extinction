extends Node
## Global game state — survival stats, session flags, dome progress.
## Expandable for multi-dome without rewriting systems.

signal health_changed(value: float)
signal stamina_changed(value: float)
signal hunger_changed(value: float)
signal hydration_changed(value: float)

var health: float = 100.0:
	set(v):
		health = clampf(v, 0.0, 100.0)
		health_changed.emit(health)

var stamina: float = 100.0:
	set(v):
		stamina = clampf(v, 0.0, 100.0)
		stamina_changed.emit(stamina)

var hunger: float = 100.0:
	set(v):
		hunger = clampf(v, 0.0, 100.0)
		hunger_changed.emit(hunger)

var hydration: float = 100.0:
	set(v):
		hydration = clampf(v, 0.0, 100.0)
		hydration_changed.emit(hydration)

## Which dome the player is in (Ozark is chapter one)
var current_dome_id: String = "ozark"
var trophies_collected: Array[String] = []
var is_extraction_available: bool = false


func apply_damage(amount: float) -> void:
	health -= amount


func reset_session() -> void:
	health = 100.0
	stamina = 100.0
	hunger = 100.0
	hydration = 100.0
	trophies_collected.clear()
	is_extraction_available = false
