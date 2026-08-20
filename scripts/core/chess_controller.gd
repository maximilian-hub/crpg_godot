#~~~~~~~~NEW FILE: chess_controller.gd~~~~~~~~~~~~
extends Node
class_name ChessBoardController

# This node serves as the Controller component.
# It translates clicks into player choices; the Model owns action/turn resolution.

@export var model: ChessBoardModel
var selected_piece: ModelPiece = null
var active_king: KingPiece = null
var active_piece: ModelPiece = null
var last_active_piece: ModelPiece = null
var legal_moves: Array = []
var is_input_locked: bool = false
var active_ability_selected: bool = false
var non_move_selection_mode: bool = false
var player_controlled_colors: Array[String] = ["white", "black"]

signal selection_piece_processing(piece: ModelPiece)
signal selection_piece_processed()
signal ability_targeting_started(king: KingPiece, ability_name: String, targets: Array)
signal ability_targeting_ended(king: KingPiece, ability_name: String, reason: String)
signal selection_targets_changed(targets: Array)
signal selection_cleared()
signal ordinary_move_submission_started(piece: ModelPiece, target: Vector2i)
signal ordinary_move_submission_finished(piece: ModelPiece, target: Vector2i, accepted: bool)

func _ready():
	model.action_started.connect(_on_action_started)
	model.action_finished.connect(_on_action_finished)
	model.action_cancelled.connect(_on_action_cancelled)
	model.battle_finished.connect(_on_battle_finished)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.reaction_selection_resolved.connect(_on_reaction_selection_resolved)

func _on_square_clicked(coord: Vector2i):
	if model.battle_over:
		return

	# Reaction selections are the only clicks allowed while an action is resolving.
	if non_move_selection_mode:
		_handle_non_move_selection_mode_click(coord)
		return
	if is_input_locked:
		return

	var temp_selected_piece := selected_piece
	var piece: ModelPiece = model.board[coord.x][coord.y]
	if piece:
		piece.print_piece()

	if active_ability_selected:
		await _handle_active_ability_selected_click(coord)
		return

	if selected_piece == null:
		if piece and piece.color == model.current_turn and is_player_controlled(piece.color):
			select_piece(piece)
		return

	if coord in legal_moves:
		deselect_piece()
		ordinary_move_submission_started.emit(temp_selected_piece, coord)
		var accepted := await model.submit_move(temp_selected_piece, coord)
		ordinary_move_submission_finished.emit(temp_selected_piece, coord, accepted)
		return

	# Fallback: deselect and possibly select a different friendly piece.
	deselect_piece()
	if piece and piece.color == model.current_turn and is_player_controlled(piece.color):
		select_piece(piece)

func _handle_non_move_selection_mode_click(coord: Vector2i):
	if coord not in legal_moves:
		return

	await model.submit_reaction_selection(coord)

func _handle_active_ability_selected_click(coord: Vector2i):
	if coord in legal_moves:
		var acting_king := active_king
		deselect_active_ability(false)
		await model.submit_active_ability(acting_king, coord)
	else:
		# Clicked outside valid targets: cancel ability selection.
		deselect_active_ability(true)

func select_piece(piece: ModelPiece):
	if piece.stunned == false and is_player_controlled(piece.color):
		selected_piece = piece
		legal_moves = _get_primary_targets(ChessPrimaryAction.Kind.MOVE, selected_piece)
		selection_targets_changed.emit(legal_moves)

func deselect_piece():
	selection_cleared.emit()
	selected_piece = null
	legal_moves.clear()

func _on_white_active_button_pressed() -> void:
	if model.battle_over:
		return
	if is_input_locked:
		return
	if model.current_turn == "black":
		return
	if not is_player_controlled("white"):
		return
	if non_move_selection_mode:
		return
	if active_ability_selected:
		deselect_active_ability(true)
	else:
		select_active_ability("white")

func _on_black_active_button_pressed() -> void:
	if model.battle_over:
		return
	if is_input_locked:
		return
	if model.current_turn == "white":
		return
	if not is_player_controlled("black"):
		return
	if non_move_selection_mode:
		return
	if active_ability_selected:
		deselect_active_ability(true)
	else:
		select_active_ability("black")

func select_active_ability(color: String):
	deselect_piece()
	active_king = model.get_king(color)

	if active_king == null:
		printerr("Could not find king for color: ", color)
		return
	if active_king.stunned:
		active_king = null
		return
	if active_king.current_cooldown > 0:
		active_king = null
		return

	active_ability_selected = true
	legal_moves = _get_primary_targets(ChessPrimaryAction.Kind.ACTIVE_ABILITY, active_king)
	ability_targeting_started.emit(active_king, active_king.get_active_ability_name(), legal_moves)

func configure_player_controlled_colors(colors: Array[String]) -> void:
	player_controlled_colors = colors.duplicate()
	if selected_piece != null and not is_player_controlled(selected_piece.color):
		deselect_piece()

func is_player_controlled(color: String) -> bool:
	return color in player_controlled_colors

func _get_primary_targets(kind: ChessPrimaryAction.Kind, piece: ModelPiece) -> Array:
	var targets: Array = []
	for action in model.get_legal_primary_actions(model.current_turn):
		if action.kind == kind and action.piece == piece:
			targets.append(action.target)
	return targets

func deselect_active_ability(play_powerdown_sound: bool):
	if active_ability_selected and active_king != null:
		var reason := "cancelled" if play_powerdown_sound else "confirmed"
		ability_targeting_ended.emit(active_king, active_king.get_active_ability_name(), reason)

	active_king = null
	active_ability_selected = false
	legal_moves.clear()

## Called by the Model when a queued reaction requires a square choice.
func initiate_non_move_selection_mode(calling_piece: ModelPiece, _legal_moves: Array):
	non_move_selection_mode = true
	if active_piece:
		last_active_piece = active_piece
	active_piece = calling_piece
	if active_piece != last_active_piece:
		selection_piece_processing.emit(calling_piece)
	legal_moves = _legal_moves
	selection_targets_changed.emit(legal_moves)

func end_non_move_selection_mode():
	non_move_selection_mode = false
	active_piece = null
	last_active_piece = null
	selection_piece_processed.emit()
	selection_cleared.emit()

## Permanently disables battle interactions after the Model declares a result.
func lock_after_battle() -> void:
	is_input_locked = true
	selected_piece = null
	legal_moves.clear()

	if active_ability_selected and is_instance_valid(active_king):
		ability_targeting_ended.emit(active_king, active_king.get_active_ability_name(), "battle_finished")

	active_king = null
	active_ability_selected = false

	if non_move_selection_mode:
		end_non_move_selection_mode()
	else:
		active_piece = null
		last_active_piece = null
		selection_cleared.emit()

func _on_action_started(_owner_color: String) -> void:
	is_input_locked = true

func _on_action_finished() -> void:
	is_input_locked = false

func _on_action_cancelled() -> void:
	is_input_locked = false

func _on_battle_finished(_winner_color: String) -> void:
	lock_after_battle()

func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, targets: Array) -> void:
	if is_player_controlled(calling_piece.color):
		initiate_non_move_selection_mode(calling_piece, targets)

func _on_reaction_selection_resolved(_calling_piece: ModelPiece, _action_type: String, _target: Vector2i) -> void:
	if non_move_selection_mode:
		end_non_move_selection_mode()
