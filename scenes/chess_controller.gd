extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI
var selected_piece: ModelPiece = null
var legal_moves: Array = []

func _ready():
	pass
	
func _on_square_clicked(coord: Vector2i):
	var piece_at_square = model.board[coord.x][coord.y]
	
	# If there is no currently selected piece:
	if selected_piece == null:
		# and a piece at the clicked square:
		if piece_at_square != null:
			piece_at_square.print_piece()
			# and it's that piece's team's turn:
			if piece_at_square.color == model.current_turn:
				select_piece(piece_at_square)
	else:
	# If there is a selected piece:
		if coord in legal_moves:
			model.move_piece(selected_piece, coord)
			selected_piece.has_moved = true
		deselect_piece()
		
func get_piece_at(coord: Vector2i) -> Node:
	for piece in view.get_node("Pieces").get_children():
		if piece.coordinate == coord:
			return piece
	return null

func select_piece(piece: ModelPiece):
	selected_piece = piece
	legal_moves = model.get_legal_moves(selected_piece)
	print(selected_piece)
	view.clear_highlights()
	view.show_legal_moves(legal_moves)

func deselect_piece():
		view.clear_highlights()
		selected_piece = null
		legal_moves.clear()

	
