extends Node
## Procedural audio — every sound is synthesized in code at boot (no audio files,
## $0). One-shots are AudioStreamWAV buffers; wind/rain are looping buffers whose
## volume tracks the weather. Positional calls play through AudioStreamPlayer3D so
## you can hear where a creature is. Autoload as `Sfx`.

const RATE := 22050

var _rng := RandomNumberGenerator.new()
var _lib: Dictionary = {}                 # name -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []  # non-positional one-shot pool
var _pool_i: int = 0
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer


func _ready() -> void:
	_rng.randomize()
	_build_library()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_wind = _loop_player(_lib["wind"], -40.0)
	_rain = _loop_player(_lib["rain"], -60.0)


var _beat_t: float = 0.0


func _process(delta: float) -> void:
	# Ambience follows the weather: wind always breathes, louder in storms; rain
	# fades in with severity.
	var s: float = GameState.storm_intensity
	_wind.volume_db = lerpf(-26.0, -8.0, s)
	_rain.volume_db = -60.0 if s < 0.22 else lerpf(-30.0, -6.0, clampf((s - 0.22) / 0.78, 0.0, 1.0))

	# "You're being hunted" — a heartbeat that quickens as the stalker closes.
	var d: float = GameState.danger
	if d > 0.08:
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = lerpf(1.1, 0.42, d)          # faster when the threat is near
			play("heartbeat", 1.0, lerpf(-16.0, -2.0, d))
	else:
		_beat_t = 0.0


# --- public API --------------------------------------------------------------

func play(name: String, pitch: float = 1.0, vol_db: float = -6.0) -> void:
	var stream: AudioStreamWAV = _lib.get(name)
	if stream == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = vol_db
	p.play()


## Positional one-shot (creature calls, distant shots) that falls off with range.
func play_at(name: String, pos: Vector3, pitch: float = 1.0, vol_db: float = 4.0) -> void:
	var stream: AudioStreamWAV = _lib.get(name)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	p.volume_db = vol_db
	p.max_distance = 140.0
	p.unit_size = 12.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


# --- synthesis ---------------------------------------------------------------

func _loop_player(stream: AudioStreamWAV, vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	add_child(p)
	p.play()
	return p


func _build_library() -> void:
	_lib["shot"] = _wav(_synth_shot())
	_lib["shot_far"] = _wav(_synth_shot(0.6))
	_lib["reload"] = _wav(_synth_click(0.05, 900.0))
	_lib["step"] = _wav(_synth_thud(0.09, 140.0))
	_lib["chime"] = _wav(_synth_chime())
	_lib["thunder"] = _wav(_synth_thunder())
	_lib["roar"] = _wav(_synth_roar(90.0, 1.0))     # base; pitch-shifted per species
	_lib["screech"] = _wav(_synth_roar(320.0, 0.55))
	_lib["chirp"] = _wav(_synth_chirp())
	_lib["wind"] = _wav(_synth_wind(), true)
	_lib["rain"] = _wav(_synth_rain(), true)
	_lib["heartbeat"] = _wav(_synth_heartbeat())
	_lib["bow"] = _wav(_synth_bow())


## Crossbow release — a short low twang plus a whoosh.
func _synth_bow() -> PackedFloat32Array:
	var len := int(RATE * 0.25)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		var twang := sin(t * TAU * 180.0 * exp(-t * 3.0)) * exp(-t * 12.0)
		var air := _rng.randf_range(-1.0, 1.0) * exp(-t * 20.0) * 0.3
		s[i] = clampf(twang * 0.7 + air, -1.0, 1.0)
	return s


func _synth_heartbeat() -> PackedFloat32Array:
	# Two low thumps (lub-dub) with fast decay.
	var len := int(RATE * 0.32)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		var a := sin(t * TAU * 55.0) * exp(-t * 22.0)
		var b := sin((t - 0.14) * TAU * 48.0) * exp(-(t - 0.14) * 24.0) if t > 0.14 else 0.0
		s[i] = clampf(a + b, -1.0, 1.0) * 0.9
	return s


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _n(count: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(count)
	return a


## Rifle crack: a sharp noise transient with a fast exponential tail + low thump.
func _synth_shot(scale: float = 1.0) -> PackedFloat32Array:
	var len := int(RATE * 0.28)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		var env := exp(-t * 28.0)
		var thump := sin(t * TAU * 70.0) * exp(-t * 14.0) * 0.5
		s[i] = (_rng.randf_range(-1.0, 1.0) * env + thump) * scale
	return s


## Low, throaty roar with vibrato and a breathy noise layer.
func _synth_roar(base_hz: float, dur: float) -> PackedFloat32Array:
	var len := int(RATE * dur)
	var s := _n(len)
	var phase := 0.0
	for i in len:
		var t := i / float(len)
		var env := sin(t * PI)                      # swell in and out
		var hz := base_hz * (1.0 + 0.06 * sin(t * TAU * 6.0))
		phase += hz / RATE * TAU
		var tone := sin(phase) + 0.4 * sin(phase * 2.0)
		var breath := _rng.randf_range(-1.0, 1.0) * 0.25
		s[i] = (tone * 0.6 + breath) * env
	return s


## Small bird/prey chirp — a couple of quick rising blips.
func _synth_chirp() -> PackedFloat32Array:
	var len := int(RATE * 0.22)
	var s := _n(len)
	for i in len:
		var t := i / float(len)
		var hz := lerpf(1400.0, 2200.0, t)
		var env := sin(t * PI) * (1.0 if fmod(t, 0.5) < 0.4 else 0.0)
		s[i] = sin(i / float(RATE) * TAU * hz) * env * 0.5
	return s


func _synth_thud(dur: float, hz: float) -> PackedFloat32Array:
	var len := int(RATE * dur)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		var env := exp(-t * 30.0)
		s[i] = (sin(t * TAU * hz) * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.4) * env
	return s


func _synth_click(dur: float, hz: float) -> PackedFloat32Array:
	var len := int(RATE * dur)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		s[i] = sin(t * TAU * hz) * exp(-t * 60.0) * 0.5
	return s


func _synth_chime() -> PackedFloat32Array:
	var len := int(RATE * 0.5)
	var s := _n(len)
	for i in len:
		var t := i / float(RATE)
		var env := exp(-t * 5.0)
		s[i] = (sin(t * TAU * 880.0) + 0.6 * sin(t * TAU * 1320.0)) * env * 0.4
	return s


func _synth_thunder() -> PackedFloat32Array:
	var len := int(RATE * 2.2)
	var s := _n(len)
	var lp := 0.0
	for i in len:
		var t := i / float(len)
		var env := (1.0 - t) * (1.0 if t > 0.02 else t / 0.02)
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.06)   # low-pass rumble
		s[i] = lp * env * 0.9
	return s


## Build a click-free, dip-free loop of `len` samples from `raw` (which must hold
## len+xf samples). The final `xf` samples are the buffer's own natural continuation
## past the loop point, crossfaded over the head — so s[len-1]->s[0] is continuous
## (no click) with no fade-to-silence at the seam (no pulsing).
func _seamless(raw: PackedFloat32Array, len: int, xf: int) -> PackedFloat32Array:
	var s := _n(len)
	for i in len:
		s[i] = raw[i]
	for i in xf:
		var w := i / float(xf)                       # 0 at seam -> 1 by end of xf
		s[i] = raw[i] * w + raw[len + i] * (1.0 - w)
	return s


func _synth_wind() -> PackedFloat32Array:
	# Steady band-limited air hiss — NO amplitude envelope. The old swelling gust
	# is what read as rhythmic "waves" on every loop; a constant hiss can't pulse.
	var len := int(RATE * 4.0)
	var xf := int(RATE * 0.5)
	var raw := _n(len + xf)
	var lp := 0.0
	for i in len + xf:
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.045)   # low-passed white = soft wind hiss
		raw[i] = lp * 0.9
	return _seamless(raw, len, xf)


func _synth_rain() -> PackedFloat32Array:
	var len := int(RATE * 3.0)
	var xf := int(RATE * 0.3)
	var raw := _n(len + xf)
	var hp := 0.0
	for i in len + xf:
		var white := _rng.randf_range(-1.0, 1.0)
		hp = white - lerpf(hp, white, 0.5)   # crude high-pass hiss
		raw[i] = hp * 0.7
	return _seamless(raw, len, xf)
