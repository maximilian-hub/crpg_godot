extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI

func _ready():
	pass
	
func _on_piece_clicked(piece: Node):
	view.clear_highlights()
	var legal_moves = model.get_legal_moves(piece)
	#print("legal moves of clicked piece: ")
	#print(legal_moves)
	view.show_legal_moves(legal_moves)
