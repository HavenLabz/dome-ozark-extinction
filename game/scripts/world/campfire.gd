extends Area3D
class_name Campfire
## A campfire the player lights with [E]. When lit it casts flickering light and
## becomes a safe haven — standing near it pauses survival drain and heals
## (GameState.near_fire). A real, working shelter mechanic, not set dressing.

@onready var _flames: Array[Node3D] = [$Fire/Flame1, $Fire/Flame2, $Fire/Flame3]
@onready var _light: OmniLight3D = $Fire/Light
@onready var _haven: Area3D = $HavenArea

var _lit: bool = false
var _player_in: bool = false
var _t: float = 0.0


func _ready() -> void:
	_haven.body_entered.connect(_on_haven_entered)
	_haven.body_exited.connect(_on_haven_exited)
	_set_lit(false)


func _process(delta: float) -> void:
	if not _lit:
		return
	# Flicker the light and flames.
	_t += delta
	_light.light_energy = 2.6 + sin(_t * 11.0) * 0.5 + sin(_t * 23.0) * 0.25
	for i in _flames.size():
		var f := _flames[i]
		f.scale.y = 1.0 + sin(_t * (9.0 + i * 2.0)) * 0.18


func interact() -> void:
	_set_lit(not _lit)


func get_prompt_text() -> String:
	return "Put out fire  [E]" if _lit else "Light campfire  [E]"


func _set_lit(v: bool) -> void:
	_lit = v
	$Fire.visible = v
	_light.visible = v
	_update_haven()


func _on_haven_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in = true
		_update_haven()


func _on_haven_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in = false
		_update_haven()


func _update_haven() -> void:
	GameState.near_fire = _lit and _player_in
