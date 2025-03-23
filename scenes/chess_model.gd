extends Node

@export var view: Node
@export var controller: Node
var boardType = "default"
var board: Array
var last_move: Dictionary = {} 		#from, to, piecename
var current_turn: String = "white" # can be white or black

var custom_size = 16

func _ready():
	initialize_board()
	print(board) # debug
	view.draw_board(board)

func initialize_board():
	if boardType == "default":
		for x in range(8):
			var row = []
			for y in range(8):
				row.append(null)
			board.append(row)
		initialize_default_pieces()
	if boardType == "custom":
		for x in range(custom_size):
			board.append([null])
			for y in range(custom_size):
				board[x].append(null)

func initialize_default_pieces():
	board[0][0] = ModelPiece.new("black", "rook", Vector2i(0, 0))
	board[0][1] = ModelPiece.new("black", "knight", Vector2i(0, 1))
	board[0][2] = ModelPiece.new("black", "bishop", Vector2i(0, 2))
	board[0][3] = ModelPiece.new("black", "queen", Vector2i(0, 3))
	board[0][4] = ModelPiece.new("black", "minotaur_king", Vector2i(0, 4))
	board[0][5] = ModelPiece.new("black", "bishop", Vector2i(0, 5))
	board[0][6] = ModelPiece.new("black", "knight", Vector2i(0, 6))
	board[0][7] = ModelPiece.new("black", "rook", Vector2i(0, 7))

	for x in range(8):
		board[1][x] = ModelPiece.new("black", "pawn", Vector2i(1, x))
		board[6][x] = ModelPiece.new("white", "pawn", Vector2i(6, x))

	board[7][0] = ModelPiece.new("white", "rook", Vector2i(7, 0))
	board[7][1] = ModelPiece.new("white", "knight", Vector2i(7, 1))
	board[7][2] = ModelPiece.new("white", "bishop", Vector2i(7, 2))
	board[7][3] = ModelPiece.new("white", "queen", Vector2i(7, 3))
	board[7][4] = ModelPiece.new("white", "minotaur_king", Vector2i(7, 4))
	board[7][5] = ModelPiece.new("white", "bishop", Vector2i(7, 5))
	board[7][6] = ModelPiece.new("white", "knight", Vector2i(7, 6))
	board[7][7] = ModelPiece.new("white", "rook", Vector2i(7, 7))


func get_legal_moves(piece: ModelPiece) -> Array:
	var moves := []
	
	match piece.type:
		"pawn":
			moves = get_pawn_moves(piece)
		"knight":
			moves = get_knight_moves(piece)
		"bishop":
			moves = get_bishop_moves(piece)
		"rook":
			moves = get_rook_moves(piece)
		"queen":
			moves = get_queen_moves(piece)
		"king":
			moves = get_king_moves(piece)
	
	return moves

func get_pawn_moves(piece: ModelPiece) -> Array:
	print("Entering get_pawn_moves.")
	piece.print_piece()
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var direction = -1 if piece.color == "white" else 1
	var moves := []

	var forward_one = row + direction
	if is_in_bounds(forward_one, col) and board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))

	var forward_two = row + (direction * 2)
	if not piece.has_moved and is_in_bounds(forward_two, col) and board[forward_two][col] == null:
		moves.append(Vector2i(forward_two, col))

	for dc in [-1, 1]:
		var diag_col = col + dc
		if is_in_bounds(forward_one, diag_col):
			var target = board[forward_one][diag_col]
			if target != null and target.color != piece.color:
				moves.append(Vector2i(forward_one, diag_col))

	# En passant
	if last_move.has("piece") and last_move["piece"].type == "pawn":
		var last_from = last_move["from"]
		var last_to = last_move["to"]
		if abs(last_to.x - last_from.x) == 2 and last_to.x == row:
			for dc in [-1, 1]:
				var side_col = col + dc
				if is_in_bounds(row, side_col) and last_to.y == side_col:
					var en_passant_row = row + direction
					moves.append(Vector2i(en_passant_row, side_col))

	return moves

func get_knight_moves(piece: ModelPiece) -> Array:
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var color = piece.color
	var moves := []
	var offsets = [
		Vector2i(2, 1), Vector2i(2, -1),
		Vector2i(-2, 1), Vector2i(-2, -1),
		Vector2i(1, 2), Vector2i(-1, 2),
		Vector2i(1, -2), Vector2i(-1, -2),
	]

	for offset in offsets:
		var target_pos = Vector2i(row, col) + offset
		if is_in_bounds(target_pos.x, target_pos.y):
			var target = board[target_pos.x][target_pos.y]
			if target == null or target.color != color:
				moves.append(target_pos)

	return moves

func get_bishop_moves(piece: ModelPiece) -> Array:
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var color = piece.color
	var moves := []
	var directions = [
		Vector2i(-1, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
		Vector2i(1, -1),
	]

	for dir in directions:
		var r = row + dir.x
		var c = col + dir.y
		while is_in_bounds(r, c):
			var target = board[r][c]
			if target == null:
				moves.append(Vector2i(r, c))
			elif target.color == color:
				break
			else:
				moves.append(Vector2i(r, c))
				break
			r += dir.x
			c += dir.y

	return moves

func get_rook_moves(piece: ModelPiece) -> Array:
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var color = piece.color
	var moves := []
	var directions = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]

	for dir in directions:
		var r = row + dir.x
		var c = col + dir.y
		while is_in_bounds(r, c):
			var target = board[r][c]
			if target == null:
				moves.append(Vector2i(r, c))
			elif target.color == color:
				break
			else:
				moves.append(Vector2i(r, c))
				break
			r += dir.x
			c += dir.y

	return moves

func get_queen_moves(piece: ModelPiece) -> Array:
	return get_rook_moves(piece) + get_bishop_moves(piece)

func get_king_moves(piece: ModelPiece) -> Array:
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var color = piece.color
	var moves := []

	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var r = row + dr
			var c = col + dc
			if is_in_bounds(r, c):
				var target = board[r][c]
				if target == null or target.color != color:
					moves.append(Vector2i(r, c))

	if not piece.has_moved:
		if can_castle_through(row, col, row, 0, color):
			moves.append(Vector2i(row, col - 2))
		if can_castle_through(row, col, row, 7, color):
			moves.append(Vector2i(row, col + 2))

	return moves

func move_piece(piece: ModelPiece, to: Vector2i):
	var from = piece.coordinate

	# 🐍 Check for en passant
	var is_en_passant = false
	if piece.type == "pawn" and from.y != to.y and board[to.x][to.y] == null:
		is_en_passant = true

	# 🗡️ If this is a regular capture, remove the target first
	if not is_en_passant and board[to.x][to.y] != null:
		print("removing piece")
		view.remove_piece_at(to)

	# 👣 Move on the model board
	board[from.x][from.y] = null
	board[to.x][to.y] = piece
	piece.coordinate = to

	# 🏰 Castling
	if piece.type == "king" and abs(to.y - from.y) == 2:
		var row = from.x
		if to.y == 6: # King-side castle
			board[row][5] = board[row][7]
			board[row][7] = null
			view.move_piece_node(Vector2i(row, 7), Vector2i(row, 5))
		elif to.y == 2: # Queen-side castle
			board[row][3] = board[row][0]
			board[row][0] = null
			view.move_piece_node(Vector2i(row, 0), Vector2i(row, 3))

	# 🐍 En passant capture
	if is_en_passant:
		var captured_row = from.x
		var captured_col = to.y
		board[captured_row][captured_col] = null
		view.remove_piece_at(Vector2i(captured_row, captured_col))

	view.move_piece_node(from, to)
	piece.has_moved = true
	
	switch_turn()

	# 👑 Promotion check (AFTER move & after any capture is resolved)
	if piece.type == "pawn":
		if (piece.color == "white" and to.x == 0) or (piece.color == "black" and to.x == 7):
			piece.type = "queen" #TODO: give options
			view.promote(piece)

	# 💾 Track the move for en passant logic
	last_move = {
		"from": from,
		"to": to,
		"piece": piece
	}

func can_castle_through(king_row: int, king_col: int, rook_row: int, rook_col: int, color: String) -> bool:
	var rook_piece = board[rook_row][rook_col]
	if rook_piece == null or rook_piece.color != color or rook_piece.type != "rook":
		return false

	if rook_piece.has_moved:
		return false

	var start = min(king_col, rook_col) + 1
	var end = max(king_col, rook_col)
	for c in range(start, end):
		if board[king_row][c] != null:
			return false

	return true

func switch_turn():
	if current_turn == "white":
		current_turn = "black"
	else:
		current_turn = "white"

func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and col >= 0 and col < board[row].size()
