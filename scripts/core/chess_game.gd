extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)

enum ControlMode {
	CPU_VS_CPU,
	PLAYER_VS_CPU,
	PLAYER_VS_PLAYER,
}

@onready var model: ChessBoardModel = $ChessModel
@onready var controller: ChessBoardController = $ChessController
@onready var white_cpu_player: ChessCpuPlayer = $WhiteCpuPlayer
@onready var black_cpu_player: ChessCpuPlayer = $BlackCpuPlayer
@export_enum("white", "black") var player_color: String = "white"
@export var control_mode: ControlMode = ControlMode.CPU_VS_CPU
@export_enum("white", "black") var ai_color: String = "black"

func _ready() -> void:
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)

	match control_mode:
		ControlMode.CPU_VS_CPU:
			controller.configure_player_controlled_colors([])
			white_cpu_player.configure(true, "white")
			black_cpu_player.configure(true, "black")
		ControlMode.PLAYER_VS_CPU:
			controller.configure_player_controlled_colors([model.get_other_color(ai_color)])
			white_cpu_player.configure(ai_color == "white", "white")
			black_cpu_player.configure(ai_color == "black", "black")
		ControlMode.PLAYER_VS_PLAYER:
			controller.configure_player_controlled_colors(["white", "black"])
			white_cpu_player.configure(false, "white")
			black_cpu_player.configure(false, "black")


func _on_battle_finished(winner_color: String) -> void:
	var player_result: String
	var result_player_color := (
		model.get_other_color(ai_color)
		if control_mode == ControlMode.PLAYER_VS_CPU
		else player_color
	)

	if winner_color == "draw":
		player_result = "draw"
	elif winner_color == result_player_color:
		player_result = "win"
	else:
		player_result = "loss"

	battle_completed.emit(player_result)

func restart_battle() -> void:
	get_tree().reload_current_scene()
