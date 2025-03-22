extends Node2D

# This scene serves as the View component.
# It receives signals from the Model,
# and renders the scene accordingly.

@export var controller: Node # ChessController is set here via the UI
var square_scene = preload("res://scenes/square.tscn")
var piece_scene = preload("res://scenes/piece.tscn")
@export var light_square_color = Color(1, 1, 1) 
@export var dark_square_color = Color(0.3, 0.3, 0.3)
var board: Array
const SQUARE_SIZE = 64

func _ready():
	pass 

# renders the board.	
func draw_board(modelBoard: Array):
	board = modelBoard
	var square_size = 64
	
	for row in range(board.size()):
		for col in range(board[row].size()):
			var pos = grid_to_screen(row, col)
			draw_square(row,col,pos)
			draw_piece(row,col,pos)

func grid_to_screen(row: int, col: int) -> Vector2:
	return Vector2(col * SQUARE_SIZE + 100, row * SQUARE_SIZE + 100)

func draw_square(row: int, col: int, pos: Vector2):
	var squares = $Squares
	var square = square_scene.instantiate()
	var square_color = get_square_color(row, col)
	square.set_color(square_color)
	square.position = pos
	square.coordinate = Vector2i(row, col)
	squares.add_child(square)

func draw_piece(row: int, col: int, pos: Vector2):
	var pieces = $Pieces
	if board[row][col] != null:
		var piece = piece_scene.instantiate()
		piece.position = pos
		piece.set_sprite(board[row][col])
		piece.connect("piece_clicked", controller._on_piece_clicked)
		piece.coordinate = Vector2i(row, col)
		pieces.add_child(piece)
			
func get_square_color(row: int, col: int):
	var square_color
	if ((row + col) % 2 == 0):
		square_color = light_square_color
	else:
		square_color = dark_square_color	
	return square_color
