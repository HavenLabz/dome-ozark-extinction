extends StaticBody3D
class_name AerialCreature
## A soaring flyer (dragon / phoenix / pterodactyl): loads a GLB, hides any stray
## ground/shadow plane, scales to a target wingspan, plays its looping animation,
## and circles the dome at altitude. Shoot it and it drops from the sky as a
## trophy. On the creature layer so weapon hitscans connect.

var model_path := ""
var wingspan := 16.0
var altitude := 55.0
var radius := 100.0
var ang_speed := 0.12
var center := Vector3.ZERO
var trophy_id := &"aerial_trophy"
var trophy_value := 400
var call_sound := "screech"
var hp := 140.0

var _t := 0.0
var _dead := false
var _vel := Vector3.ZERO
var _call_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = 4          # creature layer — weapons hit this
	collision_mask = 0
	add_to_group("wildlife")
	_rng.randomize()
	_t = _rng.randf() * TAU
	_call_t = _rng.randf_range(3.0, 10.0)

	var scene := load(model_path) as PackedScene
	if scene:
		var m := scene.instantiate() as Node3D
		add_child(m)
		# Hide stray shadow/ground planes (huge + flat).
		for n in m.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var sz := mi.mesh.get_aabb().size
			if "plane" in mi.name.to_lower() or (maxf(sz.x, sz.z) > 40.0 and sz.y < maxf(sz.x, sz.z) * 0.06):
				mi.visible = false
		var aabb := _visible_aabb(m)
		var w := maxf(aabb.size.x, aabb.size.z)
		if w > 0.01:
			m.scale = Vector3.ONE * (wingspan / w)
		var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			var clip := ap.get_animation_list()[0]
			var a := ap.get_animation(clip)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(wingspan * 0.45, wingspan * 0.25, wingspan * 0.55)
	col.shape = box
	add_child(col)


func _physics_process(delta: float) -> void:
	if _dead:
		_vel.y -= 22.0 * delta
		global_position += _vel * delta
		rotate_object_local(Vector3.FORWARD, delta * 3.0)   # tumble
		if global_position.y < center.y - 40.0:
			queue_free()
		return

	_t += delta * ang_speed
	global_position = center + Vector3(cos(_t) * radius, altitude + sin(_t * 0.6) * 6.0, sin(_t) * radius)
	var ahead := center + Vector3(cos(_t + 0.06) * radius, altitude, sin(_t + 0.06) * radius)
	look_at(ahead, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, -0.3)   # bank into the turn

	_call_t -= delta
	if _call_t <= 0.0:
		_call_t = _rng.randf_range(6.0, 14.0)
		Sfx.play_at(call_sound, global_position, 0.7, 10.0)


func take_damage(amount: float, _from: Vector3 = global_position, _hit: Vector3 = Vector3.INF) -> String:
	if _dead:
		return ""
	hp -= amount
	if hp <= 0.0:
		_dead = true
		collision_layer = 0
		_vel = -global_transform.basis.z * 8.0
		GameState.collect_trophy(trophy_id, trophy_value, false)
		Sfx.play_at(call_sound, global_position, 0.5, 10.0)
	return "BODY"


func _visible_aabb(root: Node) -> AABB:
	var out := AABB()
	var started := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = mi.get_transform() * mi.mesh.get_aabb()
		out = out.merge(b) if started else b
		started = true
	return out
