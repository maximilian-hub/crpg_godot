extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI
var selected_piece: Node = null
var legal_moves: Array = []

func _ready():
	pass
	
func _on_square_clicked(coord: Vector2i):
	var piece_at_square = get_piece_at(coord)
	
	# If there is no currently selected piece.
	if selected_piece == null:
		# and a piece at the clicked square:
		if piece_at_square != null:
			select_piece(piece_at_square)
	else:
		if coord in legal_moves:
			model.move_piece(selected_piece.coordinate, coord)
			selected_piece.hasMoved = true
		deselect_piece()
		
		
func get_piece_at(coord: Vector2i) -> Node:
	for piece in view.get_node("Pieces").get_children():
		if piece.coordinate == coord:
			return piece
	return null

func select_piece(piece: Node):
	selected_piece = piece
	legal_moves = model.get_legal_moves(selected_piece)
	view.clear_highlights()
	view.show_legal_moves(legal_moves)

func deselect_piece():
		view.clear_highlights()
		selected_piece = null
		legal_moves.clear()
		
	
