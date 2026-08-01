extends Area3D
class_name WaterSource
## A drinkable water spot. Look at it and press Interact to restore hydration.
## Small but real — no "coming soon" placeholders (North Star Hard Rule #2).

func interact() -> void:
	GameState.hydration = 100.0


func get_prompt_text() -> String:
	return "Drink  [E]"
