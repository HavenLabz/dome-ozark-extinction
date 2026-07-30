extends CanvasLayer
## Survival HUD — bars for health, stamina, hunger, hydration.

@onready var health_bar: ProgressBar = $Root/VBox/HealthRow/Bar
@onready var stamina_bar: ProgressBar = $Root/VBox/StaminaRow/Bar
@onready var hunger_bar: ProgressBar = $Root/VBox/HungerRow/Bar
@onready var hydration_bar: ProgressBar = $Root/VBox/HydrationRow/Bar
@onready var hint_label: Label = $Root/Hint


func _ready() -> void:
	GameState.health_changed.connect(_on_health)
	GameState.stamina_changed.connect(_on_stamina)
	GameState.hunger_changed.connect(_on_hunger)
	GameState.hydration_changed.connect(_on_hydration)
	_on_health(GameState.health)
	_on_stamina(GameState.stamina)
	_on_hunger(GameState.hunger)
	_on_hydration(GameState.hydration)
	# Hide control hint after a few seconds
	await get_tree().create_timer(6.0).timeout
	if is_instance_valid(hint_label):
		hint_label.visible = false


func _on_health(v: float) -> void:
	health_bar.value = v


func _on_stamina(v: float) -> void:
	stamina_bar.value = v


func _on_hunger(v: float) -> void:
	hunger_bar.value = v


func _on_hydration(v: float) -> void:
	hydration_bar.value = v
