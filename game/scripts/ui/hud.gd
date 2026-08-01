extends CanvasLayer
class_name HUD
## Minimal survival HUD: crosshair, vitals, trophy score, interaction prompt.
## Built in code so it stays in sync with GameState without brittle scene wiring.
## This is the seed of the Phase 7 UI, not a mock — every readout is live.

var _stats: Label
var _prompt: Label
var _score: Label


func _ready() -> void:
	_build()
	# Live vitals.
	GameState.health_changed.connect(func(_v): _refresh_stats())
	GameState.stamina_changed.connect(func(_v): _refresh_stats())
	GameState.hunger_changed.connect(func(_v): _refresh_stats())
	GameState.hydration_changed.connect(func(_v): _refresh_stats())
	GameState.trophy_collected.connect(func(_id, _val): _refresh_score())
	_refresh_stats()
	_refresh_score()
	# Player-driven interaction prompt.
	call_deferred("_hook_player")


func _hook_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("interact_prompt_changed"):
		player.interact_prompt_changed.connect(_on_prompt_changed)


func _on_prompt_changed(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


func _refresh_stats() -> void:
	_stats.text = "HP  %3d\nSTAM %3d\nFOOD %3d\nWATER %3d" % [
		roundi(GameState.health), roundi(GameState.stamina),
		roundi(GameState.hunger), roundi(GameState.hydration)]


func _refresh_score() -> void:
	_score.text = "Trophies: %d   Score: %d" % [
		GameState.trophies_collected.size(), GameState.trophy_score]


func _build() -> void:
	# Crosshair
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_control(cross)

	_stats = _make_label(Vector2(16, 16))
	_add_control(_stats)

	_score = _make_label(Vector2(16, 128))
	_add_control(_score)

	_prompt = _make_label(Vector2(0, 0))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-80, -80)
	_prompt.visible = false
	_add_control(_prompt)


func _make_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.92, 0.93, 0.88))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _add_control(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
