extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)

@onready var model: ChessBoardModel = $ChessModel
@export_enum("white", "black") var player_color: String = "white"

func _ready() -> void:
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)


func _on_battle_finished(winner_color: String) -> void:
	var player_result: String

	if winner_color == "draw":
		player_result = "draw"
	elif winner_color == player_color:
		player_result = "win"
	else:
		player_result = "loss"

	battle_completed.emit(player_result)

func restart_battle() -> void:
	get_tree().reload_current_scene()
