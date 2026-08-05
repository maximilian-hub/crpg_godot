#~~~~~~~~NEW FILE: chess_controller.gd~~~~~~~~~~~~
extends Node
class_name ChessBoardController

# This node serves as the Controller component.
# It translates clicks into player choices; the Model owns action/turn resolution.

@export var model: ChessBoardModel
@export var view: ChessBoardView
var selected_piece: ModelPiece = null
var active_king: KingPiece = null
var active_piece: ModelPiece = null
var last_active_piece: ModelPiece = null
var legal_moves: Array = []
var is_input_locked: bool = false
var active_ability_selected: bool = false
var non_move_selection_mode: bool = false

signal selection_piece_processing(piece: ModelPiece)
signal selection_piece_processed()

func _ready():
	pass

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
		if piece and piece.color == model.current_turn:
			select_piece(piece)
		return

	if coord in legal_moves:
		deselect_piece()
		await model.move_piece(temp_selected_piece, coord)
		return

	# Fallback: deselect and possibly select a different friendly piece.
	deselect_piece()
	if piece and piece.color == model.current_turn:
		select_piece(piece)

func _handle_non_move_selection_mode_click(coord: Vector2i):
	if coord not in legal_moves:
		return

	var reacting_piece := active_piece
	model.resolve_reaction_selection(reacting_piece, coord)

func _handle_active_ability_selected_click(coord: Vector2i):
	if coord in legal_moves:
		var acting_king := active_king
		deselect_active_ability(false)
		await model.perform_active_ability(acting_king, coord)
	else:
		# Clicked outside valid targets: cancel ability selection.
		deselect_active_ability(true)

func get_piece_at(coord: Vector2i) -> Node:
	for piece in view.get_node("Pieces").get_children():
		if piece.coordinate == coord:
			return piece
	return null

func select_piece(piece: ModelPiece):
	if piece.stunned == false:
		selected_piece = piece
		legal_moves = model.get_legal_moves(selected_piece)
		view.clear_highlights()
		view.show_legal_moves(legal_moves)

func deselect_piece():
	view.clear_highlights()
	selected_piece = null
	legal_moves.clear()

func _on_white_active_button_pressed() -> void:
	if model.battle_over:
		return
	if is_input_locked:
		return
	if model.current_turn == "black":
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
	legal_moves = active_king.get_active_ability_targets()
	view.show_legal_moves(legal_moves)
	view.flash_screen()
	active_king._on_active_selected()

func deselect_active_ability(play_powerdown_sound: bool):
	if active_ability_selected and active_king != null:
		if active_king.view_node:
			active_king._on_active_deselected(play_powerdown_sound)
		else:
			printerr("Cannot fade aura, active_king has no view_node.")
		view.clear_highlights()

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
	view.clear_highlights()
	view.highlight_squares(legal_moves)

func end_non_move_selection_mode():
	non_move_selection_mode = false
	active_piece = null
	last_active_piece = null
	selection_piece_processed.emit()
	view.clear_highlights()

## Permanently disables battle interactions after the Model declares a result.
func lock_after_battle() -> void:
	is_input_locked = true
	selected_piece = null
	legal_moves.clear()

	if active_ability_selected and is_instance_valid(active_king):
		if active_king.has_method("_on_active_deselected"):
			active_king._on_active_deselected(false)

	active_king = null
	active_ability_selected = false

	if non_move_selection_mode:
		end_non_move_selection_mode()
	else:
		active_piece = null
		last_active_piece = null
		view.clear_highlights()
