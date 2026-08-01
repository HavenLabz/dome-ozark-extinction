extends Node3D
class_name Weapon
## A single weapon: procedural viewmodel, hitscan firing, ammo, reload, spread,
## and muzzle flash. Recoil KICK on the camera is owned by the player (which
## reads this weapon's data on each shot); the weapon animates its own viewmodel
## kick. Attach as a child of the first-person Camera3D.

signal ammo_changed(in_mag: int, reserve: int)
signal reload_started(seconds: float)
signal fired()

@export var data: WeaponData

const _WORLD := 1
const _CREATURES := 4

var _in_mag: int = 0
var _reserve: int = 0
var _fire_cd: float = 0.0
var _reloading: bool = false
var _reload_t: float = 0.0
var _spread: float = 0.0

var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_t: float = 0.0
var _rest_pos: Vector3
var _kick_pos: Vector3 = Vector3.ZERO
var _kick_rot: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = WeaponData.new()
	_in_mag = data.mag_size
	_reserve = data.reserve_ammo
	_spread = data.spread_base
	_build_viewmodel()
	call_deferred("_emit_ammo")


func _emit_ammo() -> void:
	ammo_changed.emit(_in_mag, _reserve)


func _process(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	# Spread decays back toward base when not firing.
	_spread = maxf(data.spread_base, _spread - data.spread_per_shot * 4.0 * delta)

	if _reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()

	# Recover viewmodel kick.
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	_kick_rot = lerpf(_kick_rot, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	position = _rest_pos + _kick_pos
	rotation.x = _kick_rot

	# Muzzle flash timeout.
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_set_flash(false)


## Returns true if a shot was actually fired (for the player to apply recoil).
func try_fire(ads: bool) -> bool:
	if _reloading or _fire_cd > 0.0:
		return false
	if _in_mag <= 0:
		return false
	_fire_cd = 60.0 / maxf(1.0, data.rounds_per_minute)
	_in_mag -= 1
	ammo_changed.emit(_in_mag, _reserve)
	_do_hitscan(ads)
	_apply_viewmodel_kick(ads)
	_set_flash(true)
	_flash_t = 0.05
	var bloom := data.spread_per_shot * (data.ads_factor if ads else 1.0)
	_spread = minf(data.spread_max, _spread + bloom)
	fired.emit()
	return true


func reload() -> void:
	if _reloading or _in_mag >= data.mag_size or _reserve <= 0:
		return
	_reloading = true
	_reload_t = data.reload_time
	reload_started.emit(data.reload_time)


func current_spread(ads: bool) -> float:
	return _spread * (data.ads_factor if ads else 1.0)


func get_ammo() -> Vector2i:
	return Vector2i(_in_mag, _reserve)


func is_reloading() -> bool:
	return _reloading


# ---------------------------------------------------------------------------

func _finish_reload() -> void:
	_reloading = false
	var need := data.mag_size - _in_mag
	var take := mini(need, _reserve)
	_in_mag += take
	_reserve -= take
	ammo_changed.emit(_in_mag, _reserve)


func _do_hitscan(ads: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var space := cam.get_world_3d().direct_space_state
	var spread := current_spread(ads)
	for i in maxi(1, data.pellets):
		var dir := -cam.global_transform.basis.z
		# Cone spread.
		dir = dir.rotated(cam.global_transform.basis.x, _rng.randf_range(-spread, spread))
		dir = dir.rotated(cam.global_transform.basis.y, _rng.randf_range(-spread, spread))
		var from := cam.global_position
		var to := from + dir * data.range
		var q := PhysicsRayQueryParameters3D.create(from, to, _WORLD | _CREATURES)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(data.damage, from)


func _apply_viewmodel_kick(ads: bool) -> void:
	var f := data.ads_factor if ads else 1.0
	_kick_pos += Vector3(0, 0, 0.06 * f)   # push toward the camera (+z)
	_kick_rot += 0.05 * f                   # tip the muzzle up


func _set_flash(on: bool) -> void:
	if _flash:
		_flash.visible = on
	if _flash_light:
		_flash_light.visible = on


# ---------------------------------------------------------------------------
# Procedural viewmodel (placeholder until real models)
# ---------------------------------------------------------------------------

func _build_viewmodel() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.tint
	mat.metallic = 0.6
	mat.roughness = 0.4

	if data.body_style == "PISTOL":
		_rest_pos = Vector3(0.22, -0.20, -0.45)
		_part(Vector3(0.07, 0.09, 0.28), Vector3(0, 0.02, -0.02), mat)      # slide
		_part(Vector3(0.06, 0.16, 0.08), Vector3(0, -0.10, 0.06), mat)      # grip
		_muzzle = _point(Vector3(0, 0.03, -0.18))
	else:  # RIFLE
		_rest_pos = Vector3(0.26, -0.22, -0.55)
		_part(Vector3(0.08, 0.10, 0.42), Vector3(0, 0, 0), mat)             # receiver
		_part(Vector3(0.05, 0.05, 0.40), Vector3(0, 0.02, -0.36), mat)      # barrel/handguard
		_part(Vector3(0.06, 0.16, 0.09), Vector3(0, -0.12, 0.05), mat)      # magazine
		_part(Vector3(0.07, 0.09, 0.20), Vector3(0, -0.01, 0.28), mat)      # stock
		_muzzle = _point(Vector3(0, 0.02, -0.56))

	position = _rest_pos

	# Muzzle flash: a small emissive card + a brief light.
	_flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	_flash.mesh = qm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.8, 0.35, 1.0)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.7, 0.2)
	fm.emission_energy_multiplier = 6.0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.material_override = fm
	_flash.visible = false
	_muzzle.add_child(_flash)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.35)
	_flash_light.light_energy = 4.0
	_flash_light.omni_range = 6.0
	_flash_light.visible = false
	_muzzle.add_child(_flash_light)


func _part(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _point(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n
