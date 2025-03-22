extends Node

@export var view: Node
var boardType = "default"
var board: Array

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
	@warning_ignore("shadowed_variable_base_class")
	var name = board[row][col] # e.g. "white_pawn"
	
	if name == null:
		return []
	
	var color = name.split("_")[0]
	var type = name.split("_")[1]
	
	if type == "pawn":
		moves = get_pawn_moves(row, col, color, piece.hasMoved)
	
	return moves

func get_pawn_moves(row: int, col: int, color: String, has_moved: bool) -> Array:
	var direction = -1 if (color == "white") else 1
	var moves := []
	
	var forward_one = row + direction
	if is_in_bounds(forward_one, col) and board[forward_one][col] == null:
		moves.append(Vector2i(forward_one, col))
		
		# Two-square move if hasn't moved
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
	
	return moves

func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and col >= 0 and col < board[row].size()

func move_piece(from: Vector2i, to: Vector2i):
	print("move_piece()")
	var piece_name = board[from.x][from.y]
	board[from.x][from.y] = null
	board[to.x][to.y] = piece_name
	
	# Tell the piece it moved
	view.move_piece_node(from, to)



func print_board():
	for row in board:
		print(row)
