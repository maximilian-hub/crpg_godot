#~~~~~~~~NEW FILE: chess_controller.gd~~~~~~~~~~~~
extends Node

# This node serves as the Controller component.
# Mostly handles user input.

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI
var selected_piece: ModelPiece = null
var active_king: KingPiece = null # the king whose ability has been selected. TODO need KingPiece class
var legal_moves: Array = []
var is_input_locked: bool = false
var active_ability_selected: bool = false

func _ready():
	pass
		
func _on_square_clicked(coord: Vector2i):
	if is_input_locked:
		return

	var piece = model.board[coord.x][coord.y]
	
	# Handle active ability target selection
	if active_ability_selected:
		if active_king == null: # Safety check
			printerr("Active ability selected, but active_king is null!")
			deselect_active_ability(true)
			return

		if coord in legal_moves:
			active_king.active_target_selected(coord) 
			deselect_active_ability(false) # Don't play powerdown sound if ability used
		else:
			# Clicked outside valid targets, cancel ability selection
			deselect_active_ability(true) # Play powerdown sound for cancellation
		return 

	# If no piece is currently selected
	if selected_piece == null:
		if piece and piece.color == model.current_turn:
			select_piece(piece)
		return

	# If clicking a legal move destination
	if coord in legal_moves:
		model.move_piece(selected_piece, coord)
		deselect_piece()
		return

	# Fallback: deselect and possibly select new piece
	deselect_piece()
	if piece and piece.color == model.current_turn:
		select_piece(piece)

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
	else:
		# TODO: little nono sound
		pass

func deselect_piece():
		view.clear_highlights()
		selected_piece = null
		legal_moves.clear()

func _on_white_active_button_pressed() -> void:
	if model.current_turn == "black":
		return
	else:
		select_active_ability("white")

func _on_black_active_button_pressed() -> void:
	if model.current_turn == "white":
		return
	else:
		select_active_ability("black")

func select_active_ability(color: String):
	deselect_piece()

	active_king = model.get_king(color) # Returns a KingPiece or subclass

	# Add check if King was found
	if active_king == null:
		printerr("Could not find king for color: ", color)
		return # Don't proceed

	# Check if King or ability is usable
	if active_king.stunned:
		active_king = null # Don't keep reference if stunned
		return
	if active_king.current_cooldown > 0:
		active_king = null # Don't keep reference if on cooldown
		return

	active_ability_selected = true
	# Assuming view_node is correctly assigned in ModelPiece/KingPiece
	if active_king.view_node:
		view.spawn_ss_aura(active_king.view_node) # Apply visual effect
	else:
		printerr("Active king has no view_node assigned!")

	# Use the generic method name now
	legal_moves = active_king.get_active_ability_targets() # <-- Use generic method
	view.show_legal_moves(legal_moves)
	view.flash_screen()

func deselect_active_ability(play_powerdown_sound: bool):
	if active_ability_selected and active_king != null: # Check active_king exists
		if active_king.view_node: # Check view_node exists
			view.fade_out_ss_aura(active_king.view_node, play_powerdown_sound)
		else:
			printerr("Cannot fade aura, active_king has no view_node.")
		view.clear_highlights()

	# Always clear state regardless of view_node status
	active_king = null
	active_ability_selected = false
	legal_moves.clear()
