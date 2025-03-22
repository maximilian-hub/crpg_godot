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
	
	# To calculate:
	# get the piece's type.
		# for pawns:
			# if they haven't moved, they can advance two squares.
			# they can advance one square.
			# they can capture diagonally.
			# they can en passant. (this'll be fun lmao)
	pass

func print_board():
	for row in board:
		print(row)
