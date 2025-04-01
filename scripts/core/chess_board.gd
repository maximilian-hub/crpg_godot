# chess_board.gd
extends Node2D

# This scene serves as the View component.
# It receives signals from the Model,
# and renders the scene accordingly.

@export var controller: Node # ChessController is set here via the UI
@export var white_cooldown_button: Node
@export var black_cooldown_button: Node
@export var flash_overlay: ColorRect
var square_scene = preload("res://scenes/square.tscn")
var piece_scene = preload("res://scenes/piece.tscn")
@export var light_square_color = Color(1, 1, 1) 
@export var dark_square_color = Color(0.3, 0.3, 0.3)
var board: Array
var hp_bar_scene = preload("res://ui/hp_bar.tscn")
var stun_stars_scene = preload("res://effects/stun_stars.tscn")
var explosion_scene = preload("res://effects/explosion.tscn")
var splatter_scene = preload("res://effects/blood_splatter.tscn")
var ss_aura_scene = preload("res://effects/ss_aura.tscn")
const SQUARE_SIZE = 128

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
		piece_data.view_node = piece
	
		if piece_data.max_hp > 1:
			var hp_bar = hp_bar_scene.instantiate()
			hp_bar.max_hp = piece_data.max_hp
			hp_bar.current_hp = piece_data.max_hp
			hp_bar.position = Vector2(0, 24)
			piece.add_child(hp_bar)
					
func get_piece_node(coord: Vector2i) -> Node:
	var desired_piece = null
	
	var piece_nodes = $Pieces.get_children()
	for piece_node in piece_nodes:
		if piece_node.coordinate == coord:
			desired_piece = piece_node
			break
	
	return desired_piece

## Converts a board position (eg 0,1) into a screen position for rendering purposes
func grid_to_screen(row: int, col: int) -> Vector2:
	var board_pixel_width = board[0].size() * SQUARE_SIZE
	var board_pixel_height = board.size() * SQUARE_SIZE
	var viewport_size = get_viewport_rect().size
	var offset_x = (viewport_size.x - board_pixel_width) / 2 + SQUARE_SIZE / 2
	var offset_y = (viewport_size.y - board_pixel_height) / 2 + SQUARE_SIZE / 2
	return Vector2(col * SQUARE_SIZE + offset_x, row * SQUARE_SIZE + offset_y)
			
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

#func hurt_piece_at(coord: Vector2i):
	#for piece in $Pieces.get_children():
		#if piece.coordinate == coord:
			#spawn_splatter(piece.position)
			#break
	
func destroy_piece_at(coord: Vector2i):
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
	
func spawn_splatter(coord: Vector2i):
	var splatter = splatter_scene.instantiate()
	splatter.position = grid_to_screen(coord.x, coord.y)
	add_child(splatter)
	
func spawn_stun_stars(coord: Vector2i):
	var stunned_piece = get_piece_node(coord)
	var stun_stars = stun_stars_scene.instantiate()
	stun_stars.position = Vector2(0,-10)
	stun_stars.add_to_group("stun")
	stunned_piece.add_child(stun_stars)

func spawn_ss_aura(coord: Vector2i):
	var piece = get_piece_node(coord)
	var aura = ss_aura_scene.instantiate()
	aura.position = Vector2(0,-20)
	aura.add_to_group("aura")
	piece.add_child(aura)
	
func remove_stun_stars(coord: Vector2i):
	var stunned_piece = get_piece_node(coord)
	for child in stunned_piece.get_children():
		if child.is_in_group("stun"):
			child.queue_free()

func remove_ss_aura(coord: Vector2i):
	var piece = get_piece_node(coord)
	for child in piece.get_children():
		if child.is_in_group("aura"):
			child.queue_free()

# Promote the piece at the specified coordinate.
# The model should already reflect the new type.
func update_piece(piece_node: Node):
	piece_node.update_sprite()
	
func minotaur_retaliate(center: Vector2i, targets: Array):
	for coord in targets:
		var pos = grid_to_screen(coord.x, coord.y)
		spawn_explosion(pos)

func start_minotaur_rage_intro(coord: Vector2i) -> void:
	var minotaur_node = get_piece_at(coord)
	if minotaur_node == null:
		return

	# Lock input
	controller.is_input_locked = true

	# Roar animation / shake / scale pop
	var tween = create_tween()
	tween.tween_property(minotaur_node, "scale", minotaur_node.scale * 1.25, 1).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_interval(0.15)
	tween.tween_property(minotaur_node, "scale", minotaur_node.scale, 0.1)
	
	await tween.finished
	
	# Unlock input
	controller.is_input_locked = false

## Changes the cooldown display to reflect the king's new cooldown.
func update_cooldown(piece: ModelPiece):
	var format_string = "%s Cooldown: %s"
	var text = format_string % [piece.ACTIVE_NAME, piece.current_cooldown]
	
	if piece.color == "white":
		white_cooldown_button.text = text
	else:
		black_cooldown_button.text = text

## Changes the display to reflect that the piece's active ability is ready to use.
func ready_cooldown(piece: ModelPiece):
	var ready_text = "%s!!!" % piece.ACTIVE_NAME
	if piece.color == "white":
		white_cooldown_button.text = ready_text
	else:
		black_cooldown_button.text = ready_text
		
func flash_screen(duration := 1):
	flash_overlay.visible = true
	flash_overlay.color.a = 1.0  # Instant full white
	
	var tween = create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(flash_overlay, "hide"))  # hide when done
