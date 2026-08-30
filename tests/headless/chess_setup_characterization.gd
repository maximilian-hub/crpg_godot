extends Node

const LAB_SCENE := preload("res://tools/dev_chess_setup/chess_setup_lab.tscn")
const SetupPreset := preload("res://tools/dev_chess_setup/chess_setup_lab_preset.gd")

var failures := 0


func _ready() -> void:
	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(lab.setup_profile.cues.size() == 16, "default setup authors all sixteen army placements")
	_check(lab.left_cue_list.item_count == 8 and lab.right_cue_list.item_count == 8, "Setup Lab presents the two independent hand orders as visible eight-piece lanes")
	_check(int(lab.left_cue_list.get_item_metadata(0)) == 0 and int(lab.right_cue_list.get_item_metadata(0)) == 8, "Cue lane rows retain stable mappings to the compatible flat cue resource")
	_check(lab.left_cue_list.get_item_text(0).ends_with("a_rook") and lab.right_cue_list.get_item_text(0).ends_with("h_rook"), "Every setup cue label begins with its chess file, not only pawns")
	_check(not lab.setup_sequence.running and lab.piece_views.values().all(func(piece): return not piece.visible), "Setup Lab opens paused on an empty player side")
	_check(lab.left_hand.visual_mirrored and not lab.right_hand.visual_mirrored, "setup hands use mirrored left and original right artwork")
	lab.left_hand._apply_pose(true)
	_check(lab.left_hand.arm_foreground_sprite.flip_h and lab.left_hand.grip_front_sprite.flip_h and lab.left_hand.grip_back_sprite.flip_h, "every left-hand art layer mirrors around its grip")
	var activation_hand: ChessHandRig = lab.activation_sequence.hand_root
	_check(lab.activation_sequence.hand_connection_anchor.position == activation_hand.get_connection_anchor_position(), "Setup activation lightning anchor resolves the style-owned palm pixel against the live rig origin")
	var king_coordinate: Vector2i = lab.board.projection.get_model_coordinate(Vector2i(7, 4))
	var king_view: PieceView = lab.piece_views.get(king_coordinate)
	lab.activation_sequence.base_hand_position = Vector2(-999.0, -999.0)
	lab.activation_sequence.hand_rest_position = Vector2(-888.0, -888.0)
	lab._refresh_activation_hand_geometry()
	var activation_direction := -1.0 if activation_hand.visual_mirrored else 1.0
	var expected_offset: Vector2 = lab.activation_sequence.profile.hand_hover_offset
	expected_offset.x *= activation_direction
	var expected_rest := activation_hand._setup_rest_position(lab.board.get_world_scale() * activation_hand.art_scale_multiplier)
	_check(lab.activation_sequence.base_hand_position == king_view.position + expected_offset and lab.activation_sequence.hand_rest_position == expected_rest and activation_hand.position == expected_rest, "Setup Lab refreshes activation hover/rest endpoints from the final board layout")

	lab.setup_profile.left_motion.pickup_delay = 0.21
	lab.setup_profile.right_motion.pickup_delay = 0.47
	lab.motion_side_selector.select(2)
	lab._sync_motion_controls()
	var shared_pickup_control: SpinBox = lab.motion_controls[&"pickup_delay"]
	_check(shared_pickup_control.get_line_edit().text == "?", "Both-hands mode displays a question mark when scalar defaults disagree")
	shared_pickup_control.value = 0.33
	_check(is_equal_approx(lab.setup_profile.left_motion.pickup_delay, 0.33) and is_equal_approx(lab.setup_profile.right_motion.pickup_delay, 0.33), "Editing a scalar in both-hands mode updates both default motion profiles")
	lab.setup_profile.left_motion.entry_arrival_handle.x = 12.0
	lab.setup_profile.right_motion.entry_arrival_handle.x = 34.0
	lab._sync_motion_controls()
	var shared_vector_control: SpinBox = lab.motion_controls[&"entry_arrival_handle:x"]
	_check(shared_vector_control.get_line_edit().text == "?", "Both-hands mode displays a question mark when vector components disagree")
	shared_vector_control.value = 56.0
	_check(is_equal_approx(lab.setup_profile.left_motion.entry_arrival_handle.x, 56.0) and is_equal_approx(lab.setup_profile.right_motion.entry_arrival_handle.x, 56.0), "Editing a vector component in both-hands mode updates both default motion profiles")
	lab.setup_profile.left_motion.pickup_delay = 0.06
	lab.setup_profile.right_motion.pickup_delay = 0.12
	lab.motion_side_selector.select(2)
	lab._sync_motion_controls()
	_check(shared_pickup_control.get_line_edit().text == "?", "Returning to both-hands mode immediately restores the mixed-value display")
	lab.motion_side_selector.select(1)
	lab._sync_motion_controls()
	_check(shared_pickup_control.get_line_edit().text == "0.12", "Leaving both-hands mode always replaces a stale question mark with the selected hand's numeric value")

	for motion in [lab.setup_profile.left_motion, lab.setup_profile.right_motion]:
		motion.pickup_delay = 0.001
		motion.entry_duration = 0.01
		motion.placement_hold = 0.001
		motion.release_hold = 0.001
		motion.retreat_duration = 0.01
	for cue in lab.setup_profile.cues:
		cue.gap_before = 0.0
	for property in ["approach_duration", "approach_settle_duration", "invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "climax_hand_return_duration", "post_climax_retreat_delay", "retreat_duration", "resolve_duration"]:
		lab.activation_sequence.profile.set(property, 0.01)
	lab.activation_sequence.profile.buildup_crackle_times = PackedFloat32Array()
	lab.activation_sequence.profile.crackle_duration = 0.001
	lab.setup_sequence.set_playback_speed(4.0)
	lab.activation_sequence.set_playback_speed(4.0)
	var started_sides: Dictionary = {}
	var observations := {"placed": 0}
	lab.setup_sequence.cue_started.connect(func(cue): started_sides[cue.hand_side] = true)
	lab.setup_sequence.piece_placed.connect(func(_cue, piece):
		observations["placed"] = int(observations["placed"]) + 1
		_check(not piece.sprite.flip_h, "carried/released chess art remains unmirrored")
	)
	lab._play()
	var timeout := 5.0
	while lab.activation_sequence.current_phase != lab.activation_sequence.Phase.COMPLETE and timeout > 0.0:
		await get_tree().process_frame
		timeout -= get_process_delta_time()
	_check(timeout > 0.0, "full two-hand setup chains into activation and completes")
	_check(int(observations["placed"]) == 16 and started_sides.has(ChessSetupCue.HandSide.LEFT) and started_sides.has(ChessSetupCue.HandSide.RIGHT), "both independent tracks place every army piece exactly once")
	var correctly_placed := true
	for cue in lab.setup_profile.cues:
		var coordinate: Vector2i = lab.board.projection.get_model_coordinate(cue.display_coordinate)
		var piece: PieceView = lab.piece_views.get(coordinate)
		correctly_placed = correctly_placed and piece.visible and piece.position == lab.board.grid_to_screen(coordinate.x, coordinate.y) and piece.z_index == lab.board.get_piece_depth(coordinate)
	_check(correctly_placed, "released pieces finish at exact board anchors and board depth")
	var selected_hand: ChessHandRig = lab.left_hand if lab.setup_profile.activating_hand == ChessArmySetupProfile.ActivatingHand.LEFT else lab.right_hand
	_check(lab.activation_sequence.hand_root == selected_hand, "explicit activating-hand selection wires the requested rig")
	_check(not lab.stone_sprite.visible and is_equal_approx(lab.activation_sequence.king_sprite.self_modulate.a, 1.0), "activation resolves the placed stone king into authored army art")
	_check(not selected_hand.visible and selected_hand.position == lab.activation_sequence.hand_rest_position, "combined preview completes with the activation hand hidden at its mirrored rest position")

	lab.playback_mode = lab.PlaybackMode.SETUP_ONLY
	lab._restart()
	lab._play()
	timeout = 3.0
	while lab.setup_sequence.running and timeout > 0.0:
		await get_tree().process_frame
		timeout -= get_process_delta_time()
	_check(timeout > 0.0 and lab.activation_sequence.current_phase == lab.activation_sequence.Phase.RESET and lab.piece_views.values().all(func(piece): return piece.visible), "Setup Only stops after both tracks without coupling to activation")

	lab.playback_mode = lab.PlaybackMode.ACTIVATION_ONLY
	lab._restart()
	_check(lab.piece_views.values().all(func(piece): return piece.visible) and not lab.setup_sequence.running, "Activation Only begins from a completed army fixture")
	lab._play()
	for _frame in range(3): await get_tree().process_frame
	_check(lab.activation_sequence.current_phase != lab.activation_sequence.Phase.RESET and not lab.setup_sequence.running, "Activation Only invokes the complete ritual independently")
	lab._restart()
	lab.playback_mode = lab.PlaybackMode.SETUP_THEN_ACTIVATION

	lab.setup_profile.left_motion.entry_duration = 0.3
	lab.setup_profile.right_motion.entry_duration = 0.3
	lab._restart()
	lab._play()
	await get_tree().process_frame
	await get_tree().process_frame
	lab._restart()
	await get_tree().process_frame
	_check(not lab.left_hand.visible and not lab.right_hand.visible and lab.piece_views.values().all(func(piece): return not piece.visible), "restart safely cancels in-flight tracks and restores the empty setup frame")

	var override := ChessSetupMotionProfile.new()
	override.entry_duration = 1.23
	lab.setup_profile.cues[0].motion_override = override
	var preset: Resource = SetupPreset.new()
	preset.display_name = "Setup Round Trip"
	preset.setup_profile = lab.setup_profile.duplicate(true)
	preset.activation_snapshot = lab.activation_preset.duplicate(true)
	var path := "user://chess_setup_characterization.tres"
	_check(ResourceSaver.save(preset, path) == OK, "setup preset fixture saves")
	var loaded := ResourceLoader.load(path, "ChessSetupLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.is_supported() and loaded.setup_profile.cues.size() == 16 and is_equal_approx(loaded.setup_profile.cues[0].motion_override.entry_duration, 1.23) and loaded.activation_snapshot != null, "setup preset round-trips cue order, overrides, and activation fallback")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	lab.queue_free()
	if failures == 0:
		print("CHESS SETUP CHARACTERIZATION: PASS")
	else:
		printerr("CHESS SETUP CHARACTERIZATION: FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	printerr("FAIL: ", description)
