extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI
var selected_piece: Node = null
var legal_moves: Array = []


func _ready():
	pass
	
#func _on_piece_clicked(clicked_piece: Node):
	## If no piece selected, select this one
	#if selected_piece == null:
		#selected_piece = clicked_piece
		#legal_moves = model.get_legal_moves(clicked_piece)
		#view.clear_highlights()
		#view.show_legal_moves(legal_moves)
		#return
	#
	## If we clicked the same piece again — deselect
	#if clicked_piece == selected_piece:
		#selected_piece = null
		#legal_moves.clear()
		#view.clear_highlights()
		#return
	#
	## 👀 If a piece is already selected, and the clicked one is ON a valid move square
	#if clicked_piece.coordinate in legal_moves:
		#model.move_piece(selected_piece.coordinate, clicked_piece.coordinate)
		#selected_piece = null
		#legal_moves.clear()
		#view.clear_highlights()
		#return
	#
	## ❌ Otherwise, treat it as a misclick or a new selection
	#selected_piece = null
	#legal_moves.clear()
	#view.clear_highlights()


func _on_square_clicked(coord: Vector2i):
	var piece_at_square = get_piece_at(coord)

	if selected_piece == null:
		if piece_at_square != null:
			selected_piece = piece_at_square
			legal_moves = model.get_legal_moves(selected_piece)
			view.clear_highlights()
			view.show_legal_moves(legal_moves)
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



func deselect_piece():
		view.clear_highlights()
		selected_piece = null
		legal_moves.clear()
		
	
