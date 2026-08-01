extends Node3D
class_name CreatureRig
## Stylized procedural creature body built from primitives — no external models
## (zero-cost art). Herbivores read as long-necked sauropods; carnivores as
## horizontal theropods with a long tail. Legs walk and the tail sways, driven by
## the creature's speed. This is the seed silhouette; final sculpted/animated
## models replace the rig without touching AI (North Star: creature quality).
##
## Forward is -Z (matches Creature facing).

var _legs: Array[Node3D] = []      # hip pivots, rotated for the walk cycle
var _leg_phase: Array[float] = []
var _tail_segments: Array[Node3D] = []
var _head: Node3D
var _body: Node3D
var _biped := false
var _gait := 0.0
var _base_y := 0.0


func build(data: CreatureData) -> void:
	var skin := _mat(data.placeholder_color)
	var belly := _mat(data.placeholder_color.lightened(0.22))
	match data.archetype:
		CreatureData.Archetype.THEROPOD:
			_biped = true
			_build_theropod(data, skin, belly)
		CreatureData.Archetype.CERATOPSIAN:
			_build_ceratopsian(data, skin, belly)
		CreatureData.Archetype.ORNITHOMIMID:
			_biped = true
			_build_ornithomimid(data, skin, belly)
		_:
			_build_sauropod(data, skin, belly)


func animate(speed: float, delta: float) -> void:
	var moving := speed > 0.15
	_gait += delta * (6.0 if moving else 0.0)
	var swing := clampf(speed / 6.0, 0.0, 1.0) * 0.6
	for i in _legs.size():
		_legs[i].rotation.x = sin(_gait + _leg_phase[i]) * swing
	# Body bob with the gait.
	if _body:
		_body.position.y = _base_y + absf(sin(_gait)) * swing * 0.12
	# Tail sway — always a little alive, more when moving.
	var t := Time.get_ticks_msec() / 1000.0
	for i in _tail_segments.size():
		var amt := (0.06 + swing * 0.18) * (1.0 + i * 0.4)
		_tail_segments[i].rotation.y = sin(t * 2.0 + i * 0.6) * amt
	if _head:
		_head.position.y = _head_base_y + sin(t * 1.5) * 0.04


var _head_base_y := 0.0


# ---------------------------------------------------------------------------

func _build_sauropod(data: CreatureData, skin: Material, belly: Material) -> void:
	var s := data.body_size
	var w := s.x
	var hgt := s.y
	var ln := s.z
	var hip := hgt * 0.72
	_base_y = hip * 1.05

	_body = _ellipsoid(Vector3(w * 1.05, hgt * 0.85, ln * 0.95), Vector3(0, _base_y, 0), skin)
	_ellipsoid(Vector3(w * 0.9, hgt * 0.5, ln * 0.7), Vector3(0, _base_y - hgt * 0.18, 0), belly)

	# Neck (curves up and forward, -Z) + head.
	var neck_root := Vector3(0, _base_y + hgt * 0.15, -ln * 0.42)
	var seg := 3
	for i in seg:
		var f := i / float(seg)
		var pos := neck_root + Vector3(0, hgt * 0.35 * f, -ln * 0.28 * (f + 0.3))
		_cyl(0.22 * w * (1.0 - f * 0.4), hgt * 0.4, pos, Vector3(-35, 0, 0), skin)
	var head_pos := neck_root + Vector3(0, hgt * 0.55, -ln * 0.5)
	_head = _ellipsoid(Vector3(w * 0.4, hgt * 0.3, ln * 0.28), head_pos, skin)
	_head_base_y = head_pos.y

	# Tail (tapers back, +Z, slightly down).
	_build_tail(Vector3(0, _base_y, ln * 0.45), ln, hgt, w, skin, 4, 0.2)

	# Four legs.
	_add_leg(Vector3(w * 0.55, hip, -ln * 0.28), hip, w * 0.22, skin, 0.0)
	_add_leg(Vector3(-w * 0.55, hip, -ln * 0.28), hip, w * 0.22, skin, PI)
	_add_leg(Vector3(w * 0.55, hip, ln * 0.28), hip, w * 0.22, skin, PI)
	_add_leg(Vector3(-w * 0.55, hip, ln * 0.28), hip, w * 0.22, skin, 0.0)


func _build_theropod(data: CreatureData, skin: Material, belly: Material) -> void:
	var s := data.body_size
	var w := s.x
	var hgt := s.y
	var ln := s.z
	var hip := hgt * 0.62
	_base_y = hip * 1.05

	_body = _ellipsoid(Vector3(w * 1.0, hgt * 0.7, ln * 1.05), Vector3(0, _base_y, 0), skin)
	_body.rotation.x = deg_to_rad(-8.0)  # nose slightly up
	_ellipsoid(Vector3(w * 0.85, hgt * 0.42, ln * 0.8), Vector3(0, _base_y - hgt * 0.14, 0), belly)

	# Short neck + head forward (-Z), raised.
	var neck_pos := Vector3(0, _base_y + hgt * 0.28, -ln * 0.5)
	_cyl(0.2 * w, hgt * 0.5, neck_pos, Vector3(-50, 0, 0), skin)
	var head_pos := neck_pos + Vector3(0, hgt * 0.28, -ln * 0.28)
	_head = _box(Vector3(w * 0.42, hgt * 0.34, ln * 0.42), head_pos, skin)
	_head_base_y = head_pos.y
	# Jaw.
	_box(Vector3(w * 0.4, hgt * 0.12, ln * 0.34),
		head_pos + Vector3(0, -hgt * 0.16, -ln * 0.03), belly)

	# Long counterbalancing tail (+Z, near horizontal).
	_build_tail(Vector3(0, _base_y + hgt * 0.05, ln * 0.5), ln * 1.4, hgt, w, skin, 5, 0.05)

	# Small arms.
	_cyl(0.08 * w, hgt * 0.3, Vector3(w * 0.35, _base_y - hgt * 0.05, -ln * 0.35),
		Vector3(30, 0, 10), skin)
	_cyl(0.08 * w, hgt * 0.3, Vector3(-w * 0.35, _base_y - hgt * 0.05, -ln * 0.35),
		Vector3(30, 0, -10), skin)

	# Two powerful legs.
	_add_leg(Vector3(w * 0.42, hip, ln * 0.05), hip, w * 0.28, skin, 0.0)
	_add_leg(Vector3(-w * 0.42, hip, ln * 0.05), hip, w * 0.28, skin, PI)


func _build_ceratopsian(data: CreatureData, skin: Material, belly: Material) -> void:
	var s := data.body_size
	var w := s.x
	var hgt := s.y
	var ln := s.z
	var hip := hgt * 0.6
	_base_y = hip * 1.05

	_body = _ellipsoid(Vector3(w * 1.15, hgt * 0.85, ln * 0.95), Vector3(0, _base_y, 0), skin)
	_ellipsoid(Vector3(w * 1.0, hgt * 0.5, ln * 0.75), Vector3(0, _base_y - hgt * 0.18, 0), belly)

	# Big head + bony frill + horns up front (-Z).
	var head_pos := Vector3(0, _base_y + hgt * 0.05, -ln * 0.6)
	_head = _ellipsoid(Vector3(w * 0.7, hgt * 0.55, ln * 0.4), head_pos, skin)
	_head_base_y = head_pos.y
	# Frill: a big flattened plate behind the head.
	var frill := _ellipsoid(Vector3(w * 1.25, hgt * 0.75, ln * 0.12),
		head_pos + Vector3(0, hgt * 0.2, ln * 0.12), belly)
	frill.rotation_degrees.x = -20.0
	# Two brow horns + a nose horn.
	_cyl(0.07 * w, hgt * 0.7, head_pos + Vector3(w * 0.22, hgt * 0.25, -ln * 0.1),
		Vector3(-20, 0, 0), skin)
	_cyl(0.07 * w, hgt * 0.7, head_pos + Vector3(-w * 0.22, hgt * 0.25, -ln * 0.1),
		Vector3(-20, 0, 0), skin)
	_cyl(0.05 * w, hgt * 0.35, head_pos + Vector3(0, hgt * 0.05, -ln * 0.28),
		Vector3(-55, 0, 0), skin)

	_build_tail(Vector3(0, _base_y, ln * 0.45), ln * 0.7, hgt, w, skin, 3, 0.25)

	# Four sturdy legs.
	_add_leg(Vector3(w * 0.6, hip, -ln * 0.25), hip, w * 0.24, skin, 0.0)
	_add_leg(Vector3(-w * 0.6, hip, -ln * 0.25), hip, w * 0.24, skin, PI)
	_add_leg(Vector3(w * 0.6, hip, ln * 0.3), hip, w * 0.24, skin, PI)
	_add_leg(Vector3(-w * 0.6, hip, ln * 0.3), hip, w * 0.24, skin, 0.0)


func _build_ornithomimid(data: CreatureData, skin: Material, belly: Material) -> void:
	# Slender ostrich-like biped (e.g. Gallimimus) — fast, skittish grazer.
	var s := data.body_size
	var w := s.x
	var hgt := s.y
	var ln := s.z
	var hip := hgt * 0.7
	_base_y = hip * 1.02

	_body = _ellipsoid(Vector3(w * 0.8, hgt * 0.55, ln * 0.95), Vector3(0, _base_y, 0), skin)
	_body.rotation.x = deg_to_rad(-6.0)

	# Long slim neck + small head (-Z, up).
	var neck_pos := Vector3(0, _base_y + hgt * 0.3, -ln * 0.42)
	for i in 2:
		var f := i / 2.0
		_cyl(0.1 * w, hgt * 0.45, neck_pos + Vector3(0, hgt * 0.3 * f, -ln * 0.12 * f),
			Vector3(-40, 0, 0), skin)
	var head_pos := neck_pos + Vector3(0, hgt * 0.55, -ln * 0.18)
	_head = _ellipsoid(Vector3(w * 0.28, hgt * 0.2, ln * 0.3), head_pos, skin)
	_head_base_y = head_pos.y

	_build_tail(Vector3(0, _base_y + hgt * 0.05, ln * 0.5), ln * 1.1, hgt, w * 0.8, skin, 4, 0.03)

	_add_leg(Vector3(w * 0.28, hip, ln * 0.05), hip, w * 0.14, skin, 0.0)
	_add_leg(Vector3(-w * 0.28, hip, ln * 0.05), hip, w * 0.14, skin, PI)


func _build_tail(root: Vector3, ln: float, hgt: float, w: float,
		skin: Material, seg: int, drop: float) -> void:
	for i in seg:
		var f := i / float(seg)
		var pos := root + Vector3(0, -drop * hgt * f, ln * 0.22 * (f + 0.4))
		var pivot := Node3D.new()
		pivot.position = pos
		add_child(pivot)
		var m := _cyl(0.26 * w * (1.0 - f * 0.7), ln * 0.24, Vector3.ZERO,
			Vector3(90, 0, 0), skin)
		# reparent under pivot
		remove_child(m)
		pivot.add_child(m)
		_tail_segments.append(pivot)


func _add_leg(hip_pos: Vector3, length: float, radius: float,
		skin: Material, phase: float) -> void:
	var pivot := Node3D.new()
	pivot.position = hip_pos
	add_child(pivot)
	var leg := _cyl(radius, length, Vector3(0, -length * 0.5, 0), Vector3.ZERO, skin)
	remove_child(leg)
	pivot.add_child(leg)
	# a little foot
	var foot := _box(Vector3(radius * 2.2, radius * 0.8, radius * 3.0),
		Vector3(0, -length + radius * 0.4, -radius * 0.4), skin)
	remove_child(foot)
	pivot.add_child(foot)
	_legs.append(pivot)
	_leg_phase.append(phase)


# ---- primitive helpers (all add to self, return the MeshInstance) ----

func _ellipsoid(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	mi.mesh = sph
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, rot_deg: Vector3,
		mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
