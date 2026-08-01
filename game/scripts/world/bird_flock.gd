extends Node3D
class_name BirdFlock
## Ambient birds circling overhead — cheap atmosphere and a sense of scale/life.
## Each bird is a tiny two-winged mesh flapping as it flies a slow circular path.

@export var count: int = 7
@export var center: Vector3 = Vector3(0, 34, 0)
@export var radius_min: float = 25.0
@export var radius_max: float = 70.0

var _birds: Array[Node3D] = []
var _params: Array[Dictionary] = []   # per-bird orbit params
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func _ready() -> void:
	_rng.randomize()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.roughness = 1.0
	for i in count:
		var bird := Node3D.new()
		add_child(bird)
		# body + two wings (wings pivot to flap)
		_wing(bird, mat, 1.0)
		_wing(bird, mat, -1.0)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.2, 0.9)
		body.mesh = bm
		body.material_override = mat
		bird.add_child(body)
		_birds.append(bird)
		_params.append({
			"radius": _rng.randf_range(radius_min, radius_max),
			"speed": _rng.randf_range(0.15, 0.35) * (1.0 if _rng.randf() > 0.5 else -1.0),
			"phase": _rng.randf_range(0.0, TAU),
			"height": _rng.randf_range(-6.0, 8.0),
			"flap": _rng.randf_range(6.0, 9.0),
		})


func _wing(bird: Node3D, mat: Material, side: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "Wing%s" % ("L" if side > 0 else "R")
	bird.add_child(pivot)
	var wing := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.1, 0.06, 0.5)
	wing.mesh = wm
	wing.position = Vector3(side * 0.65, 0, 0)
	wing.material_override = mat
	pivot.add_child(wing)


func _process(delta: float) -> void:
	_t += delta
	for i in _birds.size():
		var p: Dictionary = _params[i]
		var ang: float = p.phase + _t * p.speed
		var r: float = p.radius
		var pos := center + Vector3(cos(ang) * r, p.height + sin(_t * 0.5 + p.phase) * 2.0, sin(ang) * r)
		var bird := _birds[i]
		bird.global_position = pos
		# Face along the tangent of the circle.
		var tangent := Vector3(-sin(ang), 0, cos(ang)) * signf(p.speed)
		bird.look_at(pos + tangent, Vector3.UP)
		# Flap the wings.
		var flap: float = sin(_t * p.flap + p.phase) * 0.6
		bird.get_node("WingL").rotation.z = -flap
		bird.get_node("WingR").rotation.z = flap
