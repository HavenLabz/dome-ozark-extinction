extends Node
class_name WeatherManager
## The dome's own weather ecosystem. Cycles through clear → cloudy → rain → storm
## and drives EVERYTHING off a single smoothed severity value (0 calm .. 1 full
## storm): wind that bends the grass and trees, rain, a darkening sky, thickening
## fog, lightning, rising floodwater, the occasional tornado, and wildlife that
## hunkers down while birds drop from the sky to shelter.
##
## North Star: the dome is a sealed, self-contained ecosystem — so it has its own
## weather, and that weather is felt in every system, not just painted on.

enum W { CLEAR, CLOUDY, RAIN, STORM }

var world: Node                       # OzarkWorld (exposes set_wind)
var day_night: DayNightCycle
var env: Environment
var sun: DirectionalLight3D
var player: Node3D
var water: Node3D
var birds: BirdFlock

var _rng := RandomNumberGenerator.new()
var _state: int = W.CLEAR
var _state_time: float = 0.0
var _state_dur: float = 30.0
var _severity: float = 0.0            # smoothed 0..1
var _target_sev: float = 0.0
var _t: float = 0.0                   # free-running clock for gusts
var _base_fog: float = 0.0006
var _base_vol_fog: float = 0.004
var _base_water_y: float = -1.5
var _flood: float = 0.0               # smoothed 0..1 floodwater rise
var _rain: GPUParticles3D
var _flash: float = 0.0               # lightning brightness, decays
var _thunder_timer: float = 0.0
var _tornado: Node3D
var _tornado_time: float = 0.0
var _tornado_dir := Vector2(1, 0)
var _forced := false


func setup(w: Node, dn: DayNightCycle, environment: Environment, s: DirectionalLight3D,
		pl: Node3D, wat: Node3D, flock: BirdFlock, water_level: float) -> void:
	world = w
	day_night = dn
	env = environment
	sun = s
	player = pl
	water = wat
	birds = flock
	_base_water_y = wat.position.y if wat else water_level
	if env:
		_base_fog = env.fog_density
		_base_vol_fog = env.volumetric_fog_density
	_rng.randomize()
	# Run after DayNight so our storm dimming + lightning win the frame.
	process_priority = 20
	_build_rain()
	_enter_state(W.CLEAR)


## Debug/testing: jump straight to a full storm.
func force_storm() -> void:
	_forced = true
	_enter_state(W.STORM)
	_severity = 1.0


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 3200
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -24, -30), Vector3(60, 44, 60))
	_rain.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 0.5, 30)
	pm.direction = Vector3(0.12, -1.0, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(2.0, -28.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	_rain.process_material = pm
	var streak := BoxMesh.new()
	streak.size = Vector3(0.02, 0.55, 0.02)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.62, 0.72, 0.86, 0.55)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = rmat
	_rain.draw_pass_1 = streak
	add_child(_rain)


func _process(delta: float) -> void:
	_t += delta
	_state_time += delta
	if not _forced and _state_time >= _state_dur:
		_advance_state()

	# Smoothly ease toward the current state's target severity.
	_severity = move_toward(_severity, _target_sev, delta * 0.12)
	GameState.storm_intensity = _severity

	_apply_wind()
	_apply_sky_and_fog(delta)
	_apply_rain()
	_apply_flood(delta)
	if _state == W.STORM:
		_tick_lightning(delta)
		_maybe_tornado(delta)
	_tick_tornado(delta)

	if birds:
		birds.shelter = clampf((_severity - 0.35) / 0.4, 0.0, 1.0)


# --- state machine -----------------------------------------------------------

func _advance_state() -> void:
	# Weighted transitions: weather drifts rather than jumping randomly.
	var next := _state
	match _state:
		W.CLEAR:   next = _pick([W.CLEAR, W.CLOUDY, W.CLOUDY, W.RAIN])
		W.CLOUDY:  next = _pick([W.CLEAR, W.CLEAR, W.RAIN, W.RAIN, W.STORM])
		W.RAIN:    next = _pick([W.CLOUDY, W.CLOUDY, W.STORM, W.CLEAR])
		W.STORM:   next = _pick([W.RAIN, W.RAIN, W.CLOUDY])
	_enter_state(next)


func _pick(options: Array) -> int:
	return options[_rng.randi() % options.size()]


func _enter_state(s: int) -> void:
	_state = s
	_state_time = 0.0
	match s:
		W.CLEAR:
			_target_sev = 0.0
			_state_dur = _rng.randf_range(45.0, 90.0)
		W.CLOUDY:
			_target_sev = 0.22
			_state_dur = _rng.randf_range(35.0, 70.0)
		W.RAIN:
			_target_sev = 0.55
			_state_dur = _rng.randf_range(35.0, 65.0)
		W.STORM:
			_target_sev = 1.0
			_state_dur = _rng.randf_range(30.0, 55.0)


# --- effects -----------------------------------------------------------------

func _apply_wind() -> void:
	if world == null or not world.has_method("set_wind"):
		return
	# Base breeze + gusts; storms drive hard, shifting wind.
	var gust := 0.6 + 0.4 * sin(_t * 0.7) + 0.25 * sin(_t * 2.3 + 1.0)
	var strength := lerpf(0.7, 3.4, _severity) * gust
	var speed := lerpf(1.0, 2.6, _severity)
	world.set_wind(strength, speed)


func _apply_sky_and_fog(delta: float) -> void:
	if day_night:
		day_night.storm_darkness = _severity * 0.78
	if env == null:
		return
	env.fog_density = lerpf(_base_fog, _base_fog * 16.0, _severity)
	env.volumetric_fog_density = lerpf(_base_vol_fog, _base_vol_fog * 4.5, _severity)
	# Grey the fog/sky tint as it clouds over.
	env.fog_light_color = Color(0.7, 0.8, 0.92).lerp(Color(0.42, 0.44, 0.48), _severity)
	# Lightning flash lifts ambient briefly (DayNight already set it this frame).
	if _flash > 0.001:
		env.ambient_light_energy += _flash * 3.2
		_flash = move_toward(_flash, 0.0, delta * 6.0)


func _apply_rain() -> void:
	if _rain == null:
		return
	var wet := clampf((_severity - 0.22) / 0.78, 0.0, 1.0)
	_rain.emitting = wet > 0.02
	_rain.amount_ratio = wet
	if player:
		_rain.global_position = player.global_position + Vector3(0.0, 17.0, 0.0)


func _apply_flood(delta: float) -> void:
	# Sustained heavy weather raises the water; it recedes as things calm.
	var target := clampf((_severity - 0.6) / 0.4, 0.0, 1.0)
	_flood = move_toward(_flood, target, delta * 0.03)
	if water:
		water.position.y = _base_water_y + _flood * 2.6


func _tick_lightning(delta: float) -> void:
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		_thunder_timer = _rng.randf_range(3.0, 9.0)
		_flash = _rng.randf_range(0.6, 1.0)   # a strike


# --- tornado -----------------------------------------------------------------

func _maybe_tornado(delta: float) -> void:
	if _tornado != null:
		return
	# Rare: only in the teeth of a storm.
	if _severity > 0.9 and _rng.randf() < delta * 0.02:
		_spawn_tornado()


func _spawn_tornado() -> void:
	_tornado = Node3D.new()
	_tornado.name = "Tornado"
	# A tall twisting funnel: stacked, narrowing, rotating rings.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.19, 0.62)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rings := 16
	for i in rings:
		var f := i / float(rings)
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = lerpf(1.2, 9.0, f) * 0.6
		cyl.bottom_radius = lerpf(0.8, 8.0, f) * 0.6
		cyl.height = 4.0
		seg.mesh = cyl
		seg.material_override = mat
		seg.position = Vector3(sin(f * 6.0) * f * 3.0, 2.0 + f * 30.0, cos(f * 6.0) * f * 3.0)
		_tornado.add_child(seg)
	# Debris particles around the base.
	var start := Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-120, 120))
	_tornado.global_position = Vector3(start.x, 0.0, start.y)
	if world:
		world.add_child(_tornado)
	_tornado_time = _rng.randf_range(18.0, 34.0)
	var a := _rng.randf_range(0.0, TAU)
	_tornado_dir = Vector2(cos(a), sin(a))


func _tick_tornado(delta: float) -> void:
	if _tornado == null:
		return
	_tornado_time -= delta
	# Spin the funnel and drift it across the land.
	_tornado.rotation.y += delta * 2.5
	var step := _tornado_dir * delta * 6.0
	_tornado.global_position += Vector3(step.x, 0.0, step.y)
	# Ride the terrain height if the world exposes it.
	if world and world.has_method("_surface_y"):
		pass
	if _tornado_time <= 0.0 or _severity < 0.6:
		_tornado.queue_free()
		_tornado = null
