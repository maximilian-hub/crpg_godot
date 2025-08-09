extends Node

class_name AIPlayer

var model: ChessBoardModel

const piece_values = {
	"pawn": 1,
	"knight": 3,
	"bishop": 3,
	"rook": 5,
	"queen": 9,
	"king": 100 # A high value to ensure it's protected
}

func _init(_model: ChessBoardModel):
	model = _model

func get_best_move() -> Dictionary:
	var legal_moves = get_all_legal_moves("black")
	if legal_moves.is_empty():
		return {}

	var best_move = {}
	var best_score = -INF

	for move in legal_moves:
		var piece = move.piece
		var from = piece.coordinate
		var to = move.to
		var target_piece = model.board[to.x][to.y]

		# Simulate the move
		model.board[to.x][to.y] = piece
		model.board[from.x][from.y] = null
		piece.coordinate = to

		var score = evaluate_board()

		# Undo the move
		model.board[from.x][from.y] = piece
		model.board[to.x][to.y] = target_piece
		piece.coordinate = from

		if score > best_score:
			best_score = score
			best_move = move

	return best_move

func get_all_legal_moves(color: String) -> Array:
	var all_legal_moves = []
	for r in range(model.board.size()):
		for c in range(model.board[r].size()):
			var piece = model.board[r][c]
			if piece and piece.color == color:
				var moves = model.get_legal_moves(piece)
				for move in moves:
					all_legal_moves.append({"piece": piece, "to": move})
	return all_legal_moves

func evaluate_board() -> float:
	var score = 0.0
	for r in range(model.board.size()):
		for c in range(model.board[r].size()):
			var piece = model.board[r][c]
			if piece:
				var value = piece_values.get(piece.type.replace("_king", ""), 0)
				if piece.color == "black":
					score += value
				else:
					score -= value
	return score
