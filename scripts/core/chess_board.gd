#~~~~~~~~NEW FILE: chess_board.gd~~~~~~~~~~~~
extends Node2D
class_name ChessBoardView

## This node serves as the main View component.
# It receives signals from the Model,
# and renders the scene accordingly.

##This is just for prototyping. 
# Eventually, the Chess scene will look very different,
# with a slightly angled board, 
# hands that move the pieces,
# and other features.
# I'm using MVC for this part of the project largely for this,
# so that a little ways down the road,
# I can completely replace this View with another,
# without too much fussing about with the game logic.

signal rage_intro_animation_completed()
signal square_selected(coordinate: Vector2i)

@export var white_cooldown_button: Node
@export var black_cooldown_button: Node
@export var flash_overlay: ColorRect
var square_scene = preload("res://scenes/square.tscn")
var piece_scene = preload("res://scenes/piece.tscn")
@export var light_square_color = Color(1, 1, 1) 
@export var dark_square_color = Color(0.3, 0.3, 0.3)
@export_enum("white", "black") var viewing_color: String = "white"
var board: Array
var projection := ChessBoardProjection.new()
var hp_bar_scene = preload("res://ui/hp_bar.tscn")
var stun_stars_scene = preload("res://effects/stun_stars.tscn")
var explosion_scene = preload("res://effects/explosion.tscn")
var splatter_scene = preload("res://effects/blood_splatter.tscn")
var ss_aura_scene = preload("res://effects/ss_aura.tscn")
var bone_pawn_portal_scene = preload("res://effects/bone_pawn_portal.tscn")
var bone_pawn_reveal_shader = preload("res://effects/bone_pawn_reveal.gdshader")
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
const PIECE_MOVE_DURATION = 0.12

const BONE_PAWN_SUMMON_RISE_DURATION := 1
const BONE_PAWN_SUMMON_RISE_DISTANCE := 28.0
const BONE_PAWN_SUMMON_SHAKE_AMPLITUDE := 4.0
const BONE_PAWN_SUMMON_SHAKE_CYCLES := 6.0


func _ready():
	setup_audio_players()
	get_viewport().size_changed.connect(_layout_board)

func setup_audio_players():
	add_child(powerup_player)
	add_child(aura_loop_player)
	add_child(powerdown_player)

	powerup_player.stream = powerup_sound
	aura_loop_player.stream = aura_loop_sound
	powerdown_player.stream = powerdown_sound
	powerup_player.volume_db = POWERUP_VOLUME
	aura_loop_player.volume_db = AURA_LOOP_VOLUME
	powerdown_player.volume_db = POWERDOWN_VOLUME

	aura_loop_player.stream.loop = true
	
# renders the board.	
func draw_board(modelBoard: Array) -> Dictionary:
	board = modelBoard
	_configure_projection()
	var rendered: Dictionary = {}
	
	for row in range(board.size()):
		for col in range(board[row].size()):
			draw_square(row, col)
			#draw_piece(row,col,pos)
			var piece_data: ModelPiece = board[row][col]
			var piece_node := draw_piece(piece_data)
			if piece_data != null and piece_node != null:
				rendered[piece_data] = piece_node
	return rendered

func _layout_board() -> void:
	if board.is_empty():
		return
	_configure_projection()
	for square in $Squares.get_children():
		square.configure_geometry(square.coordinate, projection.get_cell_polygon(square.coordinate))
	for piece in $Pieces.get_children():
		piece.position = grid_to_screen(piece.coordinate.x, piece.coordinate.y)
		_update_piece_depth(piece)

func set_viewing_color(color: String) -> void:
	viewing_color = color if color == "black" else "white"
	_layout_board()

func _configure_projection() -> void:
	projection.configure(
		get_viewport_rect().size,
		board.size(),
		board[0].size(),
		viewing_color
	)

func draw_square(row: int, col: int):
	var squares = $Squares
	var square: SquareView = square_scene.instantiate()
	var square_color = get_square_color(row, col)
	square.set_color(square_color)
	square.configure_geometry(
		Vector2i(row, col),
		projection.get_cell_polygon(Vector2i(row, col))
	)
	square.connect("square_clicked", _on_square_selected)
	square.z_index = -2
	squares.add_child(square)

func _on_square_selected(coordinate: Vector2i) -> void:
	square_selected.emit(coordinate)

func draw_piece(piece_data: ModelPiece) -> Node:
	if piece_data == null: return null # no need to draw a piece that doesn't exist!
	var pieces = $Pieces
	var row = piece_data.coordinate.x
	var col = piece_data.coordinate.y
	var pos = grid_to_screen(row, col)
	var piece = piece_scene.instantiate()
	piece.position = pos
	piece.set_model(piece_data)
	piece.coordinate = Vector2i(row, col)
	_update_piece_depth(piece)
	pieces.add_child(piece)

	# Does it need an HP bar?
	if piece_data.max_hp > 1:
		var hp_bar = hp_bar_scene.instantiate()
		hp_bar.max_hp = piece_data.max_hp
		hp_bar.current_hp = piece_data.max_hp
		hp_bar.position = Vector2(0, 24)
		piece.add_child(hp_bar)
	return piece
					
func get_piece_node(coord: Vector2i) -> Node:
	var desired_piece = null
	
	var piece_nodes = $Pieces.get_children()
	for piece_node in piece_nodes:
		if piece_node.coordinate == coord:
			desired_piece = piece_node
			break
	
	return desired_piece

## Compatibility wrapper for presentation code that targets a logical cell.
func grid_to_screen(row: int, col: int) -> Vector2:
	return projection.get_cell_anchor(Vector2i(row, col))

func _update_piece_depth(piece_node: Node2D) -> void:
	piece_node.z_index = projection.get_display_coordinate(piece_node.coordinate).x
			
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

func move_piece_node(piece_node: Node, to: Vector2i) -> void:
	if not is_instance_valid(piece_node):
		printerr("move_piece_node: Invalid piece node.")
		return

	piece_node.coordinate = to
	_update_piece_depth(piece_node)
	await _tween_piece_to(piece_node, grid_to_screen(to.x, to.y))

func attack_piece_node(piece_node: Node, to: Vector2i) -> void:
	if not is_instance_valid(piece_node):
		printerr("attack_piece_node: Invalid piece node.")
		return

	var original_position: Vector2 = piece_node.position
	await _tween_piece_to(piece_node, grid_to_screen(to.x, to.y))
	await _tween_piece_to(piece_node, original_position)

func _tween_piece_to(piece_node: Node, target_position: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(
		piece_node,
		"position",
		target_position,
		PIECE_MOVE_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func promote_piece(piece: Node, new_name: String):
	if piece:
		piece.set_sprite(new_name)

func get_piece_at(coord: Vector2i) -> Node:
	for piece in $Pieces.get_children():
		if piece.coordinate == coord:
			return piece
	return null

## Destroy a sprite with a visual effect.
func destroy_piece(piece: Node):
	# TODO: if piece.is_king: play king death sound, spawn king death effect
	spawn_explosion(piece.position)
	piece.queue_free()

## Disappear a sprite.
func remove_piece(piece: Node):
	piece.queue_free()


func promote_piece_at(coord: Vector2i, new_name: String):
	for piece in $Pieces.get_children():
		if piece.coordinate == coord:
			piece.set_sprite(new_name)
			break

func spawn_explosion(pos: Vector2):
	var explosion = explosion_scene.instantiate()
	explosion.position = pos
	explosion.z_index = 20
	add_child(explosion)
	
func spawn_splatter(coord: Vector2i):
	var splatter = splatter_scene.instantiate()
	splatter.position = grid_to_screen(coord.x, coord.y)
	splatter.z_index = 20
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

func play_bone_pawn_summon(piece_node: Node2D) -> void:
	if not is_instance_valid(piece_node):
		return
	var sprite := piece_node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	var original_position := piece_node.position
	var original_material := sprite.material
	var reveal_material := ShaderMaterial.new()
	reveal_material.shader = bone_pawn_reveal_shader
	reveal_material.set_shader_parameter("reveal", 0.0)
	sprite.material = reveal_material
	piece_node.position = original_position + Vector2.DOWN * BONE_PAWN_SUMMON_RISE_DISTANCE

	var portal := bone_pawn_portal_scene.instantiate() as BonePawnSummonPortal
	portal.position = original_position + Vector2.DOWN * 35.0
	add_child(portal)
	await portal.open()

	var elapsed := 0.0
	while elapsed < BONE_PAWN_SUMMON_RISE_DURATION and is_instance_valid(piece_node):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var target_position := grid_to_screen(piece_node.coordinate.x, piece_node.coordinate.y)
		var progress := clampf(elapsed / BONE_PAWN_SUMMON_RISE_DURATION, 0.0, 1.0)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		var shake := sin(progress * TAU * BONE_PAWN_SUMMON_SHAKE_CYCLES)
		shake *= BONE_PAWN_SUMMON_SHAKE_AMPLITUDE * (1.0 - progress)
		piece_node.position = target_position + Vector2(
			shake,
			lerpf(BONE_PAWN_SUMMON_RISE_DISTANCE, 0.0, eased_progress)
		)
		reveal_material.set_shader_parameter("reveal", eased_progress)
		portal.position = target_position + Vector2.DOWN * 35.0
		portal.rotation = sin(progress * TAU * 2.0) * 0.08

	if is_instance_valid(piece_node):
		piece_node.position = grid_to_screen(piece_node.coordinate.x, piece_node.coordinate.y)
		if is_instance_valid(sprite):
			sprite.material = original_material
	if is_instance_valid(portal):
		await portal.close()

	
func remove_stun_stars(coord: Vector2i):
	var stunned_piece = get_piece_node(coord)
	for child in stunned_piece.get_children():
		if child.is_in_group("stun"):
			child.queue_free()

func remove_stun_stars_from_piece(piece_node: Node):
	for child in piece_node.get_children():
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
	
func minotaur_retaliate(targets: Array):
	for coord in targets:
		var pos = grid_to_screen(coord.x, coord.y)
		spawn_explosion(pos)

func start_minotaur_rage_intro(minotaur_node: Node) -> void:
	if not is_instance_valid(minotaur_node):
		printerr("start_minotaur_rage_intro: Invalid Minotaur view node.")
		rage_intro_animation_completed.emit()
		return

	var original_scale = minotaur_node.scale
	var tween = create_tween()
	tween.tween_property(minotaur_node, "scale", original_scale * 1.25, 1).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_interval(0.15) # Adjust timing as needed
	tween.tween_property(minotaur_node, "scale", original_scale, 0.1)
	await tween.finished

	# The Model owns input locking for the complete action/reaction chain.
	rage_intro_animation_completed.emit()
		
func flash_screen(duration := 1):
	flash_overlay.visible = true
	flash_overlay.color.a = 1.0  # Instant full white
	
	var tween = create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(flash_overlay, "hide"))  # hide when done

## Updates the cooldown display text for the given King.
## Connected to KingPiece.cooldown_changed signal.
func update_cooldown_display(king: KingPiece, new_cooldown: int):
	var button = white_cooldown_button if king.color == "white" else black_cooldown_button
	var format_string = "%s CD: %s"
	button.text = format_string % [king.get_active_ability_name(), new_cooldown]

## Updates the display text to show the ability is ready.
## Connected to KingPiece.cooldown_ready signal.
func ready_cooldown_display(king: KingPiece):
	var button = white_cooldown_button if king.color == "white" else black_cooldown_button
	var ready_text = "%s Ready!" % king.get_active_ability_name() # Changed from "!!!"
	button.text = ready_text
