#~~~~~~~~NEW FILE: chess_board.gd~~~~~~~~~~~~
extends Node2D

# This node serves as the main View component.
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
var powerup_sound = preload("res://assets/ss_aura/ss_powerup.mp3")
var aura_loop_sound = preload("res://assets/ss_aura/ss_aura.mp3") 
var powerdown_sound = preload("res://assets/ss_aura/ss_powerdown.mp3")
var active_loop_player: AudioStreamPlayer
@onready var powerup_player = AudioStreamPlayer.new()
@onready var aura_loop_player = AudioStreamPlayer.new()
@onready var powerdown_player = AudioStreamPlayer.new()
const POWERUP_VOLUME = -20
const AURA_LOOP_VOLUME = -20
const POWERDOWN_VOLUME = -20
const SQUARE_SIZE = 128


func _ready():
	# Setup audio players
	add_child(powerup_player)
	add_child(aura_loop_player)
	add_child(powerdown_player)

	powerup_player.stream = powerup_sound
	aura_loop_player.stream = aura_loop_sound
	powerdown_player.stream = powerdown_sound
	powerup_player.volume_db = POWERUP_VOLUME
	aura_loop_player.volume_db = AURA_LOOP_VOLUME
	powerdown_player.volume_db = POWERDOWN_VOLUME

	# Make the aura loop sound loop
	aura_loop_player.stream.loop = true

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
	if piece_data == null: return

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
	
func destroy_piece(piece: Node):
	# TODO: if piece.is_king: play king death sound, spawn king death effect
	spawn_explosion(piece.position)
	piece.queue_free()


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
	
func spawn_stun_stars(stunned_piece: Node):
	var stun_stars = stun_stars_scene.instantiate()
	stun_stars.position = Vector2(0,-10)
	stun_stars.add_to_group("stun")
	stunned_piece.add_child(stun_stars)

func spawn_ss_aura(piece: Node):
	var aura = ss_aura_scene.instantiate()
	aura.position = Vector2(0,-20)
	aura.add_to_group("aura")
	piece.add_child(aura)
	play_power_activation_sound()

	
func remove_stun_stars(coord: Vector2i):
	var stunned_piece = get_piece_node(coord)
	for child in stunned_piece.get_children():
		if child.is_in_group("stun"):
			child.queue_free()

func remove_ss_aura(piece_node: Node):
	for child in piece_node.get_children():
		if child.is_in_group("aura"):
			child.queue_free()

# In chess_board.gd (your view class)
func fade_out_ss_aura(piece_node: Node, include_powerdown: bool = true):
	if include_powerdown: play_power_deactivation_sound()
	
	for child in piece_node.get_children():
		if child.is_in_group("aura"):
			# Create a tween for the fade out animation
			var tween = create_tween()

			# Animate scale increase (1.5x) and opacity decrease (to 0)
			tween.parallel().tween_property(child, "scale", child.scale * 1.5, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

			# Queue free the aura after animation completes
			tween.tween_callback(child.queue_free)
			
			powerup_player.stop()
			aura_loop_player.stop()
			if include_powerdown: powerdown_player.play()

# Plays the powerup sound with a fadeout for the tail
func play_power_activation_sound():
	# Reset volumes in case they were modified
	powerup_player.volume_db = POWERUP_VOLUME
	aura_loop_player.volume_db = AURA_LOOP_VOLUME

	# Play the powerup sound
	powerup_player.play()

	# Create a tween to fade out the powerup tail
	var powerup_tween = create_tween()
	# Start fading out after 0.5 seconds (adjust based on when the annoying tail starts)
	powerup_tween.tween_interval(0.5)
	powerup_tween.tween_property(powerup_player, "volume_db", -40.0, 0.8).set_ease(Tween.EASE_OUT)

	# Start the loop with a slight delay
	await get_tree().create_timer(0.1).timeout
	aura_loop_player.play()
	
# Stops all power sounds and plays the powerdown sound
func play_power_deactivation_sound():	
	powerup_player.stop()
	aura_loop_player.stop()
	powerdown_player.play()


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
