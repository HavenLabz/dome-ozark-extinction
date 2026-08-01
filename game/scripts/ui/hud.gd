extends CanvasLayer
class_name HUD
## Minimal survival HUD: crosshair, vitals, trophy score, interaction prompt.
## Built in code so it stays in sync with GameState without brittle scene wiring.
## This is the seed of the Phase 7 UI, not a mock — every readout is live.

var _stats: Label
var _prompt: Label
var _score: Label
var _ammo: Label
var _bound_weapon: Weapon


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
	if player == null:
		return
	if player.has_signal("interact_prompt_changed"):
		player.interact_prompt_changed.connect(_on_prompt_changed)
	if player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)
	# The initial weapon_changed fired during the player's _ready (before this
	# deferred hookup), so bind the already-active weapon now.
	if player.has_method("get_active_weapon"):
		var w = player.get_active_weapon()
		if w:
			_on_weapon_changed(w)


func _on_weapon_changed(weapon: Weapon) -> void:
	if _bound_weapon and _bound_weapon.ammo_changed.is_connected(_on_ammo_changed):
		_bound_weapon.ammo_changed.disconnect(_on_ammo_changed)
	_bound_weapon = weapon
	if weapon:
		weapon.ammo_changed.connect(_on_ammo_changed)
		var a := weapon.get_ammo()
		_on_ammo_changed(a.x, a.y)


func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	if _bound_weapon:
		_ammo.text = "%s\n%d / %d" % [_bound_weapon.data.display_name, in_mag, reserve]


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

	# Ammo, bottom-right (explicit anchors so it pins to the corner reliably).
	_ammo = _make_label(Vector2.ZERO)
	_ammo.anchor_left = 1.0
	_ammo.anchor_right = 1.0
	_ammo.anchor_top = 1.0
	_ammo.anchor_bottom = 1.0
	_ammo.offset_left = -230.0
	_ammo.offset_top = -80.0
	_ammo.offset_right = -24.0
	_ammo.offset_bottom = -20.0
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_ammo.add_theme_font_size_override("font_size", 22)
	_add_control(_ammo)


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
