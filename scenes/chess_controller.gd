extends Node

@export var model: Node
@export var view: Node # ChessBoard node is connected here via the UI

func _ready():
	pass
	
func _on_piece_clicked(piece: Node):
	print("controller here! someone told me a piece was clicked?????")
	print(piece)
	var legal_moves = model.get_legal_moves(piece)
