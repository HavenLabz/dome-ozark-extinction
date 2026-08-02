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

# --- Persistent records (survive between runs, saved to disk) ---
const SAVE_PATH := "user://records.cfg"
var best_score: int = 0
var hunts_completed: int = 0
var lifetime_trophies: Dictionary = {}   # trophy_id -> count across all runs


func _ready() -> void:
	_load_records()


func _load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best_score = cfg.get_value("records", "best_score", 0)
	hunts_completed = cfg.get_value("records", "hunts_completed", 0)
	lifetime_trophies = cfg.get_value("records", "lifetime_trophies", {})


func _save_records() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_score", best_score)
	cfg.set_value("records", "hunts_completed", hunts_completed)
	cfg.set_value("records", "lifetime_trophies", lifetime_trophies)
	cfg.save(SAVE_PATH)


## Log a completed hunt's final score into the persistent records.
func record_hunt(final_score: int) -> void:
	hunts_completed += 1
	best_score = maxi(best_score, final_score)
	_save_records()

## Weather severity 0 (clear) .. 1 (full storm), set by WeatherManager each
## frame. Wildlife reads this to decide whether to shelter / hunker down.
var storm_intensity: float = 0.0
## Set by the day/night cycle. Predators grow bolder and sharper-sensed at night.
var is_night: bool = false
## 0..1 threat level, driven by the ambush stalker — feeds the "being hunted"
## heartbeat cue. 1 = it's on you.
var danger: float = 0.0

# --- Hunt loadout (chosen on the deployment screen, Carnivores-style) ---
## Weapon .tres paths the player deploys with. Empty = default loadout.
var loadout_weapons: Array[String] = []
## Species the player has flagged as targets this trip (for objectives/score).
var target_species: Array[StringName] = []
## Field gear: each aid makes the hunt easier but taxes your final score.
var gear := {"scent": false, "tracker": false, "ghillie": false}
## Per-weapon attachments chosen on the deployment screen:
##   weapon_path -> {optic: "iron"/"reflex"/"scope", suppressor: bool, foregrip: bool}
var attachments: Dictionary = {}
## Score multiplier (1.0 = pure/fair-chase). Each gear item lowers it.
var score_purity: float = 1.0
## Filled in at extraction so the front-end can show a results card.
var last_result: Dictionary = {}
## The one supply drop per hunt (Carnivores-style) — refills ammo. Once used,
## no more until the next deployment.
var supply_used: bool = false

# --- Hidden caches → legendary edge ---
var caches_total: int = 6
var caches_found: int = 0
## Once every cache is found, weapons hit harder for the rest of the run.
var legendary_unlocked: bool = false

signal cache_found(found: int, total: int)
signal legendary_found

# --- Contracts (per-hunt objectives, rolled at deployment) ---
## trophy_id -> class, for contract matching.
const TROPHY_CLASS := {
	"deer_trophy": "game", "turkey_trophy": "game", "gallimimus_trophy": "game",
	"parasaurolophus_trophy": "game", "brachiosaurus_trophy": "game",
	"bear_trophy": "threat", "stegosaurus_trophy": "threat", "triceratops_trophy": "threat",
	"velociraptor_trophy": "predator", "allosaurus_trophy": "predator",
	"spinosaurus_trophy": "apex", "tyrannosaurus_trophy": "apex", "stalker_trophy": "apex",
}
const CONTRACT_POOL := [
	{"type": "trophies", "target": 4, "desc": "Recover 4 trophies", "reward": 300},
	{"type": "trophies", "target": 6, "desc": "Recover 6 trophies", "reward": 500},
	{"type": "apex", "target": 1, "desc": "Take down an apex predator", "reward": 600},
	{"type": "clean", "target": 3, "desc": "Land 3 clean vital kills", "reward": 400},
	{"type": "predator", "target": 2, "desc": "Cull 2 predators", "reward": 350},
	{"type": "caches", "target": 3, "desc": "Recover 3 hidden caches", "reward": 300},
]
var contracts: Array = []      # active: {type,target,desc,reward,progress,done}

signal contracts_changed
signal contract_completed(desc: String, reward: int)


## Roll a fresh set of 3 contracts for a new hunt.
func roll_contracts() -> void:
	contracts.clear()
	var pool := CONTRACT_POOL.duplicate()
	pool.shuffle()
	for i in mini(3, pool.size()):
		var c: Dictionary = pool[i].duplicate()
		c["progress"] = 0
		c["done"] = false
		contracts.append(c)
	contracts_changed.emit()


func _advance_contracts(kind: String, klass: String, clean: bool) -> void:
	var changed := false
	for c in contracts:
		if c["done"]:
			continue
		var hit := false
		match c["type"]:
			"trophies": hit = kind == "trophy"
			"apex": hit = kind == "trophy" and klass == "apex"
			"predator": hit = kind == "trophy" and (klass == "predator" or klass == "apex")
			"clean": hit = kind == "trophy" and clean
			"caches": hit = kind == "cache"
		if hit:
			c["progress"] = int(c["progress"]) + 1
			changed = true
			if c["progress"] >= c["target"]:
				c["done"] = true
				trophy_score += int(c["reward"])
				contract_completed.emit(c["desc"], int(c["reward"]))
	if changed:
		contracts_changed.emit()


## Recover a hidden cache: score + ammo, and the last one unlocks the legendary.
func find_cache() -> void:
	caches_found += 1
	trophy_score += 100
	_advance_contracts("cache", "", false)
	cache_found.emit(caches_found, caches_total)
	if caches_found >= caches_total and not legendary_unlocked:
		legendary_unlocked = true
		trophy_score += 500
		legendary_found.emit()


## Purity multiplier from the currently-selected gear (−15% per aid).
func compute_purity() -> float:
	var p := 1.0
	for k in gear:
		if gear[k]:
			p -= 0.15
	return maxf(0.4, p)

# --- Survival ---
# Tuned to real-wilderness pacing: you're dropped in the wild, not on a timer.
# Thirst is the first real concern (~21 min from full to empty), hunger far
# slower (~33 min) — you can hunt and explore for a long stretch before either
# bites. Hitting empty then weakens you gradually (grace to reach water), it
# doesn't chunk your health away.
const HUNGER_DRAIN := 0.05       # per second → ~33 min full→empty
const HYDRATION_DRAIN := 0.08    # per second → ~21 min full→empty
const STARVE_DAMAGE := 1.0       # per second at 0 food/water (~100s of grace)
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
func collect_trophy(trophy_id: StringName, value: int, clean: bool = false) -> void:
	trophies_collected.append(trophy_id)
	trophy_score += value
	lifetime_trophies[trophy_id] = int(lifetime_trophies.get(trophy_id, 0)) + 1
	_save_records()
	_advance_contracts("trophy", TROPHY_CLASS.get(String(trophy_id), "game"), clean)
	trophy_collected.emit(trophy_id, value)


func reset_session() -> void:
	health = 100.0
	stamina = 100.0
	hunger = 100.0
	hydration = 100.0
	trophies_collected.clear()
	trophy_score = 0
	is_extraction_available = false
	supply_used = false
	caches_found = 0
	legendary_unlocked = false
