extends Node

const LAB := preload("res://tools/dev_chess_king_movement/chess_king_movement_lab.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var lab = LAB.instantiate()
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.board.get_world_scale() > 0.0 and lab.model.get_king("white").coordinate == Vector2i(4, 4), "lab uses the shipping board projection and centers its King", failures)
	_check(lab.playback_speed_selector.selected == 0 and is_equal_approx(lab.board.animation_duration_scale, 1.0), "lab defaults to Normal playback speed", failures)
	lab.playback_speed_selector.select(2)
	lab._set_playback_speed(2)
	_check(is_equal_approx(lab.board.animation_duration_scale, lab.adapter.presentation_policy.ultra_slow_duration_scale), "lab applies the shared Ultra Slow presentation speed", failures)
	lab.playback_speed_selector.select(0)
	lab._set_playback_speed(0)
	_check(lab.path_preview_toggle.button_pressed and lab.approach_path.visible and lab.swipe_path.visible and lab.retreat_path.visible, "hand path preview defaults to visible", failures)
	lab.path_preview_toggle.set_pressed_no_signal(false)
	lab._set_path_preview_visible(false)
	_check(not lab.approach_path.visible and not lab.swipe_path.visible and not lab.retreat_path.visible, "hand path preview toggle hides every trajectory segment", failures)
	lab.path_preview_toggle.set_pressed_no_signal(true)
	lab._set_path_preview_visible(true)
	_check(lab.knockoff_path_preview_toggle.button_pressed and not lab.knockoff_path.visible, "knockoff path preview defaults on but remains hidden outside Capture mode", failures)
	_check(lab.selected_destination == Vector2i(4, 5), "lab starts with a reusable adjacent destination", failures)
	lab._on_square_selected(Vector2i(3, 3))
	_check(lab.selected_destination == Vector2i(3, 3), "clicking any adjacent square selects its movement direction", failures)
	lab._on_square_selected(Vector2i(1, 1))
	_check(lab.selected_destination == Vector2i(3, 3), "non-adjacent board clicks do not replace the selected direction", failures)
	var selected_square: SquareView
	for square in lab.board.get_node("Squares").get_children():
		if square.coordinate == Vector2i(3, 3): selected_square = square
	_check(selected_square != null and selected_square.get_node("Highlight").visible, "selected destination remains visibly highlighted", failures)
	_check(lab.approach_path.points.size() == 2 and lab.swipe_path.points.size() == 2 and lab.retreat_path.points.size() > 12, "lab previews the complete approach, straight swipe, rounded turn, and tangent retreat path", failures)
	var swipe_delta: Vector2 = lab.swipe_path.points[1] - lab.swipe_path.points[0]
	var move_delta: Vector2 = lab.board.grid_to_screen(3, 3) - lab.board.grid_to_screen(4, 4)
	_check(absf(swipe_delta.normalized().cross(move_delta.normalized())) < 0.001, "path preview aligns its straight swipe with the selected board direction", failures)
	var original_lock: Vector2 = lab.swipe_path.points[0]
	lab.profile.gesture_sweep_distance += 40.0
	lab._refresh_hand_path()
	_check(lab.swipe_path.points[0].is_equal_approx(original_lock) and lab.swipe_path.points[1].distance_to(original_lock) > swipe_delta.length(), "swipe-length tuning moves only the preview endpoint and preserves its lock position", failures)
	lab.profile.hand_approach_duration = 0.01
	lab.profile.gesture_lock_duration = 0.0
	lab.profile.gesture_duration = 0.02
	lab.profile.king_move_delay = 0.01
	lab.profile.travel_duration = 0.01
	lab.profile.settle_duration = 0.0
	await lab._play()
	_check(lab.selected_destination == Vector2i(3, 3) and not lab.playing, "move playback completes without clearing the selected destination", failures)
	lab.capture_mode = true
	lab.profile.knockoff_horizontal_speed = 100000.0
	lab.profile.knockoff_upward_speed = 0.0
	lab.profile.knockoff_gravity = 1.0
	lab._rebuild_fixture()
	_check(lab.model.board[3][3] != null and not lab.model.board[3][3] is KingPiece, "Capture mode places a disposable target on the selected square", failures)
	_check(lab.knockoff_path.visible and lab.knockoff_path.points.size() == 65, "Capture mode previews the defender's complete ballistic knockoff arc", failures)
	lab.knockoff_path_preview_toggle.set_pressed_no_signal(false)
	lab._set_knockoff_path_preview_visible(false)
	_check(not lab.knockoff_path.visible and lab.approach_path.visible, "knockoff path toggle operates independently from the hand path preview", failures)
	lab.knockoff_path_preview_toggle.set_pressed_no_signal(true)
	lab._set_knockoff_path_preview_visible(true)
	var foreground_at_impact := {"active": false, "effective_rear_z": 0, "defender_z": 0}
	lab.profile.gesture_duration = 0.2
	lab.profile.king_move_delay = 0.05
	lab.profile.travel_duration = 0.05
	lab._play()
	var capture_magic: ChessKingMagicController = lab.adapter.get_king_magic_controller("white")
	capture_magic.capture_impact.connect(func(defender: PieceView):
		foreground_at_impact.active = lab.board.near_hand_rig.magical_foreground_active
		foreground_at_impact.effective_rear_z = lab.board.near_hand_rig.z_index + lab.board.near_hand_rig.grip_back_sprite.z_index
		foreground_at_impact.defender_z = defender.z_index
	, CONNECT_ONE_SHOT)
	while lab.playing:
		await get_tree().process_frame
	_check(foreground_at_impact.active and foreground_at_impact.effective_rear_z > foreground_at_impact.defender_z, "rebuilt lab controller retains ownership of the full foreground hand stack through capture impact", failures)
	_check(lab.selected_destination == Vector2i(3, 3) and not lab.playing, "capture playback also remains replayable in the chosen direction", failures)
	lab.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("CHESS KING MOVEMENT LAB CHARACTERIZATION: PASS (19 checks)")
		get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
