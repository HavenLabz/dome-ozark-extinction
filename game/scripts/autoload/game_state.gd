extends Node
## Global game state — survival stats, session flags, dome progress.
## Expandable for multi-dome without rewriting systems.

signal health_changed(value: float)
signal stamina_changed(value: float)
signal hunger_changed(value: float)
signal hydration_changed(value: float)
signal trophy_collected(trophy_id: StringName, value: int)
signal player_died

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
var trophies_collected: Array[StringName] = []
var trophy_score: int = 0
var is_extraction_available: bool = false

# --- Survival ---
const HUNGER_DRAIN := 0.30       # per second
const HYDRATION_DRAIN := 0.45
const STARVE_DAMAGE := 2.5       # per second at 0 food/water
const HAVEN_HEAL := 4.0          # per second near a lit fire
var survival_active: bool = true
## Set true by a lit campfire when the player is near: pauses drain and heals.
var near_fire: bool = false


func _process(delta: float) -> void:
	if not survival_active or health <= 0.0:
		return
	if near_fire:
		health = minf(100.0, health + HAVEN_HEAL * delta)
		hunger = minf(100.0, hunger + 1.0 * delta)
		hydration = minf(100.0, hydration + 1.0 * delta)
		return
	hunger -= HUNGER_DRAIN * delta
	hydration -= HYDRATION_DRAIN * delta
	if hunger <= 0.0 or hydration <= 0.0:
		apply_damage(STARVE_DAMAGE * delta)


## Eat harvested meat — restores hunger (amount scales with the kill).
func eat_food(amount: float) -> void:
	hunger = minf(100.0, hunger + amount)


func apply_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		player_died.emit()


## Record a recovered trophy and its prestige value. Trophies can repeat
## (you may hunt several of a species), so this is a log, not a set.
func collect_trophy(trophy_id: StringName, value: int) -> void:
	trophies_collected.append(trophy_id)
	trophy_score += value
	trophy_collected.emit(trophy_id, value)


func reset_session() -> void:
	health = 100.0
	stamina = 100.0
	hunger = 100.0
	hydration = 100.0
	trophies_collected.clear()
	trophy_score = 0
	is_extraction_available = false
