extends Node

@export var view: Node
var boardType = "default"
var board: Array
var last_move: Dictionary = {}


var custom_size = 16

func _ready():
	initialize_board()
	print_board() # Debug
	view.draw_board(board)
	

#Initializes the board array in the proper shape for its board type.
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
	board[0][0] = "black_rook"
	board[0][1] = "black_knight"
	board[0][2] = "black_bishop"
	board[0][3] = "black_queen"
	board[0][4] = "black_king"
	board[0][5] = "black_bishop"
	board[0][6] = "black_knight"
	board[0][7] = "black_rook"

	for x in range(8):
		board[1][x] = "black_pawn"
		board[6][x] = "white_pawn"

	board[7][0] = "white_rook"
	board[7][1] = "white_knight"
	board[7][2] = "white_bishop"
	board[7][3] = "white_queen"
	board[7][4] = "white_king"
	board[7][5] = "white_bishop"
	board[7][6] = "white_knight"
	board[7][7] = "white_rook"

func get_legal_moves(piece):
	# Receives a piece. The piece knows its own coordinate.
	# Returns the legal coordinates this piece can move to.

	var moves := []
	var row = piece.coordinate.x
	var col = piece.coordinate.y
	var name = board[row][col] # e.g. "white_pawn"
	
	if name == null:
		return []
	
	var color = name.split("_")[0]
	var type = name.split("_")[1]
	
	match type:
		"pawn":
			moves = get_pawn_moves(row, col, color, piece.hasMoved)
		"knight":
			moves = get_knight_moves(row, col, color)
		"bishop":
			moves = get_bishop_moves(row, col, color)
		"rook":
			moves = get_rook_moves(row, col, color)
		"queen":
			moves = get_queen_moves(row, col, color)
		"king":
			moves = get_king_moves(row, col, color)
	
	return moves

func get_pawn_moves(row: int, col: int, color: String, has_moved: bool) -> Array:
	var direction = -1 if (color == "white") else 1
	var moves := []
	
	# One-square advance
	var forward_one = row + direction
	if is_in_bounds(forward_one, col) and board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))
	
	# Two-square advance if hasn't moved
	var forward_two = row + (direction * 2)
	if not has_moved and is_in_bounds(forward_two, col) and board[forward_two][col] == null:
		moves.append(Vector2i(forward_two, col))
	
	# Diagonal captures
	for dc in [-1, 1]:
		var diag_col = col + dc
		if is_in_bounds(forward_one, diag_col):
			var target = board[forward_one][diag_col]
			if target != null and not target.begins_with(color):
				moves.append(Vector2i(forward_one, diag_col))
	
	# En passant
	if last_move.has("piece_name") and last_move["piece_name"].ends_with("pawn"):
		var last_from = last_move["from"]
		var last_to = last_move["to"]
		
		# The pawn must have just moved 2 squares forward
		if abs(last_to.x - last_from.x) == 2 and last_to.x == row:
			for dc in [-1, 1]:
				var side_col = col + dc
				if is_in_bounds(row, side_col) and last_to.y == side_col:
					# Can capture en passant diagonally forward
					var en_passant_row = row + direction
					moves.append(Vector2i(en_passant_row, side_col))

	
	return moves

func get_knight_moves(row: int, col: int, color: String) -> Array:
	var moves := []
	
	# Assuming enough space, Knights have 8 moves.
	# Kights can move 2 squares in any direction,
	# and then 1 square in any perpendicular direction.
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
			if target == null or not target.begins_with(color):
				moves.append(target_pos)
		
	return moves

func get_bishop_moves(row: int, col: int, color: String) -> Array:
	var moves := []

	# Directions: [ (↖), (↗), (↘), (↙) ]
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
			elif target.begins_with(color):
				break # Friendly piece blocks the way
			else:
				moves.append(Vector2i(r, c)) # Enemy — capture and stop
				break
			r += dir.x
			c += dir.y

	return moves

func get_rook_moves(row: int, col: int, color: String) -> Array:
	var moves := []
	
	# Directions: ↑ ↓ → ←
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
			elif target.begins_with(color):
				break
			else:
				moves.append(Vector2i(r, c)) # enemy capture
				break
			r += dir.x
			c += dir.y
	
	return moves

func get_queen_moves(row: int, col: int, color: String) -> Array:
	var rook_moves = get_rook_moves(row, col, color)
	var bishop_moves = get_bishop_moves(row, col, color)
	return rook_moves + bishop_moves

func get_king_moves(row: int, col: int, color: String) -> Array:
	var moves := []

	# Normal 1-square moves
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var r = row + dr
			var c = col + dc
			if is_in_bounds(r, c):
				var target = board[r][c]
				if target == null or not target.begins_with(color):
					moves.append(Vector2i(r, c))

	# Castling logic (ignore check for now)
	if not get_piece_at(row, col).hasMoved:
		# Queen-side rook
		if can_castle_through(row, col, row, 0, color):
			moves.append(Vector2i(row, col - 2))
		# King-side rook
		if can_castle_through(row, col, row, 7, color):
			moves.append(Vector2i(row, col + 2))

	return moves

func can_castle_through(king_row: int, king_col: int, rook_row: int, rook_col: int, color: String) -> bool:
	# Rook must exist and be unmoved
	var rook_name = board[rook_row][rook_col]
	if rook_name == null or not rook_name.begins_with(color) or not rook_name.ends_with("rook"):
		return false

	var rook_piece = get_piece_at(rook_row, rook_col)
	if rook_piece == null or rook_piece.hasMoved:
		return false

	# Squares between must be empty
	var start = min(king_col, rook_col) + 1
	var end = max(king_col, rook_col)
	for c in range(start, end):
		if board[king_row][c] != null:
			return false

	return true

	
	
func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and col >= 0 and col < board[row].size()

	
func move_piece(from: Vector2i, to: Vector2i):
	var piece_name = board[from.x][from.y]
	
	# Check for en passant (this needs to be done before the piece is actually moved)
	var is_en_passant = false
	if piece_name.ends_with("pawn") and from.y != to.y and board[to.x][to.y] == null:
		is_en_passant = true
		
	board[from.x][from.y] = null
	board[to.x][to.y] = piece_name

	#  Detect castling
	if piece_name.ends_with("king") and abs(to.y - from.y) == 2:
		var row = from.x
		if to.y == 6: # King-side castle
			board[row][5] = board[row][7] # Move rook
			board[row][7] = null
			view.move_piece_node(Vector2i(row, 7), Vector2i(row, 5))
		elif to.y == 2: # Queen-side castle
			board[row][3] = board[row][0]
			board[row][0] = null
			view.move_piece_node(Vector2i(row, 0), Vector2i(row, 3))
	
	# Check for en passant capture
	if is_en_passant:
		# This was a diagonal move to an empty square = en passant!
		var captured_row = from.x
		var captured_col = to.y
		board[captured_row][captured_col] = null
		view.remove_piece_at(Vector2i(captured_row, captured_col))


	view.move_piece_node(from, to)
	
	last_move = {
	"from": from,
	"to": to,
	"piece_name": piece_name
}



func get_piece_at(row: int, col: int):
	for piece in view.get_node("Pieces").get_children():
		if piece.coordinate == Vector2i(row, col):
			return piece
	return null



func print_board():
	for row in board:
		print(row)
