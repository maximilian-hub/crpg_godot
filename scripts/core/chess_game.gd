extends Node
class_name ChessGame

## Coordinates battle-level state without owning chess rules.
## The model reports a winning color; this node translates it into a
## player-facing win/loss/draw result for UI and future overworld flow.

signal battle_completed(player_result: String)
signal battle_exit_requested(player_result: String)
signal opening_completed()
signal white_activation_completed()

const OpeningDirector := preload("res://scripts/view/chess_battle_opening_director.gd")
const DEFAULT_PLAYER_PRESENTATION := preload("res://assets/player_army_presentation.tres")
const DEFAULT_OPPONENT_PRESENTATION := preload("res://assets/opponent_army_presentation.tres")

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
@export var player_hand_style: Resource
@export var opponent_hand_style: Resource
@export var player_presentation: Resource
@export var opponent_presentation: Resource
@export var play_opening_presentation := true
var completed_player_result: String = ""
var opening_director: ChessBattleOpeningDirector
var _white_turn_released := false
var _black_activation_barrier_started := false

var opening_in_progress: bool:
	get:
		return is_instance_valid(opening_director) and opening_director.is_running

var opening_pending: bool:
	get:
		return is_instance_valid(opening_director) and opening_director.is_pending

func _ready() -> void:
	player_color = _normalize_color(player_color)
	if player_presentation == null:
		player_presentation = DEFAULT_PLAYER_PRESENTATION
	if opponent_presentation == null:
		opponent_presentation = DEFAULT_OPPONENT_PRESENTATION
	var board_view := get_node_or_null("CanvasLayer/ChessBoard") as ChessBoardView
	_apply_army_presentations(board_view)
	var adapter := get_node_or_null("ChessPresentationAdapter") as ChessPresentationAdapter
	if adapter != null:
		adapter.configure_army_presentations(player_color, player_presentation, opponent_presentation)
	set_viewing_color(player_color)
	if model == null:
		printerr("ChessGame has no ChessBoardModel assigned.")
		return

	if not model.battle_finished.is_connected(_on_battle_finished):
		model.battle_finished.connect(_on_battle_finished)
	if not model.board_rebuilt.is_connected(_on_board_rebuilt):
		model.board_rebuilt.connect(_on_board_rebuilt)
	if not model.settled_action_completed.is_connected(_on_settled_action_completed):
		model.settled_action_completed.connect(_on_settled_action_completed)
	var result_view := get_node_or_null("CanvasLayer/ResultOverlay") as BattleResultView
	if result_view != null and not result_view.result_confirmed.is_connected(_on_result_confirmed):
		result_view.result_confirmed.connect(_on_result_confirmed)

	_configure_participants(false)
	controller.is_input_locked = play_opening_presentation
	if play_opening_presentation and board_view != null and adapter != null:
		opening_director = OpeningDirector.new()
		opening_director.name = "BattleOpeningDirector"
		add_child(opening_director)
		opening_director.configure(model, board_view, adapter, adapter.presentation_policy, player_color, player_presentation, opponent_presentation)
		await opening_director.play()
	controller.is_input_locked = model.battle_over
	_configure_participants(true)
	_white_turn_released = true
	if opening_director == null or not opening_director.is_pending:
		opening_completed.emit()
	else:
		white_activation_completed.emit()


func _configure_participants(enable_automatic_players: bool) -> void:
	match control_mode:
		ControlMode.CPU_VS_CPU:
			controller.configure_player_controlled_colors([])
			white_cpu_player.configure(enable_automatic_players, "white")
			black_cpu_player.configure(enable_automatic_players, "black")
		ControlMode.PLAYER_VS_CPU:
			var opponent_color := model.get_other_color(player_color)
			controller.configure_player_controlled_colors([player_color])
			white_cpu_player.configure(enable_automatic_players and opponent_color == "white", "white")
			black_cpu_player.configure(enable_automatic_players and opponent_color == "black", "black")
		ControlMode.PLAYER_VS_PLAYER:
			controller.configure_player_controlled_colors(["white", "black"])
			white_cpu_player.configure(false, "white")
			black_cpu_player.configure(false, "black")

func _on_battle_finished(winner_color: String) -> void:
	var player_result: String

	if winner_color == "draw":
		player_result = "draw"
	elif winner_color == player_color:
		player_result = "win"
	else:
		player_result = "loss"

	completed_player_result = player_result
	battle_completed.emit(player_result)

func _on_result_confirmed() -> void:
	if completed_player_result.is_empty():
		return
	battle_exit_requested.emit(completed_player_result)

func _on_board_rebuilt(_board: Array) -> void:
	if opening_pending:
		opening_director.cancel()
		if _white_turn_released:
			opening_completed.emit()
	if not model.battle_over:
		completed_player_result = ""
		return
	if model.battle_result == "draw":
		completed_player_result = "draw"
	elif model.battle_result == player_color:
		completed_player_result = "win"
	else:
		completed_player_result = "loss"


func _on_settled_action_completed() -> void:
	if (
		_black_activation_barrier_started
		or not _white_turn_released
		or not opening_pending
		or opening_director.stage != ChessBattleOpeningDirector.Stage.AWAITING_BLACK_ACTIVATION
		or (model.current_turn != "black" and not model.battle_over)
		or not model.is_settled()
	):
		return
	_black_activation_barrier_started = true
	controller.is_input_locked = true
	_configure_participants(false)
	if model.battle_over:
		opening_director.finish_immediately()
	else:
		await opening_director.play_black_activation()
	controller.is_input_locked = model.battle_over
	if not model.battle_over:
		_configure_participants(true)
	opening_completed.emit()

func restart_battle() -> void:
	get_tree().reload_current_scene()


## Changes presentation perspective only. Controller ownership, CPUs, turn state,
## and the authoritative position are intentionally unaffected.
func set_viewing_color(color: String) -> void:
	var normalized := _normalize_color(color)
	var board_view := get_node_or_null("CanvasLayer/ChessBoard") as ChessBoardView
	if board_view != null:
		board_view.set_viewing_color(normalized)
		_apply_army_presentations(board_view)
	var adapter := get_node_or_null("ChessPresentationAdapter") as ChessPresentationAdapter
	if adapter != null:
		adapter.refresh_magic_controllers()
	_layout_side_ui(normalized)


func _apply_army_presentations(board_view: ChessBoardView) -> void:
	if board_view == null:
		return
	var player_style: Resource = player_presentation.hand_style if player_presentation != null else player_hand_style
	var opponent_style: Resource = opponent_presentation.hand_style if opponent_presentation != null else opponent_hand_style
	if board_view.viewing_color == player_color:
		board_view.set_hand_styles(player_style, opponent_style)
	else:
		board_view.set_hand_styles(opponent_style, player_style)


func _layout_side_ui(viewing_color: String) -> void:
	var white_container := get_node_or_null("UI/WhitePlayerUIContainer") as MarginContainer
	var black_container := get_node_or_null("UI/BlackPlayerUIContainer") as MarginContainer
	if white_container == null or black_container == null:
		return
	_place_side_ui(white_container, viewing_color == "white")
	_place_side_ui(black_container, viewing_color == "black")


func _place_side_ui(container: MarginContainer, near_player: bool) -> void:
	container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if near_player else Control.PRESET_TOP_WIDE)
	container.offset_left = 0.0
	container.offset_right = 0.0
	container.offset_top = -125.0 if near_player else 0.0
	container.offset_bottom = 0.0 if near_player else 125.0
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		container.add_theme_constant_override(margin_name, 0)
	container.add_theme_constant_override("margin_left" if near_player else "margin_right", 50)
	container.add_theme_constant_override("margin_bottom" if near_player else "margin_top", 50)
	var button := container.get_child(0) as Control if container.get_child_count() > 0 else null
	if button != null:
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if near_player else Control.SIZE_SHRINK_END
		button.size_flags_vertical = Control.SIZE_SHRINK_END if near_player else Control.SIZE_SHRINK_BEGIN


func _normalize_color(color: String) -> String:
	return "black" if color == "black" else "white"
