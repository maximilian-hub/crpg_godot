extends Node2D

# This scene serves as the View component.
# It receives signals from the Model,
# and renders the scene accordingly.

@export var controller: Node # ChessController is set here via the UI
var square_scene = preload("res://scenes/square.tscn")

func _ready():
	pass 

# renders the board.	
func draw_board(board: Array):
	var squares = $Squares
	var square_size = 64
	var square_color
	
	for x in range(board.size()):
		for y in range(board[x].size()):
			# Determine the color:
			if ((x + y) % 2 == 0):
				square_color = Color(1, 1, 1)
			else:
				square_color = Color(0.3, 0.3, 0.3)
			
			var square = square_scene.instantiate()
			square.set_color(square_color)
			square.position = Vector2(x * square_size + 100, y * square_size + 100)
			# square.size = Vector2(square_size, square_size)
			square.coordinate = Vector2(y, x)
			
			squares.add_child(square)
			
			
			
	
	
	
	
