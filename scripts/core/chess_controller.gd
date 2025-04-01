extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI
var selected_piece: ModelPiece = null
var active_king: MinotaurKing = null # the king whose ability has been selected. TODO need KingPiece class
var legal_moves: Array = []
var is_input_locked: bool = false
var active_ability_selected: bool = false


func _ready():
	pass
	
### Handles clicks on the board.
## Depending on the context, user is selecting a piece, deselecting,
## selecting a move, or selecting a target for an ability.
#func _on_square_clicked(coord: Vector2i):
	#if is_input_locked: return
	#var piece_at_square = model.board[coord.x][coord.y]
	#
	## If there is an ability selected:
	#if active_ability_selected:
		#if coord in legal_moves:
			#active_king.active_target_selected(coord)
		#deselect_active_ability()
	#
	## If there is no currently selected piece:
	#elif selected_piece == null:
		## and a piece at the clicked square:
		#if piece_at_square != null:
			## and it's that piece's team's turn:
			#if piece_at_square.color == model.current_turn:
				#select_piece(piece_at_square)
	#else:
	## If there is already a selected piece:
		#if coord in legal_moves:
			#model.move_piece(selected_piece, coord)
			#selected_piece.has_moved = true
			#deselect_piece()
		#else:
			#deselect_piece()
			#if piece_at_square and piece_at_square.color == model.current_turn:
				#select_piece(piece_at_square)
				
func _on_square_clicked(coord: Vector2i):
	if is_input_locked:
		return

	var piece = model.board[coord.x][coord.y]

	# Handle active ability target selection
	if active_ability_selected:
		if coord in legal_moves:
			active_king.active_target_selected(coord)
		deselect_active_ability()
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
	deselect_piece() 	# if a piece was selected, deselect it
	
	# TODO: flash the screen or whatever
	# TODO: apply aura
	
	active_ability_selected = true
	active_king = model.get_king(color)
	legal_moves = active_king.get_charge_moves()
	view.show_legal_moves(legal_moves)
	
	#view.active_ability_selected(color)
	pass
	
func deselect_active_ability():
	# TODO: remove aura
	# TODO: power down sound
	if active_ability_selected:
		active_king = null
		active_ability_selected = false
		legal_moves = []
		view.clear_highlights()
