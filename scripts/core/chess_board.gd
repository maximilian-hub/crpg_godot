#~~~~~~~~NEW FILE: chess_board.gd~~~~~~~~~~~~
extends Node2D
class_name ChessBoardView

const BoardMaterialSurface := preload("res://scripts/view/chess_board_material_surface.gd")

## This node serves as the main View component of the chess game.
# It receives signals from the Model,
# and renders the scene accordingly.

signal rage_intro_animation_completed()
signal square_selected(coordinate: Vector2i)
signal editor_square_pressed(coordinate: Vector2i)
signal editor_square_entered(coordinate: Vector2i)
signal editor_square_exited(coordinate: Vector2i)

@export var white_cooldown_button: Node
@export var black_cooldown_button: Node
@export var flash_overlay: ColorRect
@export var visual_style: Resource:
	set(value):
		if visual_style != null and visual_style.changed.is_connected(_on_visual_style_changed):
			visual_style.changed.disconnect(_on_visual_style_changed)
		visual_style = value
		if is_inside_tree():
			_connect_visual_style()
		_request_layout()
@export_range(0.5, 1.0, 0.01) var viewport_height_width_ratio := 0.90:
	set(value):
		viewport_height_width_ratio = value
		_request_layout()
@export_range(0.3, 0.9, 0.01) var viewport_width_cap_ratio := 0.64:
	set(value):
		viewport_width_cap_ratio = value
		_request_layout()
@export_range(0.5, 1.0, 0.01) var projected_depth_ratio := 0.70:
	set(value):
		projected_depth_ratio = value
		_request_layout()
@export_range(0.7, 1.0, 0.01) var far_edge_width_ratio := 0.88:
	set(value):
		far_edge_width_ratio = value
		_request_layout()
@export_range(0.3, 0.7, 0.01) var vertical_center_ratio := 0.50:
	set(value):
		vertical_center_ratio = value
		_request_layout()
@export_range(0.0, 0.25, 0.01) var piece_forward_bias := 0.35: # adjust this for piece placement
	set(value):
		piece_forward_bias = value
		_request_layout()
@export var scale_world_with_projection := false:
	set(value):
		scale_world_with_projection = value
		_request_layout()
@export var show_piece_grip_anchors := false:
	set(value):
		show_piece_grip_anchors = value
		if is_node_ready():
			_sync_piece_grip_anchor_debug()
var square_scene = preload("res://scenes/square.tscn")
var piece_scene = preload("res://scenes/piece.tscn")
@export_enum("white", "black") var viewing_color: String = "white"
var board: Array
var projection := ChessBoardProjection.new()
var animation_duration_scale := 1.0
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
@onready var board_body: Node2D = $BoardBody
@onready var material_surface: MeshInstance2D = $BoardBody/MaterialSurface
@onready var near_hand_rig: ChessHandRig = (get_node_or_null("NearHandRig") if has_node("NearHandRig") else get_node_or_null("PlayerHandRig")) as ChessHandRig
@onready var far_hand_rig: ChessHandRig = get_node_or_null("FarHandRig") as ChessHandRig
## Compatibility alias for developer labs and older focused tests. Shipping
## presentation should resolve a rig by army color through get_hand_rig_for_color().
var player_hand_rig: ChessHandRig:
	get:
		return near_hand_rig
const POWERUP_VOLUME = -20
const AURA_LOOP_VOLUME = -20
const POWERDOWN_VOLUME = -20
const PIECE_MOVE_DURATION = 0.12
const PIECE_REFERENCE_NEAR_EDGE_WIDTH := 486.0
## Each displayed row owns enough z-space for the layered hand rig to sit inside
## it without overtaking any piece in the next row toward the camera.
const BOARD_DEPTH_STRIDE := 10
const BOARD_EFFECT_Z := 90
const DRAG_GHOST_Z := 95

const BONE_PAWN_SUMMON_RISE_DURATION := 1
const BONE_PAWN_SUMMON_RISE_DISTANCE := 28.0
const BONE_PAWN_SUMMON_SHAKE_AMPLITUDE := 4.0
const BONE_PAWN_SUMMON_SHAKE_CYCLES := 6.0


func _ready():
	# Seat is a board-space role, not character or army identity. Enforce it here
	# so an open Godot scene saved after an external edit cannot silently turn the
	# far rig back into a near rig.
	if is_instance_valid(near_hand_rig):
		near_hand_rig.seat = ChessHandRig.Seat.NEAR
	if is_instance_valid(far_hand_rig):
		far_hand_rig.seat = ChessHandRig.Seat.FAR
	setup_audio_players()
	_connect_visual_style()
	_sync_hand_board_sounds()
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
	
	for row in range(board.size()):
		for col in range(board[row].size()):
			draw_square(row, col)
	return _draw_pieces()

func _draw_pieces() -> Dictionary:
	var rendered: Dictionary = {}
	for row in range(board.size()):
		for col in range(board[row].size()):
			var piece_data: ModelPiece = board[row][col]
			var piece_node := draw_piece(piece_data)
			if piece_data != null and piece_node != null:
				rendered[piece_data] = piece_node
	return rendered

func rebuild_board(model_board: Array) -> Dictionary:
	clear_transient_presentation()
	for child in $Pieces.get_children():
		child.free()

	var preserve_squares := _squares_match_board(model_board)
	board = model_board
	_configure_projection()
	_layout_board_body()
	if preserve_squares:
		# Position restores change occupancy, not board geometry. Keeping the square
		# Area2Ds alive also avoids freeing the square currently emitting input_event.
		return _draw_pieces()

	# A genuine geometry change needs new hit regions. queue_free() is required
	# here because rebuild_board can be reached synchronously from a square signal.
	for child in $Squares.get_children():
		child.input_pickable = false
		child.queue_free()
	for row in range(board.size()):
		for col in range(board[row].size()):
			draw_square(row, col)
	return _draw_pieces()

func _squares_match_board(model_board: Array) -> bool:
	var expected_count := 0
	for row in model_board:
		expected_count += row.size()
	if $Squares.get_child_count() != expected_count:
		return false
	for square in $Squares.get_children():
		var coordinate: Vector2i = square.coordinate
		if coordinate.x < 0 or coordinate.x >= model_board.size():
			return false
		if coordinate.y < 0 or coordinate.y >= model_board[coordinate.x].size():
			return false
	return true

func clear_transient_presentation() -> void:
	clear_highlights()
	for child in get_children():
		if child != $BoardBody and child != $Squares and child != $Pieces and child != near_hand_rig and child != far_hand_rig and (child.is_in_group("aura") or child.is_in_group("stun")):
			child.queue_free()

func _layout_board() -> void:
	if board.is_empty():
		return
	_configure_projection()
	_layout_board_body()
	for square in $Squares.get_children():
		square.configure_geometry(square.coordinate, projection.get_cell_polygon(square.coordinate))
		square.set_color(get_square_color(square.coordinate.x, square.coordinate.y))
		square.set_surface_visible(not _uses_material_surface())
	for piece in $Pieces.get_children():
		piece.position = grid_to_screen(piece.coordinate.x, piece.coordinate.y)
		piece.scale = Vector2.ONE * get_world_scale()
		_update_piece_depth(piece)

func set_viewing_color(color: String) -> void:
	viewing_color = color if color == "black" else "white"
	_layout_board()

func set_player_hand_style(style: Resource) -> void:
	if is_instance_valid(near_hand_rig):
		near_hand_rig.set_hand_style(style)

func set_hand_styles(near_style: Resource, far_style: Resource) -> void:
	set_player_hand_style(near_style)
	if is_instance_valid(far_hand_rig):
		far_hand_rig.set_hand_style(far_style)

func get_hand_rig_for_color(color: String) -> ChessHandRig:
	return near_hand_rig if color == viewing_color or not is_instance_valid(far_hand_rig) else far_hand_rig

func _get_piece_hand_rig(piece_node: Node) -> ChessHandRig:
	var piece_model: ModelPiece = piece_node.get("model") if piece_node != null else null
	return get_hand_rig_for_color(piece_model.color) if piece_model != null else near_hand_rig

func _sync_piece_grip_anchor_debug() -> void:
	for piece in $Pieces.get_children():
		if piece.has_method("set_grip_anchor_debug_visible"):
			piece.set_grip_anchor_debug_visible(show_piece_grip_anchors)

func _request_layout() -> void:
	if is_node_ready() and not board.is_empty():
		_layout_board()

func _on_visual_style_changed() -> void:
	_sync_hand_board_sounds()
	_request_layout()

func _sync_hand_board_sounds() -> void:
	for hand_rig in [near_hand_rig, far_hand_rig]:
		if is_instance_valid(hand_rig):
			hand_rig.set_board_sound_set(visual_style.interaction_sounds if visual_style != null else null)

func _connect_visual_style() -> void:
	if visual_style != null and not visual_style.changed.is_connected(_on_visual_style_changed):
		visual_style.changed.connect(_on_visual_style_changed)

func _configure_projection() -> void:
	projection.configure(
		get_viewport_rect().size,
		board.size(),
		board[0].size(),
		viewing_color,
		viewport_height_width_ratio,
		viewport_width_cap_ratio,
		projected_depth_ratio,
		far_edge_width_ratio,
		vertical_center_ratio
	)

func _layout_board_body() -> void:
	if board_body != null and visual_style != null:
		board_body.configure(
			projection.get_board_outline(),
			projection.get_presentation_scale(),
			visual_style
		)
	if material_surface != null:
		material_surface.configure(projection, visual_style)

func draw_square(row: int, col: int):
	var squares = $Squares
	var square: SquareView = square_scene.instantiate()
	var square_color = get_square_color(row, col)
	square.set_color(square_color)
	square.set_surface_visible(not _uses_material_surface())
	square.configure_geometry(
		Vector2i(row, col),
		projection.get_cell_polygon(Vector2i(row, col))
	)
	square.connect("square_clicked", _on_square_selected)
	square.editor_pointer_pressed.connect(func(coord: Vector2i): editor_square_pressed.emit(coord))
	square.editor_pointer_entered.connect(func(coord: Vector2i): editor_square_entered.emit(coord))
	square.editor_pointer_exited.connect(func(coord: Vector2i): editor_square_exited.emit(coord))
	square.z_index = -2
	squares.add_child(square)

func _uses_material_surface() -> bool:
	return visual_style != null and bool(visual_style.material_surface_enabled)

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
	piece.set_grip_anchor_debug_visible(show_piece_grip_anchors)
	piece.scale = Vector2.ONE * get_world_scale()
	piece.coordinate = Vector2i(row, col)
	_update_piece_depth(piece)
	pieces.add_child(piece)

	# Does it need an HP bar?
	if piece_data.max_hp > 1:
		var hp_bar = hp_bar_scene.instantiate()
		hp_bar.max_hp = piece_data.max_hp
		hp_bar.current_hp = piece_data.current_hp
		# PieceView's origin is the board-contact point; keep HP just below the base.
		hp_bar.position = Vector2(0, 4)
		piece.add_child(hp_bar)
	return piece

func create_piece_drag_ghost(piece_data: ModelPiece) -> PieceView:
	if piece_data == null:
		return null
	var ghost: PieceView = piece_scene.instantiate()
	ghost.name = "PieceDragGhost"
	ghost.input_pickable = false
	ghost.set_model(piece_data)
	ghost.scale = Vector2.ONE * get_world_scale()
	ghost.modulate.a = 0.55
	ghost.z_index = DRAG_GHOST_Z
	$Pieces.add_child(ghost)
	return ghost

func position_piece_drag_ghost(ghost: PieceView, canvas_position: Vector2) -> void:
	if is_instance_valid(ghost):
		ghost.global_position = canvas_position
					
func get_piece_node(coord: Vector2i) -> Node:
	var desired_piece = null
	
	var piece_nodes = $Pieces.get_children()
	for piece_node in piece_nodes:
		if piece_node.coordinate == coord:
			desired_piece = piece_node
			break
	
	return desired_piece

func get_piece_directly_toward_viewer(coord: Vector2i) -> Node:
	var display_coordinate := projection.get_display_coordinate(coord)
	display_coordinate.x += 1
	if display_coordinate.x >= projection.rows:
		return null
	return get_piece_node(projection.get_model_coordinate(display_coordinate))

## Compatibility wrapper for presentation code that targets a physical piece.
func grid_to_screen(row: int, col: int) -> Vector2:
	return projection.get_piece_ground_anchor(Vector2i(row, col), piece_forward_bias)

func cell_to_screen_center(row: int, col: int) -> Vector2:
	return projection.get_cell_center(Vector2i(row, col))

func get_world_scale() -> float:
	if not scale_world_with_projection:
		return 1.0
	return calculate_world_scale(projection.get_near_edge_width())

static func calculate_world_scale(near_edge_width: float) -> float:
	return maxf(near_edge_width / PIECE_REFERENCE_NEAR_EDGE_WIDTH, 0.01)

func _update_piece_depth(piece_node: Node2D) -> void:
	piece_node.z_index = get_piece_depth(piece_node.coordinate)

func get_piece_depth(coordinate: Vector2i) -> int:
	return projection.get_display_coordinate(coordinate).x * BOARD_DEPTH_STRIDE
			
func get_square_color(row: int, col: int):
	if visual_style == null:
		return Color.WHITE if ((row + col) % 2 == 0) else Color(0.3, 0.3, 0.3)
	if ((row + col) % 2 == 0):
		return visual_style.light_square_color
	return visual_style.dark_square_color

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

func snap_piece_node(piece_node: Node, to: Vector2i) -> void:
	if not is_instance_valid(piece_node):
		return
	piece_node.coordinate = to
	piece_node.position = grid_to_screen(to.x, to.y)
	_update_piece_depth(piece_node)

func move_piece_node_with_player_hand(
	piece_node: Node,
	from: Vector2i,
	to: Vector2i,
	enter_from_offscreen := true,
	retreat_offscreen := true,
	carry_path_override: StringName = &""
) -> void:
	await move_piece_node_with_hand(piece_node, from, to, enter_from_offscreen, retreat_offscreen, carry_path_override)

func move_piece_node_with_hand(
	piece_node: Node,
	from: Vector2i,
	to: Vector2i,
	enter_from_offscreen := true,
	retreat_offscreen := true,
	carry_path_override: StringName = &""
) -> void:
	if not is_instance_valid(piece_node):
		printerr("move_piece_node_with_hand: Invalid piece node.")
		return
	var hand_rig := _get_piece_hand_rig(piece_node)
	if not is_instance_valid(hand_rig) or not hand_rig.can_animate():
		await move_piece_node(piece_node, to)
		return

	piece_node.coordinate = to
	var destination := grid_to_screen(to.x, to.y)
	var destination_z_index := get_piece_depth(to)
	var carry_path := carry_path_override if not carry_path_override.is_empty() else get_player_hand_carry_path(piece_node, from, to)
	await hand_rig.play_piece_move(piece_node, destination, get_world_scale(), carry_path, enter_from_offscreen, retreat_offscreen, destination_z_index)
	_update_piece_depth(piece_node)

func capture_piece_node_with_player_hand(attacker_node: Node, defender_node: Node, from: Vector2i, to: Vector2i) -> bool:
	return await capture_piece_node_with_hand(attacker_node, defender_node, from, to)

func capture_piece_node_with_hand(attacker_node: Node, defender_node: Node, from: Vector2i, to: Vector2i) -> bool:
	if not is_instance_valid(attacker_node) or not is_instance_valid(defender_node):
		return false
	var hand_rig := _get_piece_hand_rig(attacker_node)
	if not is_instance_valid(hand_rig) or not hand_rig.can_animate():
		await move_piece_node(attacker_node, to)
		return false

	attacker_node.coordinate = to
	var destination := grid_to_screen(to.x, to.y)
	var destination_z_index := get_piece_depth(to)
	var carried_offscreen: bool = await hand_rig.play_piece_capture(attacker_node, defender_node, destination, get_world_scale(), destination_z_index)
	_update_piece_depth(attacker_node)
	return carried_offscreen

func get_player_hand_carry_path(piece_node: Node, from: Vector2i, to: Vector2i) -> StringName:
	var piece_model: ModelPiece = piece_node.get("model") if piece_node != null else null
	var piece_type: String = piece_model.type if piece_model != null else ""
	if piece_type == "knight":
		return &"jump"
	if piece_type in ["bishop", "queen"] and not get_player_hand_clearance_blockers(piece_node, from, to).is_empty():
		return &"jump"
	return &"slide"

func get_player_hand_clearance_blockers(piece_node: Node, from: Vector2i, to: Vector2i) -> Array[Node2D]:
	var blockers: Array[Node2D] = []
	var piece_model: ModelPiece = piece_node.get("model") if piece_node != null else null
	var piece_type: String = piece_model.type if piece_model != null else ""
	if piece_type not in ["bishop", "queen"]:
		return blockers
	var delta := to - from
	if delta.x == 0 or absi(delta.x) != absi(delta.y):
		return blockers
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var current := from
	for _step_index in range(absi(delta.x)):
		# Each diagonal step crosses the corner between these two orthogonally
		# adjacent squares. Either occupied flank makes a slide look squeezed.
		for flank in [current + Vector2i(step.x, 0), current + Vector2i(0, step.y)]:
			var blocking_piece := get_piece_node(flank) as Node2D
			if is_instance_valid(blocking_piece) and blocking_piece != piece_node and blocking_piece not in blockers:
				blockers.append(blocking_piece)
		current += step
	return blockers

func attack_piece_node(piece_node: Node, to: Vector2i, contact_callback: Callable = Callable()) -> void:
	if not is_instance_valid(piece_node):
		printerr("attack_piece_node: Invalid piece node.")
		return

	var original_position: Vector2 = piece_node.position
	await _tween_piece_to(piece_node, grid_to_screen(to.x, to.y))
	if contact_callback.is_valid():
		contact_callback.call()
	await _tween_piece_to(piece_node, original_position)

func attack_piece_node_with_player_hand(piece_node: Node, from: Vector2i, to: Vector2i, contact_callback: Callable = Callable()) -> void:
	await attack_piece_node_with_hand(piece_node, from, to, contact_callback)

func attack_piece_node_with_hand(piece_node: Node, from: Vector2i, to: Vector2i, contact_callback: Callable = Callable()) -> void:
	if not is_instance_valid(piece_node):
		printerr("attack_piece_node_with_player_hand: Invalid piece node.")
		return
	var hand_rig := _get_piece_hand_rig(piece_node)
	if not is_instance_valid(hand_rig) or not hand_rig.can_animate():
		await attack_piece_node(piece_node, to, contact_callback)
		return

	await hand_rig.play_piece_attack(piece_node, grid_to_screen(to.x, to.y), get_world_scale(), contact_callback, get_piece_depth(from))
	_update_piece_depth(piece_node)

func _tween_piece_to(piece_node: Node, target_position: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(
		piece_node,
		"position",
		target_position,
		PIECE_MOVE_DURATION * animation_duration_scale
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
	var effect_position: Vector2 = piece.position
	if piece.has_method("get_body_anchor") and piece.has_method("get_anchor_position_in"):
		effect_position = piece.get_anchor_position_in(self, piece.get_body_anchor())
	spawn_explosion(effect_position)
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
	explosion.scale *= get_world_scale()
	explosion.z_index = BOARD_EFFECT_Z
	add_child(explosion)
	
func spawn_splatter(piece_node: Node2D):
	if not is_instance_valid(piece_node):
		return
	var splatter = splatter_scene.instantiate()
	splatter.scale *= get_world_scale()
	if piece_node.has_method("get_body_anchor") and piece_node.has_method("get_anchor_position_in"):
		splatter.position = piece_node.get_anchor_position_in(self, piece_node.get_body_anchor())
	else:
		splatter.position = piece_node.position
	splatter.z_index = BOARD_EFFECT_Z
	add_child(splatter)
	
func spawn_stun_stars(stunned_piece: Node):
	var stun_stars = stun_stars_scene.instantiate()
	if stunned_piece.has_method("get_head_anchor"):
		stunned_piece.get_head_anchor().add_child(stun_stars)
		stun_stars.position = Vector2(0, 4.0)
	else:
		stun_stars.position = Vector2(0, -10)
		stunned_piece.add_child(stun_stars)
	stun_stars.add_to_group("stun")

func spawn_ss_aura(piece: Node):
	var aura = ss_aura_scene.instantiate()
	aura.add_to_group("aura")
	if piece.has_method("get_body_anchor"):
		piece.get_body_anchor().add_child(aura)
	else:
		piece.add_child(aura)
	play_power_activation_sound()

func play_bone_pawn_summon(piece_node: Node2D) -> void:
	if not is_instance_valid(piece_node):
		return
	var sprite := piece_node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	var world_scale := get_world_scale()
	var summon_rise_distance := BONE_PAWN_SUMMON_RISE_DISTANCE * world_scale
	var summon_shake_amplitude := BONE_PAWN_SUMMON_SHAKE_AMPLITUDE * world_scale
	var original_position := piece_node.position
	var target_position := grid_to_screen(piece_node.coordinate.x, piece_node.coordinate.y)
	var original_material := sprite.material
	var reveal_material := ShaderMaterial.new()
	reveal_material.shader = bone_pawn_reveal_shader
	reveal_material.set_shader_parameter("reveal", 0.0)
	sprite.material = reveal_material
	piece_node.position = original_position + Vector2.DOWN * summon_rise_distance

	var portal := bone_pawn_portal_scene.instantiate() as BonePawnSummonPortal
	portal.configure_presentation_scale(world_scale)
	portal.position = target_position
	add_child(portal)
	await portal.open()

	var elapsed := 0.0
	while elapsed < BONE_PAWN_SUMMON_RISE_DURATION and is_instance_valid(piece_node):
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		target_position = grid_to_screen(piece_node.coordinate.x, piece_node.coordinate.y)
		var progress := clampf(elapsed / BONE_PAWN_SUMMON_RISE_DURATION, 0.0, 1.0)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		var shake := sin(progress * TAU * BONE_PAWN_SUMMON_SHAKE_CYCLES)
		shake *= summon_shake_amplitude * (1.0 - progress)
		piece_node.position = target_position + Vector2(
			shake,
			lerpf(summon_rise_distance, 0.0, eased_progress)
		)
		reveal_material.set_shader_parameter("reveal", eased_progress)
		portal.position = target_position
		portal.rotation = sin(progress * TAU * 2.0) * 0.08

	if is_instance_valid(piece_node):
		piece_node.position = grid_to_screen(piece_node.coordinate.x, piece_node.coordinate.y)
		if is_instance_valid(sprite):
			sprite.material = original_material
	if is_instance_valid(portal):
		await portal.close()

	
func remove_stun_stars(coord: Vector2i):
	var stunned_piece = get_piece_node(coord)
	remove_stun_stars_from_piece(stunned_piece)

func remove_stun_stars_from_piece(piece_node: Node):
	for effect in _get_descendant_effects_in_group(piece_node, &"stun"):
		effect.queue_free()

func remove_ss_aura(piece_node: Node):
	for effect in _get_descendant_effects_in_group(piece_node, &"aura"):
		effect.queue_free()

# In chess_board.gd (your view class)
func fade_out_ss_aura(piece_node: Node, include_powerdown: bool = true):
	if include_powerdown: play_power_deactivation_sound()
	
	for child in _get_descendant_effects_in_group(piece_node, &"aura"):
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

func _get_descendant_effects_in_group(root: Node, group: StringName) -> Array[Node]:
	var matches: Array[Node] = []
	if not is_instance_valid(root):
		return matches
	for child in root.get_children():
		if child.is_in_group(group):
			matches.append(child)
		matches.append_array(_get_descendant_effects_in_group(child, group))
	return matches

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
		var pos = cell_to_screen_center(coord.x, coord.y)
		spawn_explosion(pos)

func start_minotaur_rage_intro(minotaur_node: Node) -> void:
	if not is_instance_valid(minotaur_node):
		printerr("start_minotaur_rage_intro: Invalid Minotaur view node.")
		rage_intro_animation_completed.emit()
		return

	var original_scale = minotaur_node.scale
	var tween = create_tween()
	tween.tween_property(minotaur_node, "scale", original_scale * 1.25, 1.0 * animation_duration_scale).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_interval(0.15 * animation_duration_scale)
	tween.tween_property(minotaur_node, "scale", original_scale, 0.1 * animation_duration_scale)
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
