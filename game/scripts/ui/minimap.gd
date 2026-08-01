extends Control
## Motion-tracker radar (top-right). Only visible when the Motion Tracker field
## gear is equipped — that's what makes that gear real (and worth its score cost).
## Wildlife pings are colour-coded and oriented to the way the player faces.

const RANGE := 70.0     # metres shown
const R := 84.0         # radar pixel radius

const PREY := Color(0.55, 0.82, 0.45)
const THREAT := Color(0.92, 0.72, 0.28)
const PRED := Color(0.9, 0.32, 0.26)


func _ready() -> void:
	custom_minimum_size = Vector2(R * 2.0, R * 2.0)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(-R * 2.0 - 18.0, 18.0)


func _process(_delta: float) -> void:
	visible = GameState.gear.get("tracker", false)
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(R, R)
	draw_circle(c, R, Color(0.04, 0.07, 0.05, 0.55))
	draw_arc(c, R, 0.0, TAU, 56, Color(0.4, 0.62, 0.4, 0.7), 2.0)
	draw_arc(c, R * 0.5, 0.0, TAU, 40, Color(0.4, 0.62, 0.4, 0.25), 1.0)
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(0.4, 0.62, 0.4, 0.2), 1.0)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(0.4, 0.62, 0.4, 0.2), 1.0)
	# Player marker (always facing up).
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(-4, 4), c + Vector2(4, 4)]), Color(0.9, 0.92, 0.88))

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var head := player.get_node_or_null("Head")
	var yaw: float = head.rotation.y if head else 0.0
	var pp: Vector3 = player.global_position
	for w in get_tree().get_nodes_in_group("wildlife"):
		if not is_instance_valid(w) or w.get("data") == null:
			continue
		var rel: Vector3 = w.global_position - pp
		var d := Vector2(rel.x, rel.z).length()
		if d > RANGE:
			continue
		var ang := atan2(rel.x, -rel.z) - yaw          # bearing relative to facing
		var rr := d / RANGE * R
		var p := c + Vector2(sin(ang), -cos(ang)) * rr
		draw_circle(p, 3.5, _class_color(w))


func _class_color(w: Object) -> Color:
	var data = w.get("data")
	if data == null:
		return THREAT
	if data.diet == CreatureData.Diet.HERBIVORE:
		return PREY
	if data.is_apex:
		return PRED
	return PRED if data.is_aggressive else THREAT
