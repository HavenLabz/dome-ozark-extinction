extends Node3D
class_name Weapon
## A single weapon: procedural viewmodel, hitscan firing, ammo, reload, spread,
## and muzzle flash. Recoil KICK on the camera is owned by the player (which
## reads this weapon's data on each shot); the weapon animates its own viewmodel
## kick. Attach as a child of the first-person Camera3D.

signal ammo_changed(in_mag: int, reserve: int)
signal reload_started(seconds: float)
signal fired()
## Emitted the instant a shot connects; on_creature true if it hit an animal.
signal shot_hit(on_creature: bool)
## Emitted when the attached optic changes (name for the HUD).
signal optic_changed(name: String)
## Emitted on a well-placed hit ("HEAD" or "VITAL") for HUD feedback.
signal zone_hit(zone: String)

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
var _rest_pos: Vector3          # hip-fire viewmodel position (lower-right)
var _ads_pos: Vector3           # aim-down-sights position (centered)
var _ads_active: bool = false
var _steady: bool = false       # hold-breath
var _aim_blend: float = 0.0     # 0 = hip, 1 = ADS
var _optics: Array = []         # attachment slots: {name, fov, scoped}
var _optic_idx: int = 0
var _kick_pos: Vector3 = Vector3.ZERO
var _kick_rot: float = 0.0
var _mag: MeshInstance3D         # the magazine, animated during reload
var _mag_rest: Vector3           # its resting local position
var _suppressed: bool = false    # deployment attachment: quieter, slightly weaker
var _foregrip: bool = false      # deployment attachment: tighter spread + less kick
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = WeaponData.new()
	_in_mag = data.mag_size
	_reserve = data.reserve_ammo
	_spread = data.spread_base
	_build_viewmodel()
	if _mag:
		_mag_rest = _mag.position
	_apply_attachments()
	call_deferred("_emit_ammo")


## Apply the attachments chosen for this weapon on the deployment screen.
func _apply_attachments() -> void:
	var key := data.resource_path
	var att: Dictionary = GameState.attachments.get(key, {})
	_suppressed = att.get("suppressor", false)
	_foregrip = att.get("foregrip", false)
	# Only override the optic if the deployment screen actually set one; otherwise
	# keep the weapon's own default (e.g. a bolt gun starts scoped).
	if att.has("optic"):
		var idx: int = {"iron": 0, "reflex": 1, "scope": 2}.get(att["optic"], 0)
		_optic_idx = clampi(idx, 0, maxi(0, _optics.size() - 1))
	if _suppressed:
		# A stubby suppressor on the muzzle.
		var can := _part(Vector3(0.05, 0.05, 0.14),
			Vector3(0, 0.03 if data.body_style == "PISTOL" else 0.03, -0.62 if data.body_style != "PISTOL" else -0.24),
			_mk_mat(Color(0.08, 0.08, 0.09), 0.7, 0.45))


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
	# Blend between hip-fire and aim-down-sights (weapon pulls to screen center).
	# Can't aim while reloading — the gun is dropped out of the sight line.
	var want_ads := _ads_active and not _reloading
	_aim_blend = move_toward(_aim_blend, 1.0 if want_ads else 0.0, delta * 10.0)

	# Visible reload: the gun dips down and tilts while the magazine drops out
	# and a fresh one seats — so a reload always reads on screen.
	var reload_dip := Vector3.ZERO
	var reload_tilt := 0.0
	if _reloading and data.reload_time > 0.0:
		var p := clampf(1.0 - _reload_t / data.reload_time, 0.0, 1.0)  # 0..1
		var swing := sin(p * PI)                                       # up at the middle
		reload_dip = Vector3(0.0, -0.14 * swing, 0.02 * swing)
		reload_tilt = 0.6 * swing
		if _mag:
			# Mag drops away in the first half, new one seats in the second.
			var drop := sin(clampf(p, 0.0, 0.5) / 0.5 * PI) if p < 0.5 else sin((1.0 - p) / 0.5 * PI)
			_mag.position = _mag_rest + Vector3(0.0, -0.18 * drop, 0.0)
	elif _mag:
		_mag.position = _mag_rest

	position = _rest_pos.lerp(_ads_pos, _aim_blend) + _kick_pos + reload_dip
	rotation.x = _kick_rot + reload_tilt

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
	if not _suppressed:
		_set_flash(true)
		_flash_t = 0.05
	_eject_casing()
	var bloom := data.spread_per_shot * (data.ads_factor if ads else 1.0)
	if _foregrip:
		bloom *= 0.6   # foregrip tightens the spread bloom
	_spread = minf(data.spread_max, _spread + bloom)
	if data.body_style == "BOW":
		Sfx.play("bow", 1.0, -8.0)
	elif _suppressed:
		Sfx.play("shot", 1.4 if data.body_style == "PISTOL" else 1.25, -16.0)
	elif data.body_style == "SHOTGUN":
		Sfx.play("shot", 0.7, 0.0)   # deeper, louder boom
	else:
		Sfx.play("shot", 1.15 if data.body_style == "PISTOL" else 1.0, -2.0)
	fired.emit()
	return true


## A brass casing arcs out to the right and vanishes — pure feel.
func _eject_casing() -> void:
	var host := get_tree().current_scene
	var cam := get_viewport().get_camera_3d()
	if host == null or cam == null:
		return
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.012
	cm.height = 0.05
	c.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.62, 0.22)
	m.metallic = 0.8
	m.roughness = 0.3
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c.material_override = m
	host.add_child(c)
	var origin := global_position + cam.global_transform.basis.x * 0.15
	c.global_position = origin
	c.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * TAU
	var right := cam.global_transform.basis.x
	var apex := origin + right * 0.5 + Vector3.UP * 0.25
	var tw := c.create_tween()
	tw.tween_property(c, "global_position", apex, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "global_position", apex + right * 0.3 - Vector3.UP * 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_callback(c.queue_free)


func reload() -> void:
	if _reloading or _in_mag >= data.mag_size or _reserve <= 0:
		return
	_reloading = true
	_reload_t = data.reload_time
	Sfx.play("reload", 1.0, -8.0)
	reload_started.emit(data.reload_time)


## Refill this weapon to full from a supply drop.
func resupply() -> void:
	_reserve = data.reserve_ammo
	if not _reloading:
		_in_mag = data.mag_size
	ammo_changed.emit(_in_mag, _reserve)


## Player calls this each frame to raise/lower the sights.
func set_ads(on: bool) -> void:
	_ads_active = on


## Hold-breath steadies the weapon (tighter spread). Player sets this while ADS.
func set_steady(on: bool) -> void:
	_steady = on


# --- Optics / attachments ---
func cycle_optic() -> void:
	if _optics.size() <= 1:
		return
	_optic_idx = (_optic_idx + 1) % _optics.size()
	optic_changed.emit(optic_name())


func optic_name() -> String:
	return _optics[_optic_idx].name if _optics.size() > 0 else "Iron Sights"


func optic_fov() -> float:
	return _optics[_optic_idx].fov if _optics.size() > 0 else 50.0


func optic_scoped() -> bool:
	return _optics.size() > 0 and _optics[_optic_idx].scoped


func current_spread(ads: bool) -> float:
	var s := _spread * (data.ads_factor if ads else 1.0)
	return s * 0.35 if _steady else s


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
		var on_creature := collider != null and collider.has_method("take_damage")
		if on_creature:
			var dmg := data.damage * (1.5 if GameState.legendary_unlocked else 1.0) * (0.85 if _suppressed else 1.0)
			var zone: String = collider.take_damage(dmg, from, hit.get("position"))
			if zone == "HEAD" or zone == "VITAL":
				zone_hit.emit(zone)
		_spawn_impact(hit.get("position"), hit.get("normal"), on_creature)
		shot_hit.emit(on_creature)


## Brief spark/puff where a shot lands. Blood-tone on flesh, dust on terrain.
func _spawn_impact(pos: Vector3, normal: Vector3, on_creature: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.06, 0.05) if on_creature else Color(0.55, 0.5, 0.42)
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	host.add_child(mi)
	mi.global_position = pos + normal * 0.05
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(2.2, 2.2, 2.2), 0.18)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)
	if on_creature:
		_blood_spray(host, pos, normal)


## A short burst of blood droplets kicking back along the shot normal.
func _blood_spray(host: Node, pos: Vector3, normal: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal
	pm.spread = 55.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -14, 0)
	pm.scale_min = 0.03
	pm.scale_max = 0.08
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.5, 0.03, 0.02)
	mesh.material = bm
	p.draw_pass_1 = mesh
	host.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _apply_viewmodel_kick(ads: bool) -> void:
	var f := data.ads_factor if ads else 1.0
	if _foregrip:
		f *= 0.6   # foregrip tames the kick
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
	# Real material set: dark gunmetal, matte polymer, FDE furniture, tactical
	# glove, olive sleeve. `body` carries the weapon's data tint on the receiver.
	var metal := _mk_mat(Color(0.11, 0.11, 0.12), 0.9, 0.32)
	var polymer := _mk_mat(Color(0.06, 0.06, 0.07), 0.1, 0.62)
	var furn := _mk_mat(Color(0.44, 0.37, 0.26), 0.0, 0.6)
	var glove := _mk_mat(Color(0.12, 0.11, 0.10), 0.0, 0.85)
	var sleeve := _mk_mat(Color(0.20, 0.26, 0.19), 0.0, 0.82)
	var body := _mk_mat(data.tint, 0.55, 0.42)

	# Real .gltf/.glb weapon drops in here; procedural mesh is the fallback.
	if data.model_scene != null:
		_build_model_viewmodel(glove, sleeve)
		_build_optics_and_flash()
		return

	match data.body_style:
		"PISTOL":
			_rest_pos = Vector3(0.22, -0.20, -0.45)
			_ads_pos = Vector3(0.0, -0.09, -0.28)
			_part(Vector3(0.052, 0.072, 0.30), Vector3(0, 0.03, -0.03), metal)    # slide
			_part(Vector3(0.05, 0.05, 0.20), Vector3(0, 0.0, -0.10), metal)       # frame/dust cover
			_mag = _part(Vector3(0.048, 0.13, 0.07), Vector3(0, -0.085, 0.055), polymer)
			_part(Vector3(0.05, 0.028, 0.11), Vector3(0, -0.028, 0.015), polymer) # trigger guard
			_part(Vector3(0.008, 0.022, 0.008), Vector3(0, 0.078, -0.16), metal)  # front sight
			_part(Vector3(0.006, 0.02, 0.008), Vector3(-0.014, 0.072, 0.10), metal)
			_part(Vector3(0.006, 0.02, 0.008), Vector3(0.014, 0.072, 0.10), metal)
			_muzzle = _point(Vector3(0, 0.03, -0.19))
			_build_arms(Vector3(0.0, -0.085, 0.06), Vector3(-0.045, -0.10, 0.02), glove, sleeve)
		"SHOTGUN":
			_rest_pos = Vector3(0.26, -0.22, -0.52)
			_ads_pos = Vector3(0.0, -0.11, -0.30)
			_part(Vector3(0.075, 0.085, 0.40), Vector3(0, 0, 0.02), body)        # receiver
			_part(Vector3(0.055, 0.055, 0.42), Vector3(0, 0.03, -0.34), metal)   # thick barrel
			_mag = _part(Vector3(0.05, 0.045, 0.22), Vector3(0, -0.03, -0.28), metal)  # tube mag
			_part(Vector3(0.075, 0.06, 0.12), Vector3(0, -0.05, -0.20), furn)    # pump fore-grip
			_part(Vector3(0.05, 0.10, 0.07), Vector3(0, -0.085, 0.13), polymer)  # grip
			_part(Vector3(0.075, 0.11, 0.22), Vector3(0, -0.01, 0.31), furn)     # stock
			_part(Vector3(0.008, 0.03, 0.008), Vector3(0, 0.078, -0.34), metal)  # bead
			_muzzle = _point(Vector3(0, 0.03, -0.56))
			_build_arms(Vector3(0.0, -0.07, -0.18), Vector3(0.0, -0.045, -0.28), glove, sleeve)
		"SNIPER":
			_rest_pos = Vector3(0.26, -0.22, -0.55)
			_ads_pos = Vector3(0.0, -0.085, -0.26)
			_part(Vector3(0.06, 0.07, 0.44), Vector3(0, 0, 0), body)             # receiver
			_part(Vector3(0.032, 0.032, 0.64), Vector3(0, 0.02, -0.52), metal)   # long thin barrel
			_mag = _part(Vector3(0.05, 0.10, 0.06), Vector3(0, -0.085, 0.02), polymer)
			_part(Vector3(0.05, 0.10, 0.07), Vector3(0, -0.09, 0.13), furn)      # grip
			_part(Vector3(0.075, 0.11, 0.32), Vector3(0, -0.01, 0.35), furn)     # long wood stock
			_part(Vector3(0.05, 0.05, 0.26), Vector3(0, 0.105, -0.02), metal)    # scope tube
			_part(Vector3(0.018, 0.05, 0.02), Vector3(0, 0.078, -0.12), metal)   # front ring
			_part(Vector3(0.018, 0.05, 0.02), Vector3(0, 0.078, 0.08), metal)    # rear ring
			_part(Vector3(0.018, 0.018, 0.07), Vector3(0.055, 0.01, 0.07), metal)# bolt handle
			_muzzle = _point(Vector3(0, 0.02, -0.80))
			_build_arms(Vector3(0.0, -0.09, -0.20), Vector3(0.0, -0.045, 0.02), glove, sleeve)
		"BOW":
			_rest_pos = Vector3(0.24, -0.20, -0.50)
			_ads_pos = Vector3(0.0, -0.10, -0.30)
			_part(Vector3(0.04, 0.05, 0.50), Vector3(0, 0, 0.04), furn)          # stock rail
			_part(Vector3(0.03, 0.04, 0.34), Vector3(0, 0.03, -0.26), metal)     # flight groove
			var limb_l := _part(Vector3(0.24, 0.03, 0.04), Vector3(-0.12, 0.04, -0.36), metal)
			limb_l.rotation.z = 0.4
			var limb_r := _part(Vector3(0.24, 0.03, 0.04), Vector3(0.12, 0.04, -0.36), metal)
			limb_r.rotation.z = -0.4
			_part(Vector3(0.46, 0.005, 0.005), Vector3(0, 0.03, -0.30), metal)   # string
			_mag = _part(Vector3(0.035, 0.05, 0.05), Vector3(0, -0.05, 0.05), polymer)  # trigger
			_part(Vector3(0.05, 0.10, 0.07), Vector3(0, -0.085, 0.10), polymer)  # grip
			_part(Vector3(0.008, 0.03, 0.008), Vector3(0, 0.075, -0.28), metal)  # sight
			_muzzle = _point(Vector3(0, 0.04, -0.50))
			_build_arms(Vector3(0.0, -0.075, -0.02), Vector3(0.0, -0.045, 0.12), glove, sleeve)
		_:  # RIFLE
			_rest_pos = Vector3(0.26, -0.22, -0.55)
			_ads_pos = Vector3(0.0, -0.115, -0.30)
			_part(Vector3(0.07, 0.09, 0.42), Vector3(0, 0, 0), body)             # receiver (tinted)
			_part(Vector3(0.042, 0.042, 0.46), Vector3(0, 0.03, -0.42), metal)   # barrel
			_part(Vector3(0.058, 0.055, 0.26), Vector3(0, 0.005, -0.30), furn)   # handguard
			_mag = _part(Vector3(0.055, 0.15, 0.085), Vector3(0, -0.125, 0.05), polymer)
			_part(Vector3(0.05, 0.11, 0.07), Vector3(0, -0.095, 0.14), polymer)  # pistol grip
			_part(Vector3(0.062, 0.10, 0.22), Vector3(0, -0.005, 0.31), furn)    # stock
			_part(Vector3(0.028, 0.016, 0.30), Vector3(0, 0.062, -0.06), polymer)# low top rail
			_part(Vector3(0.007, 0.032, 0.007), Vector3(0, 0.086, -0.40), metal) # front sight
			_part(Vector3(0.006, 0.028, 0.008), Vector3(-0.017, 0.078, 0.15), metal)
			_part(Vector3(0.006, 0.028, 0.008), Vector3(0.017, 0.078, 0.15), metal)
			_muzzle = _point(Vector3(0, 0.03, -0.62))
			_build_arms(Vector3(0.0, -0.095, 0.14), Vector3(0.0, -0.045, -0.28), glove, sleeve)

	_build_optics_and_flash()


## Instantiate a real weapon model as the viewmodel. Position/scale/rotation are
## tuned per-weapon via the WeaponData knobs; a child node named "Muzzle" marks
## the barrel tip if present, else a sensible default point is used. Gloved arms
## are kept (set them off in the model itself if it ships its own hands).
func _build_model_viewmodel(glove: Material, sleeve: Material) -> void:
	if data.body_style == "PISTOL":
		_rest_pos = Vector3(0.22, -0.20, -0.45)
		_ads_pos = Vector3(0.0, -0.09, -0.28)
	else:
		_rest_pos = Vector3(0.26, -0.22, -0.55)
		_ads_pos = Vector3(0.0, -0.115, -0.30)
	var m := data.model_scene.instantiate() as Node3D
	if m:
		m.position = data.model_offset
		m.scale = Vector3.ONE * data.model_scale
		m.rotation_degrees = data.model_rotation
		add_child(m)
		_muzzle = m.find_child("Muzzle", true, false) as Node3D
	if _muzzle == null:
		_muzzle = _point(Vector3(0, 0.03, -0.6 if data.body_style != "PISTOL" else -0.2))
	if data.body_style == "PISTOL":
		_build_arms(Vector3(0.0, -0.085, 0.06), Vector3(-0.045, -0.10, 0.02), glove, sleeve)
	else:
		_build_arms(Vector3(0.0, -0.095, 0.14), Vector3(0.0, -0.045, -0.28), glove, sleeve)


## Optics + muzzle flash — shared by procedural and real-model viewmodels.
func _build_optics_and_flash() -> void:
	# Optic loadout (cycle with V).
	match data.body_style:
		"PISTOL", "SHOTGUN", "BOW":
			_optics = [
				{"name": "Iron Sights", "fov": 52.0, "scoped": false},
				{"name": "Reflex Sight", "fov": 46.0, "scoped": false},
			]
		"SNIPER":
			_optics = [
				{"name": "Iron Sights", "fov": 48.0, "scoped": false},
				{"name": "4x Scope", "fov": 20.0, "scoped": true},
				{"name": "8x Scope", "fov": 10.0, "scoped": true},
			]
			_optic_idx = 1   # bolt guns come scoped by default
		_:
			_optics = [
				{"name": "Iron Sights", "fov": 50.0, "scoped": false},
				{"name": "Reflex Sight", "fov": 44.0, "scoped": false},
				{"name": "4x Hunting Scope", "fov": 20.0, "scoped": true},
			]

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


func _mk_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## First-person arms: a gloved hand on the gun at each grip point, with an
## olive-sleeved forearm running back toward the shoulder. Children of the
## weapon, so they ride every kick, sway and ADS move with it.
func _build_arms(support_hand: Vector3, firing_hand: Vector3, glove: Material, sleeve: Material) -> void:
	# Firing (right) hand + forearm from the right shoulder.
	_hand(firing_hand, glove)
	_limb(Vector3(0.14, -0.36, 0.42), firing_hand, 0.052, sleeve)
	# Support (left) hand + forearm from the left shoulder.
	_hand(support_hand, glove)
	_limb(Vector3(-0.14, -0.36, 0.46), support_hand, 0.052, sleeve)


## A gloved hand: a palm block plus a wrap of fingers curling over the grip.
func _hand(pos: Vector3, glove: Material) -> void:
	var palm := _part(Vector3(0.058, 0.05, 0.085), pos, glove)
	palm.rotation.x = 0.35
	# Four fingers wrapping down over the front of the grip.
	var fingers := _part(Vector3(0.056, 0.055, 0.02), pos + Vector3(0, -0.012, -0.05), glove)
	fingers.rotation.x = 0.5
	# Thumb along the side.
	var thumb := _part(Vector3(0.02, 0.02, 0.05), pos + Vector3(0.03, 0.006, 0.0), glove)


## A tapered limb segment from `from` to `to`, oriented along the line.
func _limb(from: Vector3, to: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	var length := from.distance_to(to)
	b.size = Vector3(thick, thick, length)
	mi.mesh = b
	mi.material_override = mat
	var dir := (to - from).normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var xf := Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5)
	mi.transform = xf
	add_child(mi)
	return mi


func _point(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n
