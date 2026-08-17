extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)
signal battle_exit_requested(player_result: String)

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
var completed_player_result: String = ""
@onready var background: TextureRect = $Background

func _ready() -> void:
	get_viewport().size_changed.connect(_layout_background)
	_layout_background()
	var board_view := get_node_or_null("CanvasLayer/ChessBoard") as ChessBoardView
	if board_view != null:
		board_view.set_viewing_color(player_color)
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)
	var result_view := get_node_or_null("CanvasLayer/ResultOverlay") as BattleResultView
	if result_view != null and not result_view.result_confirmed.is_connected(_on_result_confirmed):
		result_view.result_confirmed.connect(_on_result_confirmed)

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

func _layout_background() -> void:
	# Preserve the authored 5x wood grain while covering the complete viewport.
	var background_scale := maxf(background.scale.x, 0.001)
	background.position = Vector2.ZERO
	background.size = get_viewport().get_visible_rect().size / background_scale


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

	completed_player_result = player_result
	battle_completed.emit(player_result)

func _on_result_confirmed() -> void:
	if completed_player_result.is_empty():
		return
	battle_exit_requested.emit(completed_player_result)

func restart_battle() -> void:
	get_tree().reload_current_scene()
