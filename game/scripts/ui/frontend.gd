extends Control
## Front-end game flow, modelled on the Carnivores hunt loop the project is
## inspired by: Main Menu → Deployment setup (area · targets · weapons · gear,
## where each aid taxes your score) → drop into the dome → hunt → extract →
## results card → redeploy. Built programmatically so it's one script + a stub
## scene. Set as the project's main scene.

const GAME_SCENE := "res://scenes/main.tscn"
const AMBER := Color(0.87, 0.66, 0.24)
const GREEN := Color(0.55, 0.78, 0.45)
const RED := Color(0.86, 0.32, 0.26)
const DIM := Color(0.62, 0.66, 0.6)
const PANEL_BG := Color(0.09, 0.10, 0.09, 0.96)

# id, display, trophy value, class label, class colour
const ROSTER := [
	["whitetail_deer", "Whitetail Deer", 120, "GAME", GREEN],
	["wild_turkey", "Wild Turkey", 60, "GAME", GREEN],
	["gallimimus", "Gallimimus", 180, "GAME", GREEN],
	["parasaurolophus", "Parasaurolophus", 200, "GAME", GREEN],
	["brachiosaurus", "Brachiosaurus", 400, "GAME", GREEN],
	["black_bear", "Black Bear", 260, "THREAT", AMBER],
	["stegosaurus", "Stegosaurus", 450, "THREAT", AMBER],
	["triceratops", "Triceratops", 500, "THREAT", AMBER],
	["velociraptor", "Velociraptor (pack)", 350, "PREDATOR", RED],
	["allosaurus", "Allosaurus", 700, "PREDATOR", RED],
	["spinosaurus", "Spinosaurus", 900, "APEX", RED],
	["tyrannosaurus", "Tyrannosaurus", 1000, "APEX", RED],
]

const WEAPONS := [
	["res://data/weapons/ar15.tres", "AR-15 Carbine", "5.56 · 30-rnd · versatile"],
	["res://data/weapons/m1911.tres", "M1911 Sidearm", ".45 ACP · 7-rnd · backup"],
]

const GEAR := [
	["scent", "Scent Mask", "Wildlife smells/hears you from closer in."],
	["tracker", "Motion Tracker", "Pings nearby wildlife on your HUD."],
	["ghillie", "Ghillie Wrap", "Harder for wildlife to spot you."],
]

var _main: Control
var _setup: Control
var _results: Control
var _targets: Dictionary = {}       # id -> bool
var _weapons_sel: Dictionary = {}   # path -> bool
var _purity_label: Label


func _ready() -> void:
	# Automated runs (smoke test, screenshots) boot straight into the world so
	# the harness in OzarkWorld handles their flags.
	var ua := OS.get_cmdline_user_args()
	if "--smoke" in ua or "--shot" in ua:
		call_deferred("_skip_to_game")
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_main()
	_build_setup()
	_build_results()

	if not GameState.last_result.is_empty():
		_show(_results)
		_populate_results()
	else:
		_show(_main)

	# Screenshot capture: `-- --shotmenu <path> [--setup]`.
	if "--shotmenu" in ua:
		if "--setup" in ua:
			_show(_setup)
		_capture_menu(ua)


func _skip_to_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _capture_menu(ua: PackedStringArray) -> void:
	var idx := ua.find("--shotmenu")
	var path := ua[idx + 1] if idx + 1 < ua.size() else "user://menu.png"
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit()


func _show(panel: Control) -> void:
	_main.visible = panel == _main
	_setup.visible = panel == _setup
	_results.visible = panel == _results


# --- MAIN MENU ---------------------------------------------------------------

func _build_main() -> void:
	_main = _panel()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.add_child(center)
	var v := _vbox(center, 12)
	v.custom_minimum_size.x = 470

	_title(v, "D O M E", 66, AMBER)
	_cline(v, "OZARK  EXTINCTION", 22, Color(0.82, 0.84, 0.8))
	_cline(v, "CONTAINMENT DOME 01 · 2038 · SEALED ECOSYSTEM", 13, DIM)
	_spacer(v, 22)
	_menu_button(v, "ENTER THE DOME", func(): _show(_setup))
	_menu_button(v, "FIELD RECORDS", func(): _show_records())
	_menu_button(v, "OPTIONS", func(): _toast("Options coming with the settings pass."))
	_menu_button(v, "EXIT", func(): get_tree().quit())
	_spacer(v, 12)
	_cline(v, "Best score: %d      Trophies logged: %d" % [GameState.trophy_score, GameState.trophies_collected.size()], 12, DIM)


# --- DEPLOYMENT SETUP --------------------------------------------------------

func _build_setup() -> void:
	_setup = _panel()
	var root := _vbox(_setup, 10)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 34
	root.offset_bottom = -34

	_title(root, "HUNT DEPLOYMENT", 30, AMBER)
	_line(root, "Configure your expedition, then drop in. Every field aid you carry lowers your final score — fair chase scores highest.", 13, DIM)
	_spacer(root, 6)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# LEFT: area + weapons + gear
	var left := _vbox(cols, 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0

	_section(left, "HUNTING GROUND")
	var area := _card(left)
	_line(area, "OZARK CONTAINMENT DOME — CHAPTER I", 17, GREEN)
	_line(area, "400 acres · river valley, bluffs, cave · full weather ecosystem", 12, DIM)
	_line(area, "Appalachian Dome · Cascade Dome · Everglade Dome — LOCKED", 11, Color(0.4, 0.42, 0.4))

	_section(left, "WEAPONS")
	for w in WEAPONS:
		_weapons_sel[w[0]] = true
		var row := _toggle_row(left, w[1], w[2], true)
		var path: String = w[0]
		row.toggled.connect(func(on): _weapons_sel[path] = on)

	_section(left, "FIELD GEAR  (lowers score)")
	for g in GEAR:
		GameState.gear[g[0]] = false
		var key: String = g[0]
		var row := _toggle_row(left, g[1] + "   −15%", g[2], false)
		row.toggled.connect(func(on):
			GameState.gear[key] = on
			_update_purity())

	# RIGHT: target roster
	var right := _vbox(cols, 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section(right, "TARGET ROSTER  (flag your quarry)")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300
	right.add_child(scroll)
	var list := _vbox(scroll, 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in ROSTER:
		var id: String = r[0]
		_targets[id] = false
		var cb := CheckBox.new()
		cb.text = "  %-22s  %4d pts   [%s]" % [r[1], r[2], r[3]]
		cb.add_theme_color_override("font_color", r[4])
		cb.add_theme_font_size_override("font_size", 14)
		cb.toggled.connect(func(on): _targets[id] = on)
		list.add_child(cb)

	# Footer: purity + deploy/back
	_spacer(root, 4)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)
	_purity_label = Label.new()
	_purity_label.add_theme_font_size_override("font_size", 16)
	_purity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_purity_label)
	_update_purity()
	var back := _wide_button("◄ BACK", DIM)
	back.pressed.connect(func(): _show(_main))
	footer.add_child(back)
	var deploy := _wide_button("DEPLOY ►", GREEN)
	deploy.pressed.connect(_deploy)
	footer.add_child(deploy)


func _update_purity() -> void:
	var p := GameState.compute_purity()
	_purity_label.text = "SCORE PURITY:  %d%%   %s" % [roundi(p * 100.0), "· fair chase" if p >= 0.999 else "· aided"]
	_purity_label.add_theme_color_override("font_color", GREEN if p >= 0.999 else AMBER)


func _deploy() -> void:
	var chosen: Array[String] = []
	for w in WEAPONS:
		if _weapons_sel.get(w[0], false):
			chosen.append(w[0])
	if chosen.is_empty():
		_toast("Select at least one weapon.")
		return
	GameState.loadout_weapons = chosen
	GameState.target_species.clear()
	for id in _targets:
		if _targets[id]:
			GameState.target_species.append(StringName(id))
	GameState.score_purity = GameState.compute_purity()
	GameState.last_result = {}
	GameState.reset_session()
	get_tree().change_scene_to_file(GAME_SCENE)


# --- RESULTS -----------------------------------------------------------------

func _build_results() -> void:
	_results = _panel()


func _populate_results() -> void:
	for c in _results.get_children():
		c.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(center)
	var v := _vbox(center, 12)
	v.custom_minimum_size.x = 520
	var res: Dictionary = GameState.last_result
	var ok: bool = res.get("extracted", true)
	_title(v, "EXTRACTED" if ok else "EXPEDITION LOST", 44, GREEN if ok else RED)
	_line(v, "The Ozark Dome holds — for now." if ok else "The dome claimed another hunter.", 14, DIM)
	_spacer(v, 16)
	_stat(v, "Trophies recovered", str(res.get("trophies", 0)))
	_stat(v, "Raw score", str(res.get("raw", 0)))
	_stat(v, "Score purity", "%d%%" % roundi(float(res.get("purity", 1.0)) * 100.0))
	_stat(v, "FINAL SCORE", str(res.get("final", 0)), AMBER, 22)
	_spacer(v, 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var re := _wide_button("REDEPLOY ►", GREEN)
	re.pressed.connect(func():
		GameState.last_result = {}
		_show(_setup))
	row.add_child(re)
	var mm := _wide_button("MAIN MENU", DIM)
	mm.pressed.connect(func():
		GameState.last_result = {}
		_show(_main))
	row.add_child(mm)


func _show_records() -> void:
	_toast("Trophies logged: %d   ·   Best score: %d" % [GameState.trophies_collected.size(), GameState.trophy_score])


# --- UI helpers --------------------------------------------------------------

func _panel() -> Control:
	var p := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(p)
	return p


func _vbox(parent: Node, sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _title(parent: Node, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if size >= 40 else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(l)


func _line(parent: Node, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)


func _cline(parent: Node, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)


func _section(parent: Node, text: String) -> void:
	_spacer(parent, 6)
	var l := Label.new()
	l.text = "▍" + text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", AMBER)
	parent.add_child(l)


func _card(parent: Node) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = Color(0.25, 0.28, 0.24)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	return _vbox(pc, 3)


func _toggle_row(parent: Node, title: String, sub: String, on: bool) -> CheckButton:
	var box := _card(parent)
	var cb := CheckButton.new()
	cb.text = title
	cb.button_pressed = on
	cb.add_theme_font_size_override("font_size", 15)
	box.add_child(cb)
	_line(box, sub, 11, DIM)
	return cb


func _stat(parent: Node, label: String, value: String, color: Color = Color(0.85, 0.87, 0.82), size: int = 16) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", size)
	v.add_theme_color_override("font_color", color)
	row.add_child(v)


func _menu_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size.y = 46
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


func _wide_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", color)
	b.custom_minimum_size = Vector2(170, 44)
	return b


func _spacer(parent: Node, h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size.y = h
	parent.add_child(s)


func _toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", AMBER)
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.position = Vector2(-200, -60)
	l.custom_minimum_size.x = 400
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(l.queue_free)
