extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)

@onready var model: ChessBoardModel = $ChessModel
@onready var controller: ChessBoardController = $ChessController
@onready var cpu_player: ChessCpuPlayer = $ChessCpuPlayer
@export_enum("white", "black") var player_color: String = "white"
@export var is_ai_game: bool = false # For prototype/debugging, to select 1 or 2 player game
@export_enum("white", "black") var ai_color: String = "black"

func _ready() -> void:
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)

	if is_ai_game:
		controller.configure_player_controlled_colors([model.get_other_color(ai_color)])
	else:
		controller.configure_player_controlled_colors(["white", "black"])
	cpu_player.configure(is_ai_game, ai_color)


func _on_battle_finished(winner_color: String) -> void:
	var player_result: String
	var result_player_color := model.get_other_color(ai_color) if is_ai_game else player_color

	if winner_color == "draw":
		player_result = "draw"
	elif winner_color == result_player_color:
		player_result = "win"
	else:
		player_result = "loss"

	battle_completed.emit(player_result)

func restart_battle() -> void:
	get_tree().reload_current_scene()
