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
			board.append([null])
			for y in range(8):
				board[x].append(null)
		initialize_default_pieces()
	if boardType == "custom":
		for x in range(custom_size):
			board.append([null])
			for y in range(custom_size):
				board[x].append(null)

func initialize_default_pieces():
	board[0][0] = "black_rook"
	board[1][0] = "black_knight"
	board[2][0] = "black_bishop"
	board[3][0] = "black_queen"
	board[4][0] = "black_king"
	board[5][0] = "black_bishop"
	board[6][0] = "black_knight"
	board[7][0] = "black_rook"
	
	for x in range(8):
		board[x][1] = "black_pawn"
		board[x][6] = "white_pawn"
		
	board[0][7] = "white_rook"
	board[1][7] = "white_knight"
	board[2][7] = "white_bishop"
	board[3][7] = "white_queen"
	board[4][7] = "white_king"
	board[5][7] = "white_bishop"
	board[6][7] = "white_knight"
	board[7][7] = "white_rook"
		
		
		
func print_board():
	for row in board:
		print(row)
		
			

		
