extends Area3D
class_name WeaponPickup
## A weapon dropped by a fallen soldier or stocked at an outpost. Interact to add
## it to your loadout (or top up ammo if you already carry it). Layer 16 so the
## player's interaction ray sees it, same as trophies/caches.

var weapon_path: String = ""
var _taken: bool = false


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0


func interact() -> void:
	if _taken:
		return
	var d := load(weapon_path) as WeaponData
	var pl := get_tree().get_first_node_in_group("player")
	if d == null or pl == null:
		return
	if pl.has_method("add_weapon") and pl.add_weapon(d):
		_taken = true
		Sfx.play("chime", 0.9, -4.0)
		queue_free()
	elif pl.has_method("get_active_weapon"):
		# Already carried — salvage it for ammo instead.
		var w = pl.get_active_weapon()
		if w and w.has_method("resupply"):
			w.resupply()
		_taken = true
		Sfx.play("reload", 1.0, -8.0)
		queue_free()


func get_prompt_text() -> String:
	var d := load(weapon_path) as WeaponData
	return "Take %s  [E]" % (d.display_name if d else "weapon")
