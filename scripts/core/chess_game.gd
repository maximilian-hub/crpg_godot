extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)

@export var model: ChessBoardModel
@export_enum("white", "black") var player_color: String = "white"

# Optional for now. Assign these in the Inspector when you add a result UI.
@export var result_panel: Control
@export var result_label: Label

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

	if result_label != null:
		match player_result:
			"win":
				result_label.text = "Victory!"
			"loss":
				result_label.text = "Defeat..."
			"draw":
				result_label.text = "Draw"

	if result_panel != null:
		result_panel.show()

	battle_completed.emit(player_result)

func restart_battle() -> void:
	get_tree().reload_current_scene()
