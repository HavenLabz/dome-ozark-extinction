extends Node3D
class_name ExtractionManager
## The signature DOME moment: recover at least one trophy, pop an extraction
## flare (F), SURVIVE while the wilderness reacts, then a helicopter descends and
## lifts you out. Never cut this — it is the franchise's payoff (North Star /
## non-negotiables). In group "extraction" so the player can trigger it.

signal status_changed(text: String)

enum Phase { IDLE, SURVIVE, INBOUND, EXTRACTED }

const SURVIVE_TIME := 40.0
const HELI_SPEED := 22.0

var _phase: int = Phase.IDLE
var _timer: float = 0.0
var _flare_pos: Vector3
var _flare: Node3D
var _heli: Node3D
var _rotor: Node3D
var _msg_clear_t: float = 0.0


func _ready() -> void:
	add_to_group("extraction")
	GameState.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	if _phase == Phase.EXTRACTED:
		return
	GameState.last_result = {
		"extracted": false,
		"trophies": GameState.trophies_collected.size(),
		"raw": GameState.trophy_score,
		"purity": GameState.score_purity,
		"final": 0,
	}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t := get_tree().create_timer(3.0, true)
	t.timeout.connect(func(): get_tree().change_scene_to_file("res://scenes/frontend.tscn"))


func can_extract() -> bool:
	return GameState.trophies_collected.size() >= 1


func begin_extraction(at: Vector3) -> void:
	if _phase != Phase.IDLE:
		return
	if not can_extract():
		status_changed.emit("Recover a trophy before calling extraction.")
		_msg_clear_t = 3.0
		return
	_phase = Phase.SURVIVE
	_timer = SURVIVE_TIME
	_flare_pos = at
	_spawn_flare(at)


func _process(delta: float) -> void:
	if _msg_clear_t > 0.0:
		_msg_clear_t -= delta
		if _msg_clear_t <= 0.0 and _phase == Phase.IDLE:
			status_changed.emit("")

	match _phase:
		Phase.SURVIVE:
			_timer -= delta
			status_changed.emit("EXTRACTION FLARE LIT — SURVIVE: %d" % ceili(_timer))
			if _rotor:
				pass
			if _timer <= 0.0:
				_phase = Phase.INBOUND
				_spawn_helicopter()
		Phase.INBOUND:
			_fly_helicopter(delta)
		_:
			pass


func _spawn_flare(at: Vector3) -> void:
	_flare = Node3D.new()
	add_child(_flare)
	_flare.global_position = at
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 0.15
	cyl.height = 14.0
	col.mesh = cyl
	col.position.y = 7.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.15, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col.material_override = mat
	_flare.add_child(col)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.3, 0.15)
	light.light_energy = 6.0
	light.omni_range = 25.0
	light.position.y = 2.0
	_flare.add_child(light)


func _spawn_helicopter() -> void:
	_heli = Node3D.new()
	add_child(_heli)
	_heli.global_position = _flare_pos + Vector3(90, 90, 90)  # inbound from the sky
	var body_mat := _mat(Color(0.18, 0.20, 0.18))
	_box(_heli, Vector3(2.2, 1.8, 4.5), Vector3(0, 0, 0), body_mat)          # cabin
	_box(_heli, Vector3(0.5, 0.5, 3.5), Vector3(0, 0.4, 3.3), body_mat)      # tail boom
	_box(_heli, Vector3(0.2, 1.2, 0.8), Vector3(0, 0.9, 4.8), body_mat)      # tail fin
	_box(_heli, Vector3(2.6, 0.2, 0.3), Vector3(0, -1.0, -1.2), body_mat)    # skids bar
	_box(_heli, Vector3(2.6, 0.2, 0.3), Vector3(0, -1.0, 1.2), body_mat)
	# Main rotor (spins).
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.1, 0)
	_heli.add_child(_rotor)
	_box(_rotor, Vector3(9.0, 0.1, 0.4), Vector3.ZERO, _mat(Color(0.1, 0.1, 0.1)))
	_box(_rotor, Vector3(0.4, 0.1, 9.0), Vector3.ZERO, _mat(Color(0.1, 0.1, 0.1)))
	status_changed.emit("HELICOPTER INBOUND — hold position!")


func _fly_helicopter(delta: float) -> void:
	if _rotor:
		_rotor.rotate_y(delta * 30.0)
	var land := _flare_pos + Vector3(0, 6.0, 0)   # hover above the flare
	_heli.global_position = _heli.global_position.move_toward(land, HELI_SPEED * delta)
	if _heli.global_position.distance_to(land) < 1.0:
		_complete()


func _complete() -> void:
	_phase = Phase.EXTRACTED
	# Final score = raw trophy score scaled by fair-chase purity (gear taxes it).
	var raw: int = GameState.trophy_score
	var final: int = int(round(raw * GameState.score_purity))
	GameState.last_result = {
		"extracted": true,
		"trophies": GameState.trophies_collected.size(),
		"raw": raw,
		"purity": GameState.score_purity,
		"final": final,
	}
	status_changed.emit("EXTRACTED!  Final score: %d\nReturning to base..." % final)
	GameState.is_extraction_available = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t := get_tree().create_timer(4.5, true)
	t.timeout.connect(func(): get_tree().change_scene_to_file("res://scenes/frontend.tscn"))


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = 0.3
	return m
