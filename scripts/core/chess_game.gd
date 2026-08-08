extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)

@onready var model: ChessBoardModel = $ChessModel
@export_enum("white", "black") var player_color: String = "white"

@onready var result_panel: Control = $CanvasLayer/ResultOverlay
@onready var result_label: Label = $CanvasLayer/ResultOverlay/ResultPanel/ContentMargin/ResultLabel

func _ready() -> void:
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)

	if result_panel != null:
		result_panel.hide()

func _on_battle_finished(winner_color: String) -> void:
	var player_result: String

	if winner_color == "draw":
		player_result = "draw"
	elif winner_color == player_color:
		player_result = "win"
	else:
		player_result = "loss"

	show_battle_result(winner_color)
	battle_completed.emit(player_result)

func show_battle_result(winner_color: String) -> void:
	if result_panel == null or result_label == null:
		printerr("ChessGame result UI is not fully assigned.")
		return

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

	var display_panel := result_panel.get_node_or_null("ResultPanel") as Control
	result_panel.modulate.a = 0.0
	result_panel.show()

	if display_panel != null:
		display_panel.scale = Vector2(0.82, 0.82)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(result_panel, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if display_panel != null:
		tween.tween_property(display_panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func restart_battle() -> void:
	get_tree().reload_current_scene()
