extends Node
class_name DayNightCycle
## Drives a full day/night cycle: sun elevation + color, ambient, sky brightness,
## and fog. Night is dark, cold-blue, and foggier — the wilderness gets more
## dangerous after dark (North Star: preserve fear/vulnerability).

@export var day_length_sec: float = 480.0     # full 24h cycle in real seconds
@export_range(0.0, 1.0) var start_time: float = 0.42   # mid-morning, bright
@export var sun_path: NodePath = ^"../DirectionalLight3D"
@export var env_path: NodePath = ^"../WorldEnvironment"

var time_of_day: float = 0.42   # 0=midnight, .25=sunrise, .5=noon, .75=sunset

@onready var _sun: DirectionalLight3D = get_node_or_null(sun_path)
@onready var _we: WorldEnvironment = get_node_or_null(env_path)

var _day_sun := Color(1.0, 0.96, 0.89)
var _dusk_sun := Color(1.0, 0.6, 0.35)


func _ready() -> void:
	time_of_day = start_time
	_apply()


func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / maxf(1.0, day_length_sec), 1.0)
	_apply()


## True between sunset and sunrise — creatures/systems can key off this later.
func is_night() -> bool:
	return _sun_elevation() < 0.05


func _sun_elevation() -> float:
	# 0 at sunrise/sunset, 1 at noon, negative at night.
	return sin((time_of_day - 0.25) * TAU)


func _apply() -> void:
	var elev := _sun_elevation()
	var day := clampf(elev, 0.0, 1.0)          # 0 night .. 1 noon
	var horizon := clampf(1.0 - absf(elev) * 3.0, 0.0, 1.0)  # peaks at dawn/dusk

	if _sun:
		# Arc the sun east→west and drop it below the horizon at night.
		var azimuth := time_of_day * TAU
		_sun.rotation = Vector3(deg_to_rad(-elev * 75.0 - 4.0), azimuth, 0.0)
		_sun.light_energy = lerpf(0.06, 1.6, day)      # moonlight .. bright noon
		_sun.light_color = _day_sun.lerp(_dusk_sun, horizon)
		_sun.shadow_enabled = day > 0.02

	if _we and _we.environment:
		var env := _we.environment
		env.ambient_light_energy = lerpf(0.14, 0.6, day)
		env.ambient_light_color = Color(0.35, 0.42, 0.6).lerp(Color(0.6, 0.66, 0.66), day)
		env.fog_density = lerpf(0.006, 0.0009, day)     # foggier at night
		env.fog_light_color = Color(0.18, 0.22, 0.34).lerp(Color(0.7, 0.8, 0.92), day)
		env.volumetric_fog_density = lerpf(0.012, 0.004, day)
		var sky_mat := env.sky.sky_material if env.sky else null
		if sky_mat is ProceduralSkyMaterial:
			(sky_mat as ProceduralSkyMaterial).energy_multiplier = lerpf(0.15, 1.0, day)
