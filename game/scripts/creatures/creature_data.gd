extends Resource
class_name CreatureData
## Data-driven definition of a single species.
##
## The game grows by adding data, not code (North Star, Principle 4).
## Every field a designer needs to tune a creature lives here; the AI
## (`creature.gd`) reads these values and never hard-codes species behavior.
## New creatures = new `.tres` files under `res://data/creatures/`.

enum Diet { HERBIVORE, CARNIVORE, OMNIVORE }

@export_group("Identity")
@export var species_id: StringName = &"unknown"
@export var display_name: String = "Unknown Creature"
@export var diet: Diet = Diet.HERBIVORE
## Rarity 1 (common) .. 5 (legendary). Drives spawn weighting + trophy prestige.
@export_range(1, 5) var rarity: int = 1

@export_group("Vitals")
@export var max_health: float = 100.0
## Body mass in kg — future systems (tracking weight, carry, ballistics) read this.
@export var mass_kg: float = 80.0

@export_group("Locomotion")
@export var walk_speed: float = 2.0
@export var run_speed: float = 7.0
## Turn rate in radians/second while steering toward a nav target.
@export var turn_speed: float = 6.0

@export_group("Perception")
@export var sight_range: float = 35.0
## Full field-of-view cone in degrees (split evenly left/right of facing).
@export_range(10.0, 360.0) var sight_fov_deg: float = 200.0
@export var hearing_range: float = 20.0

@export_group("Behavior")
## How close a threat may get before a skittish creature bolts.
@export var flee_distance: float = 18.0
## Seconds a creature keeps investigating/pursuing after losing its target.
@export var alert_memory: float = 6.0
## Radius of the creature's home range; it prefers to stay within this.
@export var territory_radius: float = 40.0

@export_group("Combat (predators)")
@export var is_aggressive: bool = false
@export var attack_range: float = 2.2
@export var attack_damage: float = 22.0
@export var attack_cooldown: float = 1.4

@export_group("Trophy / Hunt")
@export var trophy_id: StringName = &"unknown_trophy"
## Prestige value awarded on a clean recovery. Feeds progression later.
@export var trophy_value: int = 100

@export_group("Appearance (placeholder)")
## Debug body dimensions + tint until final art replaces the primitive mesh.
@export var body_size: Vector3 = Vector3(0.8, 1.0, 1.8)
@export var placeholder_color: Color = Color(0.5, 0.4, 0.3)
