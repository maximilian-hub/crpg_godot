extends Control
class_name BattleResultView

signal result_confirmed

@onready var result_label: Label = $ResultPanel/ContentMargin/ResultLabel
var can_confirm: bool = false

func _ready() -> void:
	set_process_unhandled_input(true)

func show_battle_result(winner_color: String) -> void:
	can_confirm = true
	match winner_color:
		"white":
			result_label.text = "White Wins"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.82))
		"black":
			result_label.text = "Black Wins"
			result_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.92))
		"draw":
			result_label.text = "Draw"
			result_label.add_theme_color_override("font_color", Color(0.88, 0.86, 0.82))
		_:
			result_label.text = "Battle Complete"

	var display_panel := get_node_or_null("ResultPanel") as Control
	modulate.a = 0.0
	show()
	if display_panel != null:
		display_panel.scale = Vector2(0.82, 0.82)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if display_panel != null:
		tween.tween_property(display_panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func reset_result() -> void:
	can_confirm = false
	hide()
	modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not can_confirm:
		return
	if event.is_action_pressed("interact"):
		can_confirm = false
		get_viewport().set_input_as_handled()
		result_confirmed.emit()
