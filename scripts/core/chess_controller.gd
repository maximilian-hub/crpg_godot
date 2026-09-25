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
var skitter_intermediate := Vector2i(-1, -1)
var skitter_destinations: Array[Vector2i] = []
var is_input_locked: bool = false
var active_ability_selected: bool = false
var non_move_selection_mode: bool = false
var player_controlled_colors: Array[String] = ["white", "black"]

signal selection_piece_processing(piece: ModelPiece)
signal selection_piece_processed()
signal ability_targeting_started(king: KingPiece, ability_name: String, targets: Array)
signal ability_targeting_preparing(king: KingPiece, ability_name: String, targets: Array, completion: CompletionGate)
signal ability_targeting_ended(king: KingPiece, ability_name: String, reason: String)
signal selection_targets_changed(targets: Array)
signal selection_cleared()
signal piece_selected(piece: ModelPiece)
signal ordinary_move_submission_started(piece: ModelPiece, target: Vector2i)
signal ordinary_move_submission_finished(piece: ModelPiece, target: Vector2i, accepted: bool)

func _ready():
	model.action_started.connect(_on_action_started)
	model.action_finished.connect(_on_action_finished)
	model.action_cancelled.connect(_on_action_cancelled)
	model.forced_pass_sequence_started.connect(_on_forced_pass_sequence_started)
	model.forced_pass_sequence_finished.connect(_on_forced_pass_sequence_finished)
	model.battle_finished.connect(_on_battle_finished)
	model.board_rebuilt.connect(_on_board_rebuilt)
	model.reaction_selection_requested.connect(_on_reaction_selection_requested)
	model.reaction_selection_committed.connect(_on_reaction_selection_committed)

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
	if skitter_intermediate != Vector2i(-1, -1):
		await _handle_skitter_destination_click(coord)
		return

	if selected_piece == null:
		if piece and piece.color == model.current_turn and is_player_controlled(piece.color):
			select_piece(piece)
		return

	if piece == selected_piece and piece is KingPiece and piece.is_active_ability_ready() and piece.has_active_ability():
		await select_active_ability(piece.color)
		return

	if coord in legal_moves:
		if temp_selected_piece is ArakneKing and piece == null:
			var arakne := temp_selected_piece as ArakneKing
			if arakne.can_begin_skitter(coord):
				var destinations := arakne.get_skitter_destinations(coord)
				if not destinations.is_empty():
					skitter_intermediate = coord
					skitter_destinations.assign(destinations)
					# The chosen first step remains a valid "stop here" target during
					# Skitter staging, so keep it visible beside the second-step options.
					legal_moves.assign([coord])
					legal_moves.append_array(destinations)
					selection_targets_changed.emit(legal_moves)
					return
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
		_clear_skitter_selection()
		selected_piece = piece
		legal_moves = _get_primary_targets(ChessPrimaryAction.Kind.MOVE, selected_piece)
		selection_targets_changed.emit(legal_moves)
		piece_selected.emit(piece)

func deselect_piece():
	selection_cleared.emit()
	selected_piece = null
	legal_moves.clear()
	_clear_skitter_selection()


func _handle_skitter_destination_click(coord: Vector2i) -> void:
	var arakne := selected_piece as ArakneKing
	if not is_instance_valid(arakne):
		deselect_piece()
		return
	var intermediate := skitter_intermediate
	if coord != intermediate and coord not in skitter_destinations:
		deselect_piece()
		return
	var final_target := coord
	deselect_piece()
	ordinary_move_submission_started.emit(arakne, final_target)
	var accepted: bool
	if final_target == intermediate:
		accepted = await model.submit_move(arakne, intermediate)
	else:
		var path: Array[Vector2i] = [intermediate, final_target]
		accepted = await model.submit_move_path(arakne, path)
	ordinary_move_submission_finished.emit(arakne, final_target, accepted)


func _clear_skitter_selection() -> void:
	skitter_intermediate = Vector2i(-1, -1)
	skitter_destinations.clear()

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
		await select_active_ability("white")

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
		await select_active_ability("black")

func select_active_ability(color: String):
	deselect_piece()
	active_king = model.get_king(color)

	if active_king == null:
		printerr("Could not find king for color: ", color)
		return
	if active_king.stunned:
		active_king = null
		return
	if not active_king.is_active_ability_ready():
		active_king = null
		return

	var preparing_king := active_king
	var preparing_targets := _get_primary_targets(ChessPrimaryAction.Kind.ACTIVE_ABILITY, preparing_king)
	is_input_locked = true
	var completion := CompletionGate.new()
	ability_targeting_preparing.emit(preparing_king, preparing_king.get_active_ability_name(), preparing_targets, completion)
	completion.close()
	await completion.wait_until_released()
	is_input_locked = model.action_in_progress or model.battle_over
	if model.battle_over or not is_instance_valid(preparing_king) or preparing_king != active_king:
		if is_instance_valid(preparing_king):
			ability_targeting_ended.emit(preparing_king, preparing_king.get_active_ability_name(), "interrupted")
		return
	active_ability_selected = true
	legal_moves = preparing_targets
	ability_targeting_started.emit(active_king, active_king.get_active_ability_name(), legal_moves)

func configure_player_controlled_colors(colors: Array[String]) -> void:
	player_controlled_colors = colors.duplicate()
	if selected_piece != null and not is_player_controlled(selected_piece.color):
		deselect_piece()

func _on_board_rebuilt(_board: Array) -> void:
	selected_piece = null
	active_king = null
	active_piece = null
	last_active_piece = null
	legal_moves.clear()
	_clear_skitter_selection()
	active_ability_selected = false
	non_move_selection_mode = false
	is_input_locked = model.battle_over
	selection_cleared.emit()

func is_player_controlled(color: String) -> bool:
	return color in player_controlled_colors

func _get_primary_targets(kind: ChessPrimaryAction.Kind, piece: ModelPiece) -> Array:
	if kind == ChessPrimaryAction.Kind.MOVE and piece is ArakneKing:
		return piece.get_legal_moves()
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


func _on_forced_pass_sequence_started() -> void:
	is_input_locked = true


func _on_forced_pass_sequence_finished() -> void:
	is_input_locked = model.battle_over

func _on_battle_finished(_winner_color: String) -> void:
	lock_after_battle()

func _on_reaction_selection_requested(calling_piece: ModelPiece, _action_type: String, targets: Array) -> void:
	if is_player_controlled(calling_piece.color):
		initiate_non_move_selection_mode(calling_piece, targets)

func _on_reaction_selection_committed(_calling_piece: ModelPiece, _action_type: String, _target: Vector2i) -> void:
	if non_move_selection_mode:
		end_non_move_selection_mode()
