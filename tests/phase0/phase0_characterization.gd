extends Node

## Phase 0 behavior characterization.
##
## These tests deliberately exercise the current, fully composed battle scene.
## They document existing coupling as well as gameplay behavior; they are not a
## headless Model harness. A later phase must make the same rule flows available
## without constructing ChessBoardView or ChessBoardController.

const CHESS_GAME_SCENE := preload("res://scenes/chess_game.tscn")
const HOOD_HAND_STYLE := preload("res://assets/arms/opponent/hood_hand_style.tres")

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	await _run_suite()

	if _failures.is_empty():
		print("PHASE 0 CHARACTERIZATION: PASS (", _checks, " checks)")
		get_tree().quit(0)
		return

	printerr("PHASE 0 CHARACTERIZATION: FAIL (", _failures.size(), " failures)")
	for failure in _failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _run_suite() -> void:
	await _test_default_initialization_and_normal_move()
	await _test_player_hand_move_presentation()
	await _test_player_hand_castling_presentation()
	await _test_player_hand_capture_presentation()
	await _test_surrounded_knight_depth_presentation()
	await _test_ai_configuration_and_turns()
	await _test_black_view_hand_presentation()
	await _test_nonlethal_attack_presentation()
	await _test_arakne_spike_burst()
	await _test_minotaur_charge_survivor_landing()
	await _test_minotaur_rage_barrier()
	await _test_active_bone_pawn_summon_presentation()
	await _test_rage_raise_dead_death_square_target()
	await _test_terminal_rank_raise_dead_expiration()
	await _test_rage_priority_before_raise_dead()
	await _test_raise_dead_selection_resume()
	await _test_battle_completion()


func _test_player_hand_move_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var view: ChessBoardView = context.view
	var rig: Node2D = view.get_node("NearHandRig")
	var piece_slot: Node2D = rig.get_node("PieceSlot")
	var grip_back: Sprite2D = rig.get_node("GripBack")
	var grip_front: Sprite2D = rig.get_node("GripFront")
	var arm_foreground: Sprite2D = rig.get_node("ArmForeground")
	var sound_set := _make_test_hand_sound_set()
	var board_sound_set := _make_test_board_sound_set()
	var test_hand_style: ChessHandStyle = rig.hand_style.duplicate()
	test_hand_style.sounds = sound_set
	rig.set_hand_style(test_hand_style)
	rig.set_board_sound_set(board_sound_set)
	rig.approach_duration = 0.01
	rig.grasp_hold_duration = 0.01
	rig.carry_duration = 0.01
	rig.release_hold_duration = 0.01
	rig.retreat_duration = 0.01

	var pawn: ModelPiece = model.board[6][0]
	var pawn_view: Node2D = context.adapter.get_piece_view(pawn)
	var nearer_rook_view: Node2D = context.adapter.get_piece_view(model.board[7][0])
	var unrelated_nearer_piece: Node2D = context.adapter.get_piece_view(model.board[7][1])
	_expect(view.get_piece_directly_toward_viewer(Vector2i(6, 0)) == nearer_rook_view, "White perspective identifies only the same-file piece one displayed row nearer")
	var nearer_rook_original_z := nearer_rook_view.z_index
	var unrelated_nearer_original_z := unrelated_nearer_piece.z_index
	rig._set_grounded_depth(pawn_view.z_index)
	_expect(grip_front.z_index < nearer_rook_view.z_index and nearer_rook_view.z_index < arm_foreground.z_index, "grounded Skeleton thumb sits below the naturally nearer piece while its foreground arm remains above")
	_expect(nearer_rook_view.z_index == nearer_rook_original_z and unrelated_nearer_piece.z_index == unrelated_nearer_original_z, "grounding the hand never changes stationary board-piece depths")
	rig._set_elevated_depth()
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][1]), Vector2i(7, 1), Vector2i(5, 2)) == &"jump", "knights always use the jump carry path")
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][0]), Vector2i(7, 0), Vector2i(5, 0)) == &"slide", "two-square rook movement retains the slide carry path")
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][0]), Vector2i(7, 0), Vector2i(4, 0)) == &"slide", "straight sliders can slide at any distance")
	var bishop_view: Node2D = context.adapter.get_piece_view(model.board[7][2])
	var bishop_clearance_blockers := view.get_player_hand_clearance_blockers(bishop_view, Vector2i(7, 2), Vector2i(6, 3))
	_expect(view.get_player_hand_carry_path(bishop_view, Vector2i(7, 2), Vector2i(6, 3)) == &"jump", "a one-square bishop move jumps when its two corner-adjacent squares form a squeezed passage")
	_expect(context.adapter.get_piece_view(model.board[7][3]) in bishop_clearance_blockers and context.adapter.get_piece_view(model.board[6][2]) in bishop_clearance_blockers, "diagonal clearance identifies both the adjacent queen and pawn as jump obstacles")
	_expect(context.adapter.get_piece_view(model.board[7][3]).z_index == view.get_piece_depth(Vector2i(7, 3)), "bishop jump selection does not alter the adjacent queen's board depth")
	_expect(view.get_player_hand_carry_path(bishop_view, Vector2i(4, 3), Vector2i(2, 5)) == &"slide", "a bishop can slide diagonally at any distance when every crossed corner is clear")
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][3]), Vector2i(7, 3), Vector2i(4, 6)) == &"jump", "a diagonally moving queen uses the same squeezed-corner rule as a bishop")
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][3]), Vector2i(4, 3), Vector2i(2, 5)) == &"slide", "a diagonally moving queen slides through a clear corridor")
	_expect(view.get_player_hand_carry_path(context.adapter.get_piece_view(model.board[7][4]), Vector2i(7, 4), Vector2i(4, 4)) == &"slide", "kings retain the slide carry path")
	var expected_grip_position := view.to_local(pawn_view.get_grip_anchor().global_position)
	var observations: Array[String] = []
	var carry_paths: Array[StringName] = []
	rig.pose_changed.connect(func(pose: StringName): observations.append(String(pose)))
	rig.carry_path_started.connect(func(path: StringName): carry_paths.append(path))
	rig.piece_grabbed.connect(
		func(piece: Node2D):
			observations.append("grabbed")
			_expect(piece == pawn_view and piece.get_parent() == piece_slot, "player hand sandwiches the grabbed piece in its carry slot")
			_expect(not grip_back.z_as_relative and not piece_slot.z_as_relative and not grip_front.z_as_relative, "grounded hand layers use explicit row-band depths")
			_expect(rig.position.is_equal_approx(expected_grip_position), "player hand aligns its grip to the piece head anchor plus the configured offset")
			_expect(nearer_rook_view.z_index > grip_front.z_index, "the direct lower piece continues to occlude the closed front grip after the grab clicks into place")
			_expect(not arm_foreground.z_as_relative and arm_foreground.z_index > nearer_rook_view.z_index, "the foreground arm remains above the naturally nearer piece")
	)
	rig.piece_released.connect(
		func(piece: Node2D):
			observations.append("released")
			_expect(piece.get_parent() == view.get_node("Pieces"), "player hand restores the released piece to the board piece layer")
			_expect(piece.z_index == view.get_piece_depth(Vector2i(4, 0)) and nearer_rook_view.z_index == nearer_rook_original_z, "placed piece assumes destination depth while every stationary piece retains natural depth")
			_expect(rig.get_node("PlaceSound").stream == board_sound_set.default_place and rig.get_node("ReleaseSound").stream == null, "placement sounds at board contact before the hand releases")
	)
	rig.move_animation_finished.connect(func(): observations.append("finished"))

	controller.select_piece(pawn)
	await controller._on_square_clicked(Vector2i(4, 0))

	_expect(observations == ["open", "grabbed", "closed", "open", "released", "finished"], "player hand uses the open-grab-close-carry-open-release sequence")
	_expect(nearer_rook_view.z_index == nearer_rook_original_z and unrelated_nearer_piece.z_index == unrelated_nearer_original_z, "stationary depths remain unchanged through the complete hand visit")
	_expect(carry_paths == [&"slide"], "two-square pawn movement retains the sliding carry path")
	_expect(rig.calculate_jump_position(Vector2.ZERO, Vector2(100, 40), 0.0, 32.0) == Vector2.ZERO, "jump arc begins at the exact grip position")
	_expect(rig.calculate_jump_position(Vector2.ZERO, Vector2(100, 40), 0.5, 32.0) == Vector2(50, -12), "jump arc reaches its configured height above the straight midpoint")
	_expect(rig.calculate_jump_position(Vector2.ZERO, Vector2(100, 40), 1.0, 32.0) == Vector2(100, 40), "jump arc ends at the exact destination")
	var approach_start := Vector2(200, 200)
	var approach_destination := Vector2(50, 50)
	var departure_control: Vector2 = approach_start.lerp(approach_destination, rig.approach_departure_progress) + Vector2.UP * rig.approach_departure_lift
	var arrival_control: Vector2 = approach_destination + rig.approach_arrival_handle
	_expect(rig.calculate_bezier_position(approach_start, departure_control, arrival_control, approach_destination, 0.0) == approach_start, "approach Bezier begins at the exact off-board rest point")
	_expect(rig.calculate_bezier_position(approach_start, departure_control, arrival_control, approach_destination, 1.0) == approach_destination, "approach Bezier ends at the exact grip position")
	_expect(rig.approach_arrival_handle.y < 0.0 and rig.calculate_bezier_position(approach_start, departure_control, arrival_control, approach_destination, 0.9).y < approach_destination.y, "approach Bezier reaches the piece from above by default")
	_expect(rig.approach_path_debug.get_parent() == view and not rig.show_approach_path_debug, "approach path preview is reparented into board space and disabled by default")
	_expect(grip_back.z_index < piece_slot.z_index and piece_slot.z_index < rig.get_node("CapturedPiecePivot").z_index and rig.get_node("CapturedPiecePivot").z_index < grip_front.z_index, "active interaction stack orders back grip, attacker, captured defender, and front grip")
	_expect(grip_back.texture.resource_path.ends_with("skeleton_open_rear_fingers.png"), "released hand displays the open back-grip artwork")
	_expect(grip_front.texture.resource_path.ends_with("skeleton_open_thumb.png"), "released hand displays the open front-grip artwork")
	_expect(arm_foreground.texture.resource_path.ends_with("skeleton_open_arm.png"), "released hand displays the open foreground-arm artwork")
	_expect(rig.get_node("GrabSound").stream == sound_set.grab, "ordinary movement plays its grab sound")
	_expect(rig.get_node("PlaceSound").stream == board_sound_set.default_place, "ordinary movement plays the board's default placement sound")
	_expect(rig.get_node("ReleaseSound").stream == sound_set.release, "ordinary movement plays its release sound")
	_expect(rig.get_node("CapturePickupSound").stream == null, "ordinary movement does not play a capture pickup sound")
	_expect(rig.get_node("SlideSound").stream == board_sound_set.default_slide, "sliding movement uses the board's default slide sound")
	_expect(rig.get_node("GrabSound").bus == &"SFX" and is_equal_approx(rig.get_node("GrabSound").volume_db, sound_set.grab_volume_db), "grab sounds use the SFX bus and their independently configured volume")
	_expect(rig.get_node("ReleaseSound").bus == &"SFX" and is_equal_approx(rig.get_node("ReleaseSound").volume_db, sound_set.release_volume_db), "release sounds use the SFX bus and their independently configured volume")
	_expect(rig.get_node("GrabSound").pitch_scale >= 0.92 and rig.get_node("GrabSound").pitch_scale <= 1.08, "hand sound pitch stays inside its configured variation")
	var expected_rest_position: Vector2 = rig._offscreen_rest_position(view.get_world_scale() * rig.art_scale_multiplier)
	_expect(not rig.visible and not rig.is_animating and rig.position.is_equal_approx(expected_rest_position), "player hand retreats to its durable lower-right rest position")
	_expect(rig.position.x > rig.get_viewport_rect().size.x and rig.position.y > rig.get_viewport_rect().size.y, "player hand rests fully beyond the viewport's right and bottom edges")
	_expect(pawn_view.position == view.grid_to_screen(4, 0) and pawn_view.coordinate == Vector2i(4, 0), "hand-carried piece lands exactly on its projected destination")
	_expect(model.current_turn == "black" and not model.action_in_progress, "hand animation completes before the player move changes turns")

	await _destroy_game(context.game)


func _test_player_hand_castling_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var view: ChessBoardView = context.view
	var rig: ChessHandRig = view.player_hand_rig
	var king := ClassicKing.new("white", Vector2i(7, 4))
	var rook := Rook.new("white", Vector2i(7, 7))
	_reset_battle(model, controller, [king, rook])
	rig.approach_duration = 0.01
	rig.grasp_hold_duration = 0.01
	rig.carry_duration = 0.01
	rig.jump_carry_duration = 0.01
	rig.release_hold_duration = 0.01
	rig.retreat_duration = 0.01

	var moved_types: Array[String] = []
	var carry_paths: Array[StringName] = []
	var observation := {"visible_after_king_release": false, "completion_count": 0}
	model.piece_move_committed.connect(func(piece: ModelPiece, _from: Vector2i, _to: Vector2i, _gate: CompletionGate): moved_types.append(piece.type))
	rig.carry_path_started.connect(func(path: StringName): carry_paths.append(path))
	rig.piece_released.connect(
		func(piece_node: Node2D):
			if piece_node.model == king:
				observation["visible_after_king_release"] = rig.visible
	)
	rig.move_animation_finished.connect(func(): observation["completion_count"] += 1)

	controller.select_piece(king)
	await controller._on_square_clicked(Vector2i(7, 6))

	_expect(moved_types == ["king", "rook"], "castling presents the king before the rook")
	_expect(carry_paths == [&"slide"], "castling moves the king magically and hand-carries only the rook")
	_expect(not observation["visible_after_king_release"] and observation["completion_count"] == 1, "castling never attaches the king to the hand rig")
	_expect(rig.position.is_equal_approx(rig._offscreen_rest_position(view.get_world_scale() * rig.art_scale_multiplier)), "castling retreats after the magical king gesture and ordinary rook move")
	_expect(model.board[7][6] == king and model.board[7][5] == rook, "magical castling lands both pieces on their final squares")

	await _destroy_game(context.game)


func _test_player_hand_capture_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var rig: Node2D = context.view.get_node("NearHandRig")
	var sound_set := _make_test_hand_sound_set()
	var board_sound_set := _make_test_board_sound_set()
	var test_hand_style: ChessHandStyle = rig.hand_style.duplicate()
	test_hand_style.sounds = sound_set
	rig.set_hand_style(test_hand_style)
	rig.set_board_sound_set(board_sound_set)
	for property_name in ["approach_duration", "grasp_hold_duration", "capture_approach_duration", "capture_swipe_duration", "capture_placement_duration", "release_hold_duration", "retreat_duration"]:
		rig.set(property_name, 0.01)

	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(5, 0))
	_reset_battle(model, controller, [rook, bishop])
	var bishop_view: Node2D = context.adapter.get_piece_view(bishop)
	var observation := {"hand_completions": 0, "grips_aligned": false, "defender_occluded": false, "thumb_above_pre_swipe_defender": false}
	var capture_stages: Array[StringName] = []
	var capture_poses: Array[StringName] = []
	var removal_timeline: Array[String] = []
	rig.pose_changed.connect(func(pose: StringName): capture_poses.append(pose))
	rig.move_animation_finished.connect(
		func():
			observation["hand_completions"] += 1
			removal_timeline.append("hand_finished")
	)
	model.piece_destroyed.connect(
		func(piece: ModelPiece):
			if piece == bishop:
				removal_timeline.append("defender_destroyed")
	)
	rig.piece_grabbed.connect(
		func(piece: Node2D):
			if piece.model == rook:
				observation["defender_occluded"] = bishop_view.z_index > rig.get_node("GripFront").z_index and bishop_view.z_index < rig.get_node("ArmForeground").z_index
	)
	rig.capture_stage_changed.connect(
		func(stage: StringName):
			capture_stages.append(stage)
			if stage == &"swipe":
				observation["thumb_above_pre_swipe_defender"] = rig.get_node("GripFront").z_index > bishop_view.z_index
			if stage == &"exit":
				_expect(bishop_view.get_parent() == rig.get_node("CapturedPiecePivot"), "captured piece remains attached while the hand exits")
				_expect(
				rig.get_node("ArmForeground").texture == test_hand_style.closed_arm_foreground
				and rig.get_node("GripBack").texture == test_hand_style.closed_grip_back
				and rig.get_node("GripFront").texture == test_hand_style.closed_grip_front,
					"capture withdrawal keeps all three hand layers in the closed pose"
				)
				var moving_view: Node2D = context.adapter.get_piece_view(rook)
				_expect(moving_view.get_parent() == context.view.get_node("Pieces") and moving_view.position == context.view.grid_to_screen(5, 0), "attacker is released onto the board before the closed hand withdraws")
	)
	rig.captured_piece_grabbed.connect(
		func(piece: Node2D):
			var moving_view: Node2D = context.adapter.get_piece_view(rook)
			observation["grips_aligned"] = piece.get_grip_anchor().global_position.is_equal_approx(moving_view.get_grip_anchor().global_position)
			observation["clack_vfx"] = _count_children_named(context.view, &"CaptureClackEffect") == 1
			_expect(rig.get_node("CapturePickupSound").stream == board_sound_set.default_capture_pickup, "the board's default capture pickup sounds at the instant the defender attaches")
			_expect(piece.get_parent() == rig.get_node("CapturedPiecePivot"), "captured piece is attached to its hand-rig pivot")
			_expect(rig.get_node("CapturedPiecePivot").z_index > rig.get_node("PieceSlot").z_index, "captured piece renders in front of the attacking piece")
			_expect(rig.depth_state == ChessHandRig.DepthState.GROUNDED, "capture swipe holds the layered rig in the defender's grounded row band")
	)

	controller.select_piece(rook)
	await controller._on_square_clicked(bishop.coordinate)
	await get_tree().process_frame

	var rook_view: Node2D = context.adapter.get_piece_view(rook)
	_expect(observation["hand_completions"] == 1, "player lethal capture reuses one ordinary hand-carry sequence")
	_expect(rig.position.is_equal_approx(rig._offscreen_rest_position(context.view.get_world_scale() * rig.art_scale_multiplier)), "capture retreats to the shared lower-right hand rest position")
	_expect(rig.get_node("GrabSound").stream == sound_set.grab and rig.get_node("PlaceSound").stream == board_sound_set.default_place and rig.get_node("ReleaseSound").stream == sound_set.release, "captures combine race-specific hand sounds with the board's default placement sound")
	_expect(rig.get_node("SlideSound").stream == null, "jumping capture movement does not play a slide sound")
	_expect(capture_stages == [&"initiation", &"swipe", &"placement", &"exit"], "player capture runs initiation, swipe, placement, and exit in order")
	_expect(capture_poses == [&"open", &"closed"], "player capture opens for approach, closes on pickup, and stays closed through withdrawal")
	_expect(observation["defender_occluded"], "a defender directly below the attacker retains natural occlusion during the initial attacker pickup")
	_expect(observation["thumb_above_pre_swipe_defender"], "near thumb settles above the waiting defender before the capture swipe begins")
	_expect(observation["grips_aligned"], "capture swipe stacks attacker and defender grip anchors at pickup")
	_expect(observation.get("clack_vfx", false), "ordinary capture pickup emits the shared clack burst without duplicating its existing sound")
	_expect(is_equal_approx(rad_to_deg(rig.get_node("CapturedPiecePivot").rotation), rig.captured_piece_rotation_degrees), "captured piece finishes at its configured carry angle")
	_expect(model.board[5][0] == rook and rook_view.position == context.view.grid_to_screen(5, 0), "hand-carried attacker occupies the captured piece's square")
	_expect(removal_timeline == ["hand_finished", "defender_destroyed"], "captured defender is destroyed only after the hand retreats offscreen")
	_expect(context.adapter.get_piece_view(bishop) == null and not is_instance_valid(bishop_view), "captured defender is silently removed after leaving the viewport")
	_expect(_count_children_named(context.view, &"Explosion") == 0, "hand-carried defender does not spawn a capture explosion")

	await _destroy_game(context.game)


func _test_surrounded_knight_depth_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var view: ChessBoardView = context.view
	var rig: ChessHandRig = view.near_hand_rig
	for property_name in ["approach_duration", "grasp_hold_duration", "jump_carry_duration", "release_hold_duration", "retreat_duration"]:
		rig.set(property_name, 0.01)
	rig.jump_carry_duration = 0.12
	var knight := Knight.new("white", Vector2i(4, 3))
	var origin_nearer_queen := Queen.new("black", Vector2i(5, 3))
	var destination_nearer_queen := Queen.new("black", Vector2i(3, 4))
	var closer_rook := Rook.new("black", Vector2i(6, 3))
	_reset_battle(model, controller, [knight, origin_nearer_queen, destination_nearer_queen, closer_rook])
	var stationary_views: Array[Node2D] = [
		context.adapter.get_piece_view(origin_nearer_queen),
		context.adapter.get_piece_view(destination_nearer_queen),
		context.adapter.get_piece_view(closer_rook),
	]
	var natural_depths: Array[int] = []
	for piece_view in stationary_views:
		natural_depths.append(piece_view.z_index)
	var observed := {"origin_grounded": false, "destination_grounded": false, "elevated": false, "grounded_at_jump_start": false, "grounded_before_contact": false}
	var knight_view: Node2D = context.adapter.get_piece_view(knight)
	var origin_position := knight_view.position
	var origin_contact := view.to_local(knight_view.get_grip_anchor().global_position)
	var destination_contact := origin_contact + view.grid_to_screen(2, 4) - origin_position
	rig.carry_path_started.connect(
		func(path: StringName):
			if path == ChessHandRig.CARRY_PATH_JUMP:
				observed["grounded_at_jump_start"] = rig.depth_state == ChessHandRig.DepthState.GROUNDED
	)
	rig.piece_grabbed.connect(
		func(_piece: Node2D):
			observed["origin_grounded"] = (
				rig.depth_state == ChessHandRig.DepthState.GROUNDED
				and rig.grip_front_sprite.z_index < stationary_views[0].z_index
				and stationary_views[0].z_index < rig.arm_foreground_sprite.z_index
			)
	)
	rig.depth_state_changed.connect(
		func(state: ChessHandRig.DepthState, base_depth: int):
			if state == ChessHandRig.DepthState.ELEVATED:
				observed["elevated"] = rig.piece_slot.z_index > 7 * ChessBoardView.BOARD_DEPTH_STRIDE
			elif observed["elevated"] and base_depth == view.get_piece_depth(Vector2i(2, 4)):
				observed["grounded_before_contact"] = not rig.position.is_equal_approx(destination_contact)
	)
	rig.piece_released.connect(
		func(_piece: Node2D):
			observed["destination_grounded"] = (
				rig.depth_state == ChessHandRig.DepthState.GROUNDED
				and rig.grip_front_sprite.z_index < stationary_views[1].z_index
				and stationary_views[1].z_index < rig.arm_foreground_sprite.z_index
			)
	)
	controller.select_piece(knight)
	await controller._on_square_clicked(Vector2i(2, 4))
	_expect(observed["origin_grounded"] and observed["destination_grounded"], "surrounded knight grounds its thumb beneath the naturally nearer tall piece at pickup and landing")
	_expect(observed["grounded_at_jump_start"], "knight remains row-sorted when its jump begins instead of popping immediately into foreground")
	_expect(observed["elevated"], "jumping knight and grip enter the foreground band during the arc")
	_expect(observed["grounded_before_contact"], "descending knight returns to destination-row depth before reaching its exact landing contact")
	for index in range(stationary_views.size()):
		_expect(stationary_views[index].z_index == natural_depths[index], "surrounding tall piece %d keeps its natural board depth through the knight jump" % index)
	await _destroy_game(context.game)


func _make_test_hand_sound_set() -> ChessHandSoundSet:
	var sound_set := ChessHandSoundSet.new()
	sound_set.grab = AudioStreamWAV.new()
	sound_set.grab_volume_db = -7.0
	sound_set.grab_pitch_variation = 0.08
	sound_set.release = AudioStreamWAV.new()
	sound_set.release_volume_db = -7.0
	sound_set.release_pitch_variation = 0.08
	return sound_set


func _make_test_board_sound_set() -> ChessBoardSoundSet:
	var sound_set := ChessBoardSoundSet.new()
	sound_set.default_capture_pickup = AudioStreamWAV.new()
	sound_set.default_place = AudioStreamWAV.new()
	sound_set.default_slide = AudioStreamWAV.new()
	sound_set.volume_db = -5.0
	sound_set.pitch_variation = 0.04
	return sound_set


func _test_active_bone_pawn_summon_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var necromancer := NecromancerKing.new("white", Vector2i(7, 4))
	var pawn := Pawn.new("white", Vector2i(6, 0))
	_reset_battle(model, controller, [necromancer, pawn])
	var observation := {"summoned_count": 0}
	model.piece_summoned.connect(
		func(piece: ModelPiece, _completion: CompletionGate):
			if piece is BonePawn:
				observation["summoned_count"] += 1
	)
	var target: Vector2i = necromancer.get_active_ability_targets()[0]
	await model.submit_active_ability(necromancer, target)
	await get_tree().process_frame

	var summoned_piece: ModelPiece = model.board[target.x][target.y]
	var piece_node: Node2D = context.adapter.get_piece_view(summoned_piece)
	_expect(summoned_piece is BonePawn and observation["summoned_count"] == 1, "active ability emits one Bone Pawn summon presentation event")
	_expect(piece_node.position == context.view.grid_to_screen(target.x, target.y), "summoned Bone Pawn settles exactly on its square")
	var summoned_sprite := piece_node.get_node("Sprite2D") as Sprite2D
	_expect(summoned_sprite.texture.resource_path == "res://assets/pieces/special/white_bone_pawn.png", "summoned White Bone Pawn resolves its authored special-piece art")
	_expect(summoned_sprite.material == null, "summoned White Bone Pawn remains exempt from the standard palette shader")
	_expect(_count_summon_portals(context.view) == 0, "active summon portal cleans itself up")
	_expect(not model.action_in_progress, "active summon animation completes before action resolution ends")

	await _destroy_game(context.game)


func _test_default_initialization_and_normal_move() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller

	_expect(_count_board_pieces(model) == 32, "default board contains 32 pieces")
	_expect(model.current_turn == "white", "default battle starts with White")
	_expect(model.get_king("white") != null, "default board has a White king")
	_expect(model.get_king("black") != null, "default board has a Black king")

	var pawn: ModelPiece = model.board[6][0]
	var legal_moves := model.get_legal_moves(pawn)
	_expect(Vector2i(5, 0) in legal_moves, "unmoved White pawn can advance one square")
	_expect(Vector2i(4, 0) in legal_moves, "unmoved White pawn can advance two clear squares")

	await model.move_piece(pawn, Vector2i(4, 0))
	_expect(model.board[4][0] == pawn and model.board[6][0] == null, "normal move updates authoritative board state")
	_expect(pawn.coordinate == Vector2i(4, 0) and pawn.has_moved, "normal move updates piece state")
	_expect(model.last_move.get("piece") == pawn, "normal move records its piece")
	_expect(model.last_move.get("from") == Vector2i(6, 0), "normal move records its origin")
	_expect(model.last_move.get("to") == Vector2i(4, 0), "normal move records its destination")
	_expect(model.current_turn == "black", "resolved normal move switches the turn")
	_expect(not model.action_in_progress, "resolved normal move closes the action")
	_expect(not controller.is_input_locked, "resolved normal move unlocks ordinary input")
	_expect(context.game.control_mode == ChessGame.ControlMode.PLAYER_VS_PLAYER, "test battle is configured for two players")
	_expect(controller.is_player_controlled("white") and controller.is_player_controlled("black"), "two-player mode leaves both colors player-controlled")
	_expect(not context.game.white_cpu_player.is_enabled and not context.game.black_cpu_player.is_enabled, "two-player mode disables both CPU clients")
	var pawn_view: Node = context.adapter.get_piece_view(pawn)
	_expect(is_instance_valid(pawn_view), "presentation maps the moved pawn to a View node")
	_expect(pawn_view.coordinate == Vector2i(4, 0), "movement animation leaves the View node at the destination")
	await get_tree().process_frame
	_expect(model.current_turn == "black", "two-player mode does not automatically take Black's turn")
	controller.select_piece(model.board[1][0])
	_expect(controller.selected_piece == model.board[1][0], "two-player mode still permits Black Controller selection")

	await _destroy_game(context.game)


func _test_ai_configuration_and_turns() -> void:
	var white_player_context := await _create_game(ChessGame.ControlMode.PLAYER_VS_CPU, "white")
	var white_player_model: ChessBoardModel = white_player_context.model
	var white_player_controller: ChessBoardController = white_player_context.controller
	_expect(white_player_controller.is_player_controlled("white") and not white_player_controller.is_player_controlled("black"), "White-player game assigns Controller ownership to White")
	_expect(not white_player_context.game.white_cpu_player.is_enabled and white_player_context.game.black_cpu_player.is_enabled, "White-player game enables only the Black CPU")
	_expect(white_player_context.view.viewing_color == "white", "White-player game uses White board perspective")
	white_player_controller.select_piece(white_player_model.board[1][0])
	_expect(white_player_controller.selected_piece == null, "Controller cannot select a CPU-owned piece")
	var black_cpu_actions := {"count": 0}
	white_player_model.action_started.connect(
		func(color: String):
			if color == "black":
				black_cpu_actions["count"] += 1
	)
	await white_player_model.submit_move(white_player_model.board[6][0], Vector2i(4, 0))
	await _wait_for_idle_turn(white_player_model, "white")
	_expect(black_cpu_actions["count"] == 1, "Black CPU acts after the human action resolves")
	await _destroy_game(white_player_context.game)

	var black_player_context := await _create_game(ChessGame.ControlMode.PLAYER_VS_CPU, "black")
	var black_player_model: ChessBoardModel = black_player_context.model
	var black_player_controller: ChessBoardController = black_player_context.controller
	await _wait_for_idle_turn(black_player_model, "black")
	_expect(not black_player_controller.is_player_controlled("white") and black_player_controller.is_player_controlled("black"), "Black-player game assigns Controller ownership to Black")
	_expect(black_player_context.game.white_cpu_player.is_enabled and not black_player_context.game.black_cpu_player.is_enabled, "Black-player game enables only the White CPU")
	_expect(black_player_context.view.viewing_color == "black", "Black-player game uses Black board perspective")
	_expect(black_player_model.current_turn == "black" and not black_player_model.action_in_progress, "White CPU takes the opening turn before the Black player")
	black_player_context.game._on_battle_finished("black")
	_expect(black_player_context.game.completed_player_result == "win", "Black victory maps to a Black player's win")
	await _destroy_game(black_player_context.game)

	var zero_game := CHESS_GAME_SCENE.instantiate()
	zero_game.play_opening_presentation = false
	zero_game.control_mode = ChessGame.ControlMode.CPU_VS_CPU
	add_child(zero_game)
	var zero_model: ChessBoardModel = zero_game.get_node("ChessModel")
	var zero_controller: ChessBoardController = zero_game.get_node("ChessController")
	var white_cpu: ChessCpuPlayer = zero_game.get_node("WhiteCpuPlayer")
	var black_cpu: ChessCpuPlayer = zero_game.get_node("BlackCpuPlayer")
	var zero_action_owners: Array[String] = []
	zero_model.action_started.connect(
		func(color: String):
			zero_action_owners.append(color)
			if zero_action_owners.size() == 2:
				white_cpu.is_enabled = false
				black_cpu.is_enabled = false
	)
	await _wait_for_action_count(zero_action_owners, 2)
	await _wait_for_idle_turn(zero_model, "white")
	_expect(zero_controller.player_controlled_colors.is_empty(), "CPU-vs-CPU mode gives the Controller no colors")
	_expect(zero_action_owners == ["white", "black"], "CPU-vs-CPU mode alternates White then Black")
	_expect(white_cpu.controlled_color == "white" and black_cpu.controlled_color == "black", "CPU-vs-CPU assigns one shared-script instance to each color")
	await _destroy_game(zero_game)


func _test_black_view_hand_presentation() -> void:
	var context := await _create_game(ChessGame.ControlMode.PLAYER_VS_PLAYER, "black")
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var rig: ChessHandRig = context.view.near_hand_rig
	var far_rig: ChessHandRig = context.view.far_hand_rig
	far_rig._set_grounded_depth(40)
	_expect(
		far_rig.grip_back_sprite.z_index < 50
		and 50 < far_rig.grip_front_sprite.z_index
		and far_rig.grip_front_sprite.z_index < far_rig.arm_foreground_sprite.z_index,
		"Hood grounds its back/thumb layer while keeping foreground fingers and arm above nearer board pieces"
	)
	far_rig._set_elevated_depth()
	far_rig.has_approach_preview = true
	far_rig.approach_preview_start = Vector2.ZERO
	far_rig.approach_preview_target = Vector2(100.0, 100.0)
	far_rig.approach_preview_world_scale = 1.0
	far_rig.approach_preview_progress = 0.5
	far_rig._refresh_live_approach()
	var expected_far_approach := ChessHandRig.calculate_bezier_position(
		Vector2.ZERO,
		Vector2.ZERO.lerp(Vector2(100.0, 100.0), far_rig.approach_departure_progress) + Vector2.UP * far_rig.approach_departure_lift,
		Vector2(100.0, 100.0) + Vector2(-far_rig.approach_arrival_handle.x, far_rig.approach_arrival_handle.y),
		Vector2(100.0, 100.0),
		0.5
	)
	_expect(far_rig.position.is_equal_approx(expected_far_approach), "Far approach mirrors its horizontal handle while preserving upward lift")
	var jump_midpoint := ChessHandRig.calculate_jump_position(Vector2.ZERO, Vector2(100.0, 100.0), 0.5, 32.0)
	_expect(jump_midpoint.y < 50.0, "shared jump and capture arcs bow upward away from the board")
	for hand_rig in [rig, far_rig]:
		for property_name in ["approach_duration", "grasp_hold_duration", "carry_duration", "jump_carry_duration", "release_hold_duration", "retreat_duration"]:
			hand_rig.set(property_name, 0.01)
	var grabbed_colors: Array[String] = []
	var far_grabbed_colors: Array[String] = []
	far_rig.piece_grabbed.connect(func(piece: Node2D): far_grabbed_colors.append(piece.model.color))
	rig.piece_grabbed.connect(
		func(piece: Node2D):
			grabbed_colors.append(piece.model.color)
			if piece.model.color == "black":
				var nearer_black_rook: Node2D = context.adapter.get_piece_view(model.board[0][0])
				_expect(context.view.get_piece_directly_toward_viewer(Vector2i(1, 0)) == nearer_black_rook, "Black perspective identifies the rotated same-file piece one displayed row nearer")
				_expect(nearer_black_rook.z_index > rig.grip_front_sprite.z_index, "Black perspective keeps the direct lower piece over the closed front grip throughout the hand visit")
				_expect(rig.arm_foreground_sprite.z_index > nearer_black_rook.z_index, "the foreground arm remains above the promoted Black lower piece")
	)
	await controller._on_square_clicked(Vector2i(6, 0))
	await controller._on_square_clicked(Vector2i(5, 0))
	_expect(grabbed_colors.is_empty() and far_grabbed_colors == ["white"], "White movement uses the far Hood seat from Black perspective")
	_expect(far_rig.seat == ChessHandRig.Seat.FAR and far_rig.hand_style.open_arm_foreground.resource_path.ends_with("hood_open_arm_foreground.png"), "Far seat owns the Hood hand style independently of army color")
	await controller._on_square_clicked(Vector2i(1, 0))
	await controller._on_square_clicked(Vector2i(2, 0))
	_expect(grabbed_colors == ["black"], "Black movement uses the near Skeleton seat from Black perspective")
	_expect(context.adapter.get_piece_view(model.board[0][0]).z_index == context.view.get_piece_depth(Vector2i(0, 0)), "Black lower-piece depth restores after the hand retreats")
	await _destroy_game(context.game)


func _test_nonlethal_attack_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var rig: ChessHandRig = context.view.player_hand_rig
	var rook := Rook.new("white", Vector2i(4, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	_reset_battle(model, controller, [rook, minotaur])
	var rook_view: Node = context.adapter.get_piece_view(rook)
	var minotaur_view: Node = context.adapter.get_piece_view(minotaur)
	var hp_bar = minotaur_view.get_node("HpBar")
	var original_position: Vector2 = rook_view.position
	var initial_displayed_hp: int = hp_bar.current_hp
	rig.approach_duration = 0.01
	rig.grasp_hold_duration = 0.01
	rig.attack_slam_duration = 0.01
	rig.attack_rebound_duration = 0.01
	rig.retreat_duration = 0.01
	var observation := {"attack_events": 0, "action_open": false, "gate_pending": false, "grabbed": false, "released": false, "visuals_delayed": false, "visuals_at_contact": false}
	var carry_paths: Array[StringName] = []
	model.piece_attack_committed.connect(
		func(piece: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, gate: CompletionGate):
			if piece == rook and defender == minotaur and from == Vector2i(4, 0) and to == Vector2i(4, 4):
				observation["attack_events"] += 1
				await get_tree().process_frame
				observation["action_open"] = model.action_in_progress
				observation["gate_pending"] = not gate.is_completed()
	)
	rig.piece_grabbed.connect(
		func(piece_node: Node2D):
			observation["grabbed"] = piece_node == rook_view and piece_node.get_parent() == rig.piece_slot
			observation["visuals_delayed"] = minotaur.current_hp < minotaur.max_hp and hp_bar.current_hp == initial_displayed_hp and _count_children_named(context.view, &"BloodSplatter") == 0
	)
	rig.attack_contact.connect(
		func(piece_node: Node2D):
			observation["visuals_at_contact"] = piece_node == rook_view and hp_bar.current_hp == minotaur.current_hp and _count_children_named(context.view, &"BloodSplatter") == 1
	)
	rig.piece_released.connect(func(piece_node: Node2D): observation["released"] = piece_node == rook_view and piece_node.get_parent() == context.view.get_node("Pieces"))
	rig.carry_path_started.connect(func(path: StringName): carry_paths.append(path))

	controller.select_piece(rook)
	await controller._on_square_clicked(minotaur.coordinate)
	_expect(observation["attack_events"] == 1, "surviving-defender combat emits one presentation event")
	_expect(observation["action_open"] and observation["gate_pending"], "nonlethal attack animation runs inside the open Model action")
	_expect(observation["grabbed"] and observation["released"] and carry_paths == [&"slam"], "player ranged attack is carried through a hand-rig slam and rebound")
	_expect(observation["visuals_delayed"] and observation["visuals_at_contact"], "damage HP, splatter, and sound presentation begins when the hand-carried attacker contacts the king")
	_expect(minotaur.current_hp == minotaur.max_hp - rook.attack_power, "animated nonlethal attack applies damage")
	_expect(model.board[4][0] == rook and rook.coordinate == Vector2i(4, 0), "animated attacker remains on its Model square")
	_expect(rook_view.coordinate == Vector2i(4, 0), "attack animation does not change the PieceView coordinate")
	_expect(rook_view.position.is_equal_approx(original_position), "attack animation returns the PieceView to its original position")
	_expect(rig.position.is_equal_approx(rig._offscreen_rest_position(context.view.get_world_scale() * rig.art_scale_multiplier)), "ranged attack retreats to the shared lower-right hand rest position")
	_expect(model.current_turn == "black" and not model.action_in_progress, "turn completes after the attack returns")
	await _destroy_game(context.game)


func _test_arakne_spike_burst() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var target := MinotaurKing.new("black", Vector2i(3, 3))
	_reset_battle(model, context.controller, [arakne, target])

	var targets := arakne.get_active_ability_targets()
	_expect(Vector2i(3, 3) in targets, "Spike Burst targets an adjacent enemy")
	await model.perform_active_ability(arakne, Vector2i(3, 3))
	_expect(target.current_hp == target.max_hp - ArakneKing.SPIKE_BURST_DAMAGE, "Spike Burst applies its configured damage")
	_expect(arakne.current_cooldown == ArakneKing.ACTIVE_ABILITY_COOLDOWN, "Spike Burst resets Arakne cooldown")
	_expect(model.current_turn == "black", "Spike Burst consumes White's action")
	_expect(not model.action_in_progress, "Spike Burst finishes its action")

	await _destroy_game(context.game)


func _test_minotaur_charge_survivor_landing() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var charging_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var defending_minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	defending_minotaur.stunned = true
	_reset_battle(model, context.controller, [charging_minotaur, defending_minotaur])
	var charging_view: Node = context.adapter.get_piece_view(charging_minotaur)

	await model.submit_active_ability(charging_minotaur, defending_minotaur.coordinate)
	_expect(defending_minotaur.current_hp == defending_minotaur.max_hp - 2, "composed Charge damages its surviving target")
	_expect(model.board[4][4] == defending_minotaur, "composed surviving target retains its square")
	_expect(model.board[4][3] == charging_minotaur and charging_minotaur.coordinate == Vector2i(4, 3), "composed Charge ends adjacent to its surviving target")
	_expect(charging_view.coordinate == Vector2i(4, 3), "Charge presentation updates the Minotaur View coordinate")
	_expect(charging_view.position.is_equal_approx(context.view.grid_to_screen(4, 3)), "Charge presentation finishes on the adjacent square")
	_expect(model.current_turn == "black" and not model.action_in_progress, "surviving Charge landing completes before turn change")
	await _destroy_game(context.game)


func _test_minotaur_rage_barrier() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var adjacent_pawn := Pawn.new("white", Vector2i(3, 4))
	_reset_battle(model, context.controller, [minotaur, adjacent_pawn])

	var observation := {"intro_completed": false}
	context.view.rage_intro_animation_completed.connect(
		func(): observation["intro_completed"] = true,
		CONNECT_ONE_SHOT
	)
	_expect(model.begin_action("white"), "Rage characterization action starts")
	await minotaur.take_damage(1)
	_expect(model.selection_queue.size() == 1, "surviving Minotaur damage queues one reaction")
	_expect(model.selection_queue[0]["action_type"] == "retaliating_rage", "queued Minotaur reaction is Retaliating Rage")
	await model.continue_action_resolution()

	_expect(observation["intro_completed"], "Rage intro animation completes before action resolution returns")
	_expect(model.board[3][4] == null, "Rage damages and destroys an adjacent one-HP piece")
	_expect(model.current_turn == "black", "completed Rage chain switches the turn")
	_expect(not model.action_in_progress, "completed Rage chain closes the action")

	await _destroy_game(context.game)


func _test_rage_raise_dead_death_square_target() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(3, 4))
	_reset_battle(model, controller, [minotaur, necromancer, rook])

	_expect(model.begin_action("white"), "Rage-to-Raise-Dead action starts")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(model.board[3][4] == null, "composed Rage leaves the defeated piece's square empty")
	_expect(controller.non_move_selection_mode, "Rage defeat enters Raise Dead selection mode")
	_expect(Vector2i(3, 4) in controller.legal_moves, "Controller receives the empty Rage death square as a Raise Dead target")
	await model.submit_reaction_selection(Vector2i(3, 4))
	await get_tree().process_frame
	_expect(model.board[3][4] is BonePawn, "composed Raise Dead summons on the Rage death square")
	_expect(_count_summon_portals(context.view) == 0, "Raise Dead uses and cleans up the shared summon portal")
	_expect(not controller.non_move_selection_mode, "death-square selection exits reaction mode")
	await _destroy_game(context.game)


func _test_terminal_rank_raise_dead_expiration() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(6, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(7, 4))
	_reset_battle(model, controller, [minotaur, necromancer, rook])
	var observation := {"bone_pawns_added": 0, "bone_pawns_destroyed": 0, "event_order": []}
	model.piece_added.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_added"] += 1
	)
	model.piece_summoned.connect(
		func(piece: ModelPiece, _completion: CompletionGate):
			if piece is BonePawn:
				observation["event_order"].append("summoned")
	)
	model.piece_destroyed.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_destroyed"] += 1
				observation["event_order"].append("destroyed")
	)

	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(Vector2i(7, 4) in controller.legal_moves, "Controller keeps the opposite back rank selectable")
	await model.submit_reaction_selection(Vector2i(7, 4))
	_expect(observation["bone_pawns_added"] == 1 and observation["bone_pawns_destroyed"] == 1, "composed summon immediately adds and destroys the terminal Bone Pawn")
	_expect(observation["event_order"] == ["summoned", "destroyed"], "terminal Bone Pawn finishes its summon event before destruction")
	_expect(model.board[7][4] == null, "composed terminal-rank summon leaves the Model square empty")
	_expect(context.adapter.get_piece_view(model.last_destroyed_piece) == null, "presentation removes the expired Bone Pawn mapping")
	_expect(not controller.non_move_selection_mode and model.current_turn == "black", "terminal-rank selection resolves and finishes the action")
	await _destroy_game(context.game)


func _test_rage_priority_before_raise_dead() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(6, 6))
	_reset_battle(model, controller, [minotaur, necromancer, rook])

	_expect(model.begin_action("white"), "mixed-reaction characterization action starts")
	model.destroy_piece(rook, true)
	await minotaur.take_damage(1)
	_expect(model.selection_queue.size() == 2, "Raise Dead and Rage coexist in the reaction queue")
	await model.continue_action_resolution()

	_expect(minotaur.current_hp == minotaur.max_hp - 1, "Rage source retains the triggering damage")
	_expect(controller.non_move_selection_mode, "Raise Dead pauses after automatic Rage resolves")
	_expect(controller.active_piece == necromancer, "pending selection belongs to the Necromancer")
	_expect(model.get_pending_reaction()["calling_piece"] == necromancer, "Model owns the pending mixed-reaction choice")
	_expect(model.action_in_progress, "action remains open while Raise Dead awaits a choice")

	var choice: Vector2i = controller.legal_moves[0]
	await model.submit_reaction_selection(choice)
	_expect(model.board[choice.x][choice.y] is BonePawn, "Raise Dead creates a Bone Pawn after the queued Rage")
	_expect(not model.action_in_progress, "mixed reaction action finishes after the choice")

	await _destroy_game(context.game)


func _test_raise_dead_selection_resume() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	_reset_battle(model, controller, [necromancer, bishop])

	_expect(model.begin_action("white"), "Raise Dead characterization action starts")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	_expect(controller.non_move_selection_mode, "Raise Dead enters non-move selection mode")
	_expect(controller.active_piece == necromancer, "Raise Dead exposes its caller through Controller state")
	_expect(not controller.legal_moves.is_empty(), "Raise Dead exposes legal choices through Controller state")
	_expect(model.has_pending_reaction(), "Raise Dead exposes the pending choice through Model state")
	_expect(model.action_in_progress, "Raise Dead pauses the current Model action")

	var choice: Vector2i = controller.legal_moves[0]
	await model.submit_reaction_selection(choice)
	_expect(model.board[choice.x][choice.y] is BonePawn, "Raise Dead choice summons a Bone Pawn")
	_expect(not controller.non_move_selection_mode, "Raise Dead choice exits selection mode")
	_expect(model.current_turn == "black", "Raise Dead choice resumes resolution and switches turn")

	await _destroy_game(context.game)


func _test_battle_completion() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var white_king := ClassicKing.new("white", Vector2i(7, 7))
	var black_king := ClassicKing.new("black", Vector2i(0, 0))
	_reset_battle(model, controller, [white_king, black_king])

	var observation := {"reported_result": ""}
	model.battle_finished.connect(
		func(result: String): observation["reported_result"] = result,
		CONNECT_ONE_SHOT
	)
	_expect(model.begin_action("white"), "battle-completion characterization action starts")
	model.destroy_piece(black_king, true)
	await model.continue_action_resolution()

	_expect(model.battle_over, "destroying a king completes the battle")
	_expect(model.battle_result == "white", "destroying Black's king records White as winner")
	_expect(observation["reported_result"] == "white", "battle completion emits the winning color")
	_expect(controller.is_input_locked, "battle completion leaves Controller input locked")
	_expect(not model.action_in_progress, "battle completion closes the current action")

	await _destroy_game(context.game)


func _create_game(control_mode: ChessGame.ControlMode = ChessGame.ControlMode.PLAYER_VS_PLAYER, player_color: String = "white") -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = GameFlow.BATTLE_LOGICAL_SIZE
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.snap_2d_transforms_to_pixel = true
	add_child(viewport)
	var game := CHESS_GAME_SCENE.instantiate()
	game.play_opening_presentation = false
	game.control_mode = control_mode
	game.player_color = player_color
	game.opponent_hand_style = HOOD_HAND_STYLE
	viewport.add_child(game)
	await get_tree().process_frame
	return {
		"game": game,
		"model": game.get_node("ChessModel"),
		"controller": game.get_node("ChessController"),
		"adapter": game.get_node("ChessPresentationAdapter"),
		"view": game.get_node("CanvasLayer/ChessBoard"),
	}


func _destroy_game(game: Node) -> void:
	var viewport := game.get_parent() as SubViewport
	if viewport != null:
		viewport.queue_free()
	else:
		game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_for_idle_turn(model: ChessBoardModel, color: String, max_frames: int = 600) -> void:
	for frame in range(max_frames):
		if model.current_turn == color and not model.action_in_progress:
			return
		await get_tree().process_frame


func _wait_for_action_count(owners: Array[String], expected: int, max_frames: int = 360) -> void:
	for frame in range(max_frames):
		if owners.size() >= expected:
			return
		await get_tree().process_frame


func _reset_battle(model: ChessBoardModel, controller: ChessBoardController, pieces: Array) -> void:
	var adapter: ChessPresentationAdapter = model.get_parent().get_node("ChessPresentationAdapter")
	for row in model.board:
		for piece in row:
			if piece != null:
				model.unregister_piece(piece)

	for piece_node in adapter.view.get_node("Pieces").get_children():
		piece_node.free()
	adapter.piece_views.clear()

	model.board = []
	for row_index in range(8):
		var row: Array = []
		for column_index in range(8):
			row.append(null)
		model.board.append(row)

	model.last_move = {}
	model.last_destroyed_piece = null
	model.current_turn = "white"
	model.battle_over = false
	model.battle_result = ""
	model.defeated_king_colors.clear()
	model.selection_queue.clear()
	model.pending_reaction.clear()
	model.selection_sequence = 0
	model.action_in_progress = false
	model.action_owner_color = ""

	controller.selected_piece = null
	controller.active_king = null
	controller.active_piece = null
	controller.last_active_piece = null
	controller.legal_moves.clear()
	controller.is_input_locked = false
	controller.active_ability_selected = false
	controller.non_move_selection_mode = false

	for piece in pieces:
		var added := model.add_piece(piece, piece.coordinate)
		_expect(added, "test setup adds %s at %s" % [piece.type, piece.coordinate])


func _count_board_pieces(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null:
				count += 1
	return count


func _count_summon_portals(view: ChessBoardView) -> int:
	var count := 0
	for child in view.get_children():
		if child is BonePawnSummonPortal:
			count += 1
	return count


func _count_children_named(parent: Node, child_name: StringName) -> int:
	var count := 0
	for child in parent.get_children():
		if child.name == child_name:
			count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
