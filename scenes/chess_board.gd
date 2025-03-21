extends Node2D

# This scene serves as the View component.
# It receives signals from the Model,
# and renders the scene accordingly.

@export var controller: Node # ChessController is set here via the UI

func _ready():
	pass 

# renders the board.	
func draw_board(board: Array):
	var squares = $Squares
	var square_size = 64
	var square_color
	
	for y in range(board.size()):
		for x in range(board[y].size()):
			# Determine the color:
			if ((x + y) % 2 == 0):
				square_color = Color(1, 1, 1)
			else:
				square_color = Color(0.3, 0.3, 0.3)
			
			var square = ColorRect.new()
			square.color = square_color
			square.position = Vector2(x * square_size, y * square_size)
			square.size = Vector2(square_size, square_size)
			
			squares.add_child(square)
			
	
	
	
	
