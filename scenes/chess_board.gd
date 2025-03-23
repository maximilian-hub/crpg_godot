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
var explosion_scene = preload("res://nonsense/explosion.tscn")
const SQUARE_SIZE = 64

func _ready():
	pass 

# renders the board.	
func draw_board(modelBoard: Array):
	board = modelBoard
	
	for row in range(board.size()):
		for col in range(board[row].size()):
			var pos = grid_to_screen(row, col)
			draw_square(row,col,pos)
			draw_piece(row,col,pos)
			
func get_piece_node(coord: Vector2i) -> Node:
	var desired_piece = null
	
	var piece_nodes = $Pieces.get_children()
	for piece_node in piece_nodes:
		if piece_node.coordinate == coord:
			desired_piece = piece_node
			break
	
	return desired_piece

func grid_to_screen(row: int, col: int) -> Vector2:
	return Vector2(col * SQUARE_SIZE + 100, row * SQUARE_SIZE + 100)

func draw_square(row: int, col: int, pos: Vector2):
	var squares = $Squares
	var square = square_scene.instantiate()
	var square_color = get_square_color(row, col)
	square.set_color(square_color)
	square.position = pos
	square.coordinate = Vector2i(row, col)
	square.connect("square_clicked", controller._on_square_clicked)
	squares.add_child(square)

func draw_piece(row: int, col: int, pos: Vector2):
	var pieces = $Pieces
	var piece_data = board[row][col] # to give the nodes a reference to the model object

	if piece_data != null:
		var piece = piece_scene.instantiate()
		piece.position = pos
		piece.set_model(piece_data)
		piece.coordinate = Vector2i(row, col)
		pieces.add_child(piece)
			
func get_square_color(row: int, col: int):
	var square_color
	if ((row + col) % 2 == 0):
		square_color = light_square_color
	else:
		square_color = dark_square_color	
	return square_color

func show_legal_moves(legal_moves: Array):
	highlight_squares(legal_moves)

func highlight_squares(squares_to_highlight: Array):
	var squares = $Squares.get_children()
	for square in squares:
		if square.coordinate in squares_to_highlight: 
			square.highlight()


func clear_highlights():
	var squares = $Squares.get_children()
	for square in squares:
		square.clear_highlight()

func move_piece_node(piece_node: Node, to: Vector2i) -> Node:
		piece_node.coordinate = to
			
		# smooth movement:
		var tween = create_tween()
		tween.tween_property(
			piece_node,
			"position",
			grid_to_screen(to.x, to.y),
			0.12
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		return piece_node


func promote_piece(piece: Node, new_name: String):
	if piece:
		piece.set_sprite(new_name)

func get_piece_at(coord: Vector2i) -> Node:
	for piece in $Pieces.get_children():
		if piece.coordinate == coord:
			return piece
	return null

func remove_piece_at(coord: Vector2i):
	print("removing piece")
	for piece in $Pieces.get_children():
		if piece.coordinate == coord:
			spawn_explosion(piece.position)
			piece.queue_free()
			break

func promote_piece_at(coord: Vector2i, new_name: String):
	print("entering promote_piece_at()")
	print("Promoting piece at:", coord, "to:", new_name)
	for piece in $Pieces.get_children():
		print("Checking piece at:", piece.coordinate)
		if piece.coordinate == coord:
			print("FOUND piece at promotion square! Calling set_sprite...")
			piece.set_sprite(new_name)
			break
		print("❌ No matching piece found at promotion coordinate")

func spawn_explosion(pos: Vector2):
	var explosion = explosion_scene.instantiate()
	explosion.position = pos
	add_child(explosion)

# Promote the piece at the specified coordinate.
func promote(piece_node: Node, color: String):
	var sprite_name = color + "_queen"
	piece_node.set_sprite(sprite_name)
	print("trying to promote. calling set_sprite(" + sprite_name + ")")
	
