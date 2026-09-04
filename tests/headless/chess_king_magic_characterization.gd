extends Node

const GAME := preload("res://scenes/chess_game.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var game := GAME.instantiate() as ChessGame
	game.play_opening_presentation = false
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	game.opponent_presentation = preload("res://assets/opponent_army_presentation.tres")
	viewport.add_child(game)
	await get_tree().process_frame
	var model: ChessBoardModel = game.model
	var adapter: ChessPresentationAdapter = game.get_node("ChessPresentationAdapter")
	var view: ChessBoardView = game.get_node("CanvasLayer/ChessBoard")
	var white_king: KingPiece = model.get_king("white")
	var black_king: KingPiece = model.get_king("black")
	var white_magic: ChessKingMagicController = adapter.king_magic_controllers[white_king]
	var black_magic: ChessKingMagicController = adapter.king_magic_controllers[black_king]
	_make_fast(white_magic)
	_make_fast(black_magic)

	_check(white_magic.hand.seat == ChessHandRig.Seat.NEAR and black_magic.hand.seat == ChessHandRig.Seat.FAR, "army magic resolves the hand rig for each displayed seat")
	var authored := Vector2(150, -180)
	_check(ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.NEAR) == authored and ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.FAR) == Vector2(-150, -180), "far hover mirrors horizontally while preserving screen-up elevation")
	_check(ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.NEAR, true) == Vector2(-150, -180) and ChessPresentationTransform.king_hover_offset(authored, ChessHandRig.Seat.FAR, true) == Vector2(150, -180), "left-hand activation combines hand mirroring with the far-seat horizontal reflection")

	var grabbed_kings: Array[Node2D] = []
	view.near_hand_rig.piece_grabbed.connect(func(piece: Node2D):
		if piece.model is KingPiece: grabbed_kings.append(piece))
	var white_view := adapter.get_piece_view(white_king) as PieceView
	var destination := Vector2i(5, 4)
	var command_observation := {"count": 0, "king_position": Vector2.INF, "hand_aura": 0.0, "rear_finger_z": 0}
	white_magic.hand_command_reached.connect(func():
		command_observation.count += 1
		command_observation.king_position = white_view.position
		command_observation.hand_aura = white_magic.hand_aura.silhouette_power
		command_observation.rear_finger_z = white_magic.hand.grip_back_sprite.z_index
	, CONNECT_ONE_SHOT)
	var release_observation := {"count": 0, "king_position": Vector2.INF}
	white_magic.king_move_released.connect(func():
		release_observation.count += 1
		release_observation.king_position = white_view.position
	, CONNECT_ONE_SHOT)
	var move_origin := white_view.position
	await white_magic.play_move(white_king.coordinate, destination)
	_check(command_observation.count == 1, "unified hand tween emits one spatial command-boundary event")
	_check(release_observation.count == 1 and release_observation.king_position == move_origin, "tunable delay releases King travel once, measured from swipe launch")
	_check(command_observation.hand_aura > 0.0 and is_zero_approx(white_magic.hand_aura.silhouette_power), "hand aura remains present at the curve boundary and fades away through retreat")
	_check(command_observation.rear_finger_z == ChessHandRig.MAGIC_GRIP_BACK_Z and white_magic.hand.grip_back_sprite.z_index == ChessHandRig.GRIP_BACK_Z, "magical gesture promotes the whole hand through its root stack and restores normal absolute child depths afterward")
	_check(grabbed_kings.is_empty() and white_view.get_parent() == view.get_node("Pieces"), "magical movement never reparents or grasps the king")
	_check(white_view.coordinate == destination and white_view.position == view.grid_to_screen(destination.x, destination.y), "magical movement settles on the exact projected ground anchor")

	var defender := adapter.get_piece_view(model.board[1][0]) as PieceView
	var defender_start := defender.position
	white_view.position = view.grid_to_screen(4, 0)
	var impact_observation := {"count": 0, "defender_position": Vector2.INF, "king_z": 0, "defender_z": 0}
	white_magic.capture_impact.connect(func(hit: PieceView):
		impact_observation.count += 1
		impact_observation.defender_position = hit.position
		impact_observation.king_z = white_view.z_index
		impact_observation.defender_z = hit.z_index
	, CONNECT_ONE_SHOT)
	await white_magic.play_capture(Vector2i(4, 0), Vector2i(3, 1), defender)
	_check(impact_observation.count == 1 and impact_observation.defender_position == defender_start, "captured piece remains planted until the King reaches its impact point")
	_check(impact_observation.king_z > impact_observation.defender_z, "King approaching from screen-below renders above the attacked knockoff piece")
	var defender_radius := ChessKingMagicController.piece_visual_radius(defender)
	var defender_offscreen := defender.position.x - defender_radius >= view.get_viewport_rect().size.x or defender.position.x + defender_radius <= 0.0 or defender.position.y - defender_radius >= view.get_viewport_rect().size.y or defender.position.y + defender_radius <= 0.0
	_check(defender_offscreen and defender.rotation > 0.0, "rightward king impact spins the defender until its complete visual bound leaves the viewport")
	defender.position = defender_start
	defender.rotation = 0.0
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 44
	var first := ChessKingMagicController.knockoff_side(Vector2.ZERO, Vector2(0, 100), seeded)
	seeded.seed = 44
	_check(first in [-1, 1] and first == ChessKingMagicController.knockoff_side(Vector2.ZERO, Vector2(0, 100), seeded), "direct vertical impacts choose a seedable random left/right arc")
	var above_depths := ChessKingMagicController.capture_collision_depths(Vector2(100, 50), Vector2(100, 100))
	_check(above_depths.king < above_depths.defender, "King approaching from screen-above preserves the defender-over-King impact stack")
	seeded.seed = 44
	var ballistic := ChessKingMagicController.build_ballistic_knockoff(Vector2(100, 300), Vector2(200, 300), Vector2(200, 300), Vector2(960, 540), 40.0, 650.0, 480.0, 1200.0, seeded)
	var initial_velocity: Vector2 = ballistic.initial_velocity
	var apex_time := -initial_velocity.y / float(ballistic.gravity)
	var before_apex := ChessKingMagicController.ballistic_position(Vector2(200, 300), initial_velocity, ballistic.gravity, apex_time * 0.5)
	var apex := ChessKingMagicController.ballistic_position(Vector2(200, 300), initial_velocity, ballistic.gravity, apex_time)
	var after_apex := ChessKingMagicController.ballistic_position(Vector2(200, 300), initial_velocity, ballistic.gravity, apex_time * 1.5)
	_check(initial_velocity.y < 0.0 and apex.y < before_apex.y and apex.y < after_apex.y, "ballistic knockoff decelerates upward to an apex and accelerates downward afterward")
	var ballistic_end: Vector2 = ballistic.target
	_check(ballistic_end.x - 40.0 >= 960.0 or ballistic_end.x + 40.0 <= 0.0 or ballistic_end.y - 40.0 >= 540.0 or ballistic_end.y + 40.0 <= 0.0, "ballistic knockoff continues until the complete visual radius is offscreen")
	var gesture := ChessKingMagicController.gesture_points(Vector2.ZERO, Vector2(200, 0), Vector2(40, 10), 96.0, 72.0)
	var longer_gesture := ChessKingMagicController.gesture_points(Vector2.ZERO, Vector2(200, 0), Vector2(40, 10), 96.0, 120.0)
	var diagonal_gesture := ChessKingMagicController.gesture_points(Vector2.ZERO, Vector2(200, 200), Vector2(40, 10), 96.0, 72.0)
	_check(gesture[0] == Vector2(40, 10) and is_equal_approx(gesture[1].x - gesture[0].x, 72.0), "directional gesture begins at the authored hover and sweeps along the move direction")
	_check(diagonal_gesture[0] == gesture[0], "all eight gesture directions share one fixed initial lock position")
	_check(longer_gesture[0].is_equal_approx(gesture[0]) and is_equal_approx(longer_gesture[1].x - longer_gesture[0].x, 120.0), "swipe length moves only the endpoint and preserves the initial hand lock position")
	var unified_path := ChessKingMagicController.build_gesture_path(gesture[0], gesture[1], Vector2(900, 700), 110.0)
	ChessKingMagicController.build_path_timing(unified_path, 2.0, 0.35, 2.0)
	var unified_points: PackedVector2Array = unified_path.points
	var join_index: int = unified_path.join_index
	var incoming := (unified_points[join_index] - unified_points[join_index - 1]).normalized()
	var start_radial: Vector2 = (unified_points[join_index] - Vector2(unified_path.turn_center)).normalized()
	var exact_outgoing := Vector2(-start_radial.y, start_radial.x) * float(unified_path.turn_sign)
	_check(absf(incoming.cross(exact_outgoing)) < 0.001, "unified hand path preserves its exact swipe tangent as the retreat curve begins")
	var turn_end_index: int = unified_path.turn_end_index
	var end_radial: Vector2 = (unified_points[turn_end_index] - Vector2(unified_path.turn_center)).normalized()
	var arc_exit := Vector2(-end_radial.y, end_radial.x) * float(unified_path.turn_sign)
	var home_line := (unified_points[turn_end_index + 1] - unified_points[turn_end_index]).normalized()
	_check(absf(arc_exit.cross(home_line)) < 0.001, "bounded-radius arc exits tangent to its final route home")
	var radius_is_stable := true
	for index in range(join_index, turn_end_index + 1):
		radius_is_stable = radius_is_stable and is_equal_approx(unified_points[index].distance_to(Vector2(unified_path.turn_center)), float(unified_path.effective_radius))
	_check(radius_is_stable, "every sampled turning-arc point respects the effective minimum radius")
	var huge_radius_path := ChessKingMagicController.build_gesture_path(gesture[0], gesture[1], Vector2(300, 180), 10000.0)
	_check(float(huge_radius_path.effective_radius) < gesture[1].distance_to(Vector2(300, 180)) * 0.5 and Vector2(huge_radius_path.points[-1]).is_equal_approx(Vector2(300, 180)), "oversized turn radii clamp safely and still finish exactly at hand home")
	var lengths: PackedFloat32Array = unified_path.cumulative_lengths
	var times: PackedFloat32Array = unified_path.cumulative_times
	var launch_rate: float = (lengths[1] - lengths[0]) / (times[1] - times[0])
	var turn_in_rate: float = (lengths[join_index] - lengths[join_index - 1]) / (times[join_index] - times[join_index - 1])
	var turn_out_rate: float = (lengths[join_index + 1] - lengths[join_index]) / (times[join_index + 1] - times[join_index])
	var exit_rate: float = (lengths[-1] - lengths[-2]) / (times[-1] - times[-2])
	_check(turn_in_rate < launch_rate and turn_out_rate < exit_rate, "unified timing decelerates to its slowest region at the curve boundary and accelerates away")

	var attack_origin := white_view.position
	var attack_observation := {"contacts": 0}
	await white_magic.play_attack(Vector2i(3, 1), Vector2i(2, 2), func(): attack_observation["contacts"] += 1)
	_check(attack_observation["contacts"] == 1, "nonlethal magical lunge applies one contact callback")
	_check(white_view.position.is_equal_approx(attack_origin), "nonlethal magical lunge rebounds exactly home")

	_make_activation_fast(black_magic)
	await black_magic.play_activation()
	_check(not black_magic.hand.visible and black_magic.hand.position == black_magic.activation_sequence.hand_rest_position, "far-seat full activation uses its transformed hover and returns offscreen")
	_check(is_equal_approx(black_magic.king_aura.silhouette_power, black_magic.profile.activation_profile.resting_aura_power), "full activation retains the configured resting king silhouette")
	_check(black_magic.activation_sequence.get_script().resource_path == "res://scripts/view/chess_hood_activation_sequence.gd", "opponent army identity selects the Hood decisive choreography independent of King type")

	var lethal_profile := preload("res://scripts/view/chess_king_death_profile.gd").new()
	lethal_profile.death_sound = null
	lethal_profile.red_blink_count = 1
	lethal_profile.blink_on_duration = 0.01
	lethal_profile.blink_off_duration = 0.01
	lethal_profile.stone_hold_duration = 0.01
	lethal_profile.stone_fade_duration = 0.04
	lethal_profile.rift_speed = 10000.0
	black_magic.profile.death_profile = lethal_profile
	var lethal_attacker: ModelPiece = model.board[7][0]
	var lethal_attacker_view := adapter.get_piece_view(lethal_attacker) as PieceView
	var lethal_origin := lethal_attacker_view.position
	view.near_hand_rig.animation_duration_scale = 0.02
	var lethal_gate := CompletionGate.new()
	await adapter._on_piece_capture_committed(lethal_attacker, black_king, lethal_attacker.coordinate, black_king.coordinate, black_king.coordinate, lethal_gate)
	_check(lethal_attacker_view.position.is_equal_approx(lethal_origin), "lethal King capture reuses the long-range attack slam and returns the attacker to its original square")

	var death_piece := preload("res://scenes/piece.tscn").instantiate() as PieceView
	death_piece.set_model(ClassicKing.new("black", Vector2i.ZERO))
	death_piece.position = Vector2(400, 260)
	view.add_child(death_piece)
	var death_profile := preload("res://scripts/view/chess_king_death_profile.gd").new()
	death_profile.death_sound = null
	death_profile.red_blink_count = 1
	death_profile.blink_on_duration = 0.01
	death_profile.blink_off_duration = 0.01
	death_profile.stone_hold_duration = 0.01
	death_profile.stone_fade_duration = 0.04
	death_profile.rift_speed = 10000.0
	var death_effect := view.create_king_death_effect(death_piece, death_profile)
	death_effect.play()
	await get_tree().create_timer(0.035).timeout
	_check(death_effect.rift_circles.size() == 8, "King death emits exactly eight radial rift circles")
	_check((death_effect.rift_circles[0].material as ShaderMaterial).shader.resource_path == "res://effects/chess_lightning_rift.gdshader", "King death circles reveal the stationary chessboard-rift pattern")
	var endpoints_offscreen := true
	for index in range(8):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
		var distance: float = death_effect._distance_to_viewport_exit(death_effect.global_position, direction, death_profile.rift_radius * 2.0)
		var endpoint: Vector2 = death_effect.global_position + direction * distance
		endpoints_offscreen = endpoints_offscreen and (endpoint.x < 0.0 or endpoint.x > viewport.size.x or endpoint.y < 0.0 or endpoint.y > viewport.size.y)
	_check(endpoints_offscreen, "every constant-speed death circle targets a point fully beyond the viewport")
	if not death_effect.finished: await death_effect.completed
	await get_tree().process_frame
	_check(not is_instance_valid(death_piece), "King view survives the blink and stone transition, then leaves with the completed death effect")

	viewport.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("CHESS KING MAGIC CHARACTERIZATION: PASS (%d checks)" % checks)
	else:
		print("CHESS KING MAGIC CHARACTERIZATION: FAIL (%d failures)" % failures.size())
		for failure in failures: print(" - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _make_fast(magic: ChessKingMagicController) -> void:
	magic.profile = magic.profile.duplicate(true)
	var move: Resource = magic.profile.movement_profile
	for property in ["hand_approach_duration", "gesture_duration", "king_move_delay", "settle_duration", "travel_duration", "attack_rebound_duration", "knockoff_duration"]:
		move.set(property, 0.01)
	move.knockoff_horizontal_speed = 100000.0
	move.knockoff_upward_speed = 0.0
	move.knockoff_gravity = 1.0


func _make_activation_fast(magic: ChessKingMagicController) -> void:
	var activation: Resource = magic.profile.activation_profile
	for property in ["approach_duration", "approach_settle_duration", "invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "resolve_duration", "climax_hand_return_duration", "post_climax_retreat_delay", "retreat_duration"]:
		activation.set(property, 0.01)
	activation.buildup_crackle_times = PackedFloat32Array()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
