extends Resource
class_name WeaponData
## Data-driven weapon definition. New guns = new .tres files (North Star:
## content by data). Hitscan for now; `pellets`/`projectile_scene` leave room for
## shotguns and thrown/launched ammo later.

enum FireMode { SEMI, AUTO }

@export_group("Identity")
@export var weapon_id: StringName = &"unknown"
@export var display_name: String = "Unknown Weapon"

@export_group("Ballistics")
@export var damage: float = 34.0
@export var range: float = 300.0
## Shots per minute. Fire cadence = 60 / rounds_per_minute.
@export var rounds_per_minute: float = 60.0
@export var fire_mode: FireMode = FireMode.SEMI
## Pellets per shot (1 = rifle/pistol; >1 = shotgun spread later).
@export var pellets: int = 1

@export_group("Ammo")
@export var mag_size: int = 30
@export var reserve_ammo: int = 120
@export var reload_time: float = 2.2

@export_group("Recoil / Accuracy")
## Upward camera kick per shot, radians.
@export var recoil_pitch: float = 0.02
## Random horizontal kick per shot, radians.
@export var recoil_yaw: float = 0.008
## How fast the camera recovers toward center (higher = snappier).
@export var recoil_recovery: float = 8.0
## Base aim spread (radians) hip-fired; grows with sustained fire.
@export var spread_base: float = 0.006
@export var spread_per_shot: float = 0.004
@export var spread_max: float = 0.06
## Aiming-down-sights tightens spread and reduces kick by this factor.
@export var ads_factor: float = 0.35

@export_group("Viewmodel")
## Drop in a real .gltf/.glb weapon here and it's used instead of the procedural
## mesh. A child node named "Muzzle" (optional) marks the barrel tip.
@export var model_scene: PackedScene
## Per-model tuning knobs (asset scales/pivots vary) — nudge until it sits right.
@export var model_scale: float = 1.0
@export var model_offset: Vector3 = Vector3.ZERO
@export var model_rotation: Vector3 = Vector3.ZERO   # degrees
## Procedural fallback silhouette when no model_scene is set.
@export_enum("RIFLE", "PISTOL") var body_style: String = "RIFLE"
@export var tint: Color = Color(0.12, 0.12, 0.13)
