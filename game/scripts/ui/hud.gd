extends CanvasLayer
class_name HUD
## Minimal survival HUD: crosshair, vitals, trophy score, interaction prompt.
## Built in code so it stays in sync with GameState without brittle scene wiring.
## This is the seed of the Phase 7 UI, not a mock — every readout is live.

var _stats: Label
var _prompt: Label
var _score: Label
var _ammo: Label
var _scan: Label
var _extract: Label
var _hitmark: Label
var _hit_t: float = 0.0
var _crit: Label
var _crit_t: float = 0.0
var _contracts: Label
var _vignette: ColorRect
var _vig_pulse: float = 0.0
var _ch_ticks: Array[ColorRect] = []
var _bound_player: Node
var _cross: Label
var _scope: Control
var _bound_weapon: Weapon


func _ready() -> void:
	_build()
	_build_scope()
	var radar = load("res://scripts/ui/minimap.gd").new()
	add_child(radar)
	# Live vitals.
	GameState.health_changed.connect(func(_v): _refresh_stats())
	GameState.stamina_changed.connect(func(_v): _refresh_stats())
	GameState.hunger_changed.connect(func(_v): _refresh_stats())
	GameState.hydration_changed.connect(func(_v): _refresh_stats())
	GameState.trophy_collected.connect(func(_id, _val): _refresh_score())
	GameState.cache_found.connect(func(_f, _t): _refresh_score())
	GameState.contracts_changed.connect(_refresh_contracts)
	GameState.contract_completed.connect(_on_contract_done)
	GameState.legendary_found.connect(func():
		_extract.text = "★ LEGENDARY EDGE UNLOCKED — your rounds hit harder."
		get_tree().create_timer(5.0).timeout.connect(func(): _extract.text = ""))
	_refresh_stats()
	_refresh_score()
	# Player-driven interaction prompt + extraction status.
	call_deferred("_hook_player")
	call_deferred("_hook_extraction")


func _hook_extraction() -> void:
	var ex := get_tree().get_first_node_in_group("extraction")
	if ex and ex.has_signal("status_changed"):
		ex.status_changed.connect(_on_extract_status)


func _hook_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_bound_player = player
	if player.has_signal("interact_prompt_changed"):
		player.interact_prompt_changed.connect(_on_prompt_changed)
	if player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)
	if player.has_signal("scan_info_changed"):
		player.scan_info_changed.connect(_on_scan_changed)
	if player.has_signal("hitmarker"):
		player.hitmarker.connect(_on_hitmarker)
	if player.has_signal("crit_hit"):
		player.crit_hit.connect(_on_crit)
	if player.has_signal("damaged"):
		player.damaged.connect(func(_a): _vig_pulse = 0.8)
	if player.has_signal("scope_changed"):
		player.scope_changed.connect(_on_scope_changed)
	# The initial weapon_changed fired during the player's _ready (before this
	# deferred hookup), so bind the already-active weapon now.
	if player.has_method("get_active_weapon"):
		var w = player.get_active_weapon()
		if w:
			_on_weapon_changed(w)


func _on_weapon_changed(weapon: Weapon) -> void:
	if _bound_weapon and _bound_weapon.ammo_changed.is_connected(_on_ammo_changed):
		_bound_weapon.ammo_changed.disconnect(_on_ammo_changed)
	if _bound_weapon and _bound_weapon.optic_changed.is_connected(_refresh_ammo):
		_bound_weapon.optic_changed.disconnect(_refresh_ammo)
	_bound_weapon = weapon
	if weapon:
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.optic_changed.connect(_refresh_ammo)
		_refresh_ammo("")


func _refresh_ammo(_optic: String) -> void:
	if _bound_weapon:
		var a := _bound_weapon.get_ammo()
		_on_ammo_changed(a.x, a.y)


func _on_ammo_changed(in_mag: int, reserve: int) -> void:
	if _bound_weapon:
		_ammo.text = "%s · %s\n%d / %d" % [
			_bound_weapon.data.display_name, _bound_weapon.optic_name(), in_mag, reserve]


func _on_scan_changed(text: String) -> void:
	_scan.text = text
	_scan.visible = text != ""


func _on_extract_status(text: String) -> void:
	_extract.text = text
	_extract.visible = text != ""


func _on_scope_changed(active: bool, _optic_name: String) -> void:
	if _scope:
		_scope.visible = active
	if _cross:
		_cross.visible = not active   # hide the hip crosshair while scoped


## Full-screen scope: black circular mask (shader) + a thin reticle cross.
func _build_scope() -> void:
	_scope = Control.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	add_child(_scope)

	# reticle cross (drawn under the mask so it only shows inside the circle)
	var vline := ColorRect.new()
	vline.color = Color(0.05, 0.06, 0.05, 0.9)
	vline.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	vline.custom_minimum_size = Vector2(0, 2)
	vline.anchor_top = 0.5; vline.anchor_bottom = 0.5; vline.offset_top = -1; vline.offset_bottom = 1
	_scope.add_child(vline)
	var hline := ColorRect.new()
	hline.color = Color(0.05, 0.06, 0.05, 0.9)
	hline.anchor_left = 0.5; hline.anchor_right = 0.5; hline.anchor_top = 0; hline.anchor_bottom = 1
	hline.offset_left = -1; hline.offset_right = 1
	_scope.add_child(hline)

	# circular black-out mask on top
	var mask := ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float aspect = 1.777;
void fragment(){
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float d = length(p);
	float outside = smoothstep(0.33, 0.345, d);
	float ring = (smoothstep(0.315,0.33,d) - smoothstep(0.345,0.36,d));
	vec3 col = mix(vec3(0.0), vec3(0.02,0.03,0.02), ring);
	COLOR = vec4(col, max(outside, ring));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))
	mask.material = mat
	_scope.add_child(mask)


func _on_hitmarker(on_creature: bool) -> void:
	_hitmark.add_theme_color_override("font_color",
		Color(1, 0.3, 0.2) if on_creature else Color(0.95, 0.95, 0.9))
	_hitmark.visible = true
	_hit_t = 0.22


func _on_crit(zone: String) -> void:
	_crit.text = "HEADSHOT" if zone == "HEAD" else "VITAL HIT"
	_crit.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if zone == "HEAD" else Color(1.0, 0.5, 0.35))
	_crit.visible = true
	_crit_t = 1.1


func _process(delta: float) -> void:
	if _hit_t > 0.0:
		_hit_t -= delta
		_hitmark.modulate.a = clampf(_hit_t / 0.22, 0.0, 1.0)
		if _hit_t <= 0.0:
			_hitmark.visible = false
	if _crit_t > 0.0:
		_crit_t -= delta
		_crit.modulate.a = clampf(_crit_t / 1.1, 0.0, 1.0)
		if _crit_t <= 0.0:
			_crit.visible = false
	if _vignette:
		_vig_pulse = maxf(0.0, _vig_pulse - delta * 1.6)
		var low := clampf((35.0 - GameState.health) / 35.0, 0.0, 0.75)  # persistent when hurt
		_vignette.material.set_shader_parameter("strength", maxf(low, _vig_pulse))
	_update_crosshair()


## Spread the crosshair ticks with the active weapon's current inaccuracy.
func _update_crosshair() -> void:
	if _ch_ticks.is_empty():
		return
	var gap := 8.0
	if _bound_player and _bound_player.has_method("get_active_weapon"):
		var w = _bound_player.get_active_weapon()
		if w and w.has_method("current_spread"):
			gap = 6.0 + clampf(w.current_spread(false) * 900.0, 0.0, 40.0)
	# order: up, down, left, right
	_ch_ticks[0].position = Vector2(-1, -gap - 7)
	_ch_ticks[1].position = Vector2(-1, gap)
	_ch_ticks[2].position = Vector2(-gap - 7, -1)
	_ch_ticks[3].position = Vector2(gap, -1)


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


func _refresh_contracts() -> void:
	if _contracts == null:
		return
	if GameState.contracts.is_empty():
		_contracts.text = ""
		return
	var lines := ["CONTRACTS"]
	for c in GameState.contracts:
		var mark := "✓" if c["done"] else "•"
		lines.append("%s %s  (%d/%d)" % [mark, c["desc"], int(c["progress"]), int(c["target"])])
	_contracts.text = "\n".join(lines)


func _on_contract_done(desc: String, reward: int) -> void:
	_refresh_score()
	_crit.text = "CONTRACT COMPLETE  +%d\n%s" % [reward, desc]
	_crit.add_theme_color_override("font_color", Color(0.55, 0.82, 0.45))
	_crit.visible = true
	_crit_t = 2.2


func _build() -> void:
	# Damage vignette — reddens the screen edges when hurt / low on health.
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://shaders/vignette.gdshader")
	vmat.set_shader_parameter("strength", 0.0)
	_vignette.material = vmat
	_add_control(_vignette)

	# Crosshair
	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 22)
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_control(_cross)

	# Dynamic crosshair ticks — spread apart as accuracy drops.
	for i in 4:
		var tick := ColorRect.new()
		tick.color = Color(0.9, 0.95, 0.9, 0.85)
		tick.set_anchors_preset(Control.PRESET_CENTER)
		var vertical := i < 2
		tick.size = Vector2(2, 7) if vertical else Vector2(7, 2)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ch_ticks.append(tick)
		_add_control(tick)

	# Hitmarker — flashes over the crosshair when a shot connects.
	_hitmark = Label.new()
	_hitmark.text = "✕"
	_hitmark.add_theme_font_size_override("font_size", 30)
	_hitmark.set_anchors_preset(Control.PRESET_CENTER)
	_hitmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmark.visible = false
	_add_control(_hitmark)

	# Vital/headshot callout — appears just above the crosshair on a placed shot.
	_crit = Label.new()
	_crit.add_theme_font_size_override("font_size", 20)
	_crit.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_crit.position = Vector2(-80, 120)
	_crit.custom_minimum_size.x = 160
	_crit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crit.visible = false
	_add_control(_crit)

	_stats = _make_label(Vector2(16, 16))
	_add_control(_stats)

	_score = _make_label(Vector2(16, 128))
	_add_control(_score)

	_contracts = _make_label(Vector2(16, 160))
	_contracts.add_theme_font_size_override("font_size", 13)
	_add_control(_contracts)
	_refresh_contracts()

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

	# Binocular scan readout, upper-center.
	_scan = _make_label(Vector2.ZERO)
	_scan.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_scan.position = Vector2(-120, 90)
	_scan.size = Vector2(240, 80)
	_scan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan.add_theme_font_size_override("font_size", 20)
	_scan.visible = false
	_add_control(_scan)

	# Extraction status banner, upper-center.
	_extract = _make_label(Vector2.ZERO)
	_extract.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_extract.position = Vector2(-260, 40)
	_extract.size = Vector2(520, 90)
	_extract.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_extract.add_theme_font_size_override("font_size", 26)
	_extract.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_extract.visible = false
	_add_control(_extract)


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
