extends Node

@export var view: Node
var boardType = "default"
var board = []

var custom_size = 16

func _ready():
	initialize_board()
	print_board() # Debug
	view.draw_board(board)
	

#Initializes the board array in the proper shape for its board type.
func initialize_board():
	if boardType == "default":
		board = [
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0],
			[0,0,0,0,0,0,0,0]
		]
		initialize_default_pieces()
	if boardType == "custom":
		for x in range(custom_size):
			board.append([0])
			for y in range(custom_size):
				board[x].append(0)
				

func initialize_default_pieces():
		pass
		
func print_board():
	for row in board:
		print(row)
		
			

		
