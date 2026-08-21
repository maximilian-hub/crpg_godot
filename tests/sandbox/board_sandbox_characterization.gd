extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")

func _ready() -> void:
	var sandbox = SANDBOX.instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	var model: ChessBoardModel = sandbox.model
	var view: ChessBoardView = sandbox.get_node("ChessGame/CanvasLayer/ChessBoard")
	var adapter: ChessPresentationAdapter = sandbox.get_node("ChessGame/ChessPresentationAdapter")
	var failures: Array[String] = []
	_check(model != null and sandbox.editor.editor_enabled, "sandbox starts in Edit Mode", failures)
	_check(model.capture_position().pieces.size() == 32, "sandbox starts at normal position", failures)
	_check(view.scale_world_with_projection, "sandbox inherits projection-scaled piece presentation", failures)
	_check(is_equal_approx(view.viewport_height_width_ratio, 1.0), "sandbox inherits fluid board height ratio", failures)
	_check(is_equal_approx(view.viewport_width_cap_ratio, 0.72), "sandbox inherits fluid board width cap", failures)
	_check(sandbox.mode_button.text == "Mode: Edit [P]", "mode button identifies Edit Mode and its shortcut", failures)
	_check(sandbox.undo_button.text == "Undo [←]" and sandbox.redo_button.text == "Redo [→]" and sandbox.reset_button.text == "Reset [R]", "history controls display keyboard shortcuts", failures)
	_check(sandbox.ai_mode_buttons[ChessCpuPlayer.ExecutionMode.DISABLED].button_pressed, "AI Off is visibly selected at startup", failures)
	_check(not sandbox.ai_side_buttons["white"].button_pressed and sandbox.ai_side_buttons["black"].button_pressed, "AI side toggles show the default Black selection", failures)
	_check(sandbox.speed_value_label.text == "Normal", "animation slider labels its startup state", failures)
	_check(not sandbox.grip_check.button_pressed, "Grip Anchors starts visibly unchecked", failures)
	_check(sandbox.editor.selected_tool == BoardEditorController.Tool.CURSOR and sandbox.piece_palette.cursor_item.selected_state, "Cursor starts visibly selected in the palette", failures)
	_check(sandbox.piece_palette.cursor_item.shortcut_label.text == "Esc", "Cursor tool displays its Escape shortcut", failures)
	_check(sandbox.piece_palette.delete_item != null and not sandbox.piece_palette.delete_item.selected_state, "Delete tool appears beside Cursor", failures)
	_check(ChessPieceCatalog.get_palette_type_ids(&"ordinary") == [&"pawn", &"knight", &"bishop", &"rook", &"queen"], "ordinary palette catalog order is stable", failures)
	_check(sandbox.piece_palette.piece_items.size() == 10 and sandbox.piece_palette.king_items.size() == 2, "palette exposes paired white and black sprite columns", failures)
	var palette_pawn = sandbox.piece_palette.piece_items["pawn:white"].preview
	var board_pawn = view.get_piece_node(Vector2i(6, 0))
	_check(palette_pawn.sprite.texture == board_pawn.sprite.texture, "palette previews reuse in-game PieceView artwork", failures)
	_check(sandbox.undo_button.disabled and sandbox.redo_button.disabled, "history actions start disabled", failures)
	_check(sandbox.reset_button.disabled and not sandbox.clear_button.disabled and not sandbox.paste_button.disabled, "editor action buttons expose their actual startup availability", failures)
	_check(sandbox.think_button.disabled and sandbox.step_button.disabled and sandbox.execute_button.disabled, "manual AI buttons are unclickable while AI is unavailable", failures)
	_check(sandbox.undo_button.focus_mode == Control.FOCUS_NONE and sandbox.think_button.focus_mode == Control.FOCUS_NONE, "disabled buttons cannot retain a white focus highlight", failures)
	sandbox.clear_button.grab_focus()
	_press_key(sandbox, KEY_P)
	_check(sandbox.mode == sandbox.Mode.EDIT, "focused controls suppress sandbox shortcuts", failures)
	_press_key(sandbox, KEY_ESCAPE)
	_check(get_viewport().gui_get_focus_owner() == null and sandbox.editor.selected_tool == BoardEditorController.Tool.CURSOR, "Escape releases focus and restores Cursor in Edit Mode", failures)
	sandbox.editor.select_delete_tool()
	_press_key(sandbox, KEY_P, true)
	_check(sandbox.mode == sandbox.Mode.EDIT, "echo key events do not trigger shortcuts", failures)
	_press_key(sandbox, KEY_P)
	_press_key(sandbox, KEY_ESCAPE)
	_check(sandbox.mode == sandbox.Mode.PLAY and sandbox.editor.selected_tool == BoardEditorController.Tool.DELETE, "Escape does nothing in Play Mode", failures)
	_press_key(sandbox, KEY_P)
	_press_key(sandbox, KEY_ESCAPE)
	_check(sandbox.mode == sandbox.Mode.EDIT and sandbox.editor.selected_tool == BoardEditorController.Tool.CURSOR, "P toggles modes and Escape restores Cursor after returning to Edit Mode", failures)
	view._on_square_selected(Vector2i(4, 4))
	_check(get_viewport().gui_get_focus_owner() == null, "board clicks release GUI focus", failures)
	var initial_count := _count(model)
	sandbox.interaction._on_square_pressed(Vector2i(4, 4))
	_check(_count(model) == initial_count, "Cursor tool does not spawn on an empty square", failures)
	sandbox.editor.select_delete_tool()
	sandbox.interaction._on_square_pressed(Vector2i(6, 0))
	await get_tree().process_frame
	_check(model.board[6][0] == null and sandbox.piece_palette.delete_item.selected_state, "Delete tool removes a clicked piece through editor mutation", failures)
	_press_key(sandbox, KEY_LEFT)
	_check(model.board[6][0] != null, "Left Arrow performs Undo", failures)
	_press_key(sandbox, KEY_RIGHT)
	_check(model.board[6][0] == null, "Right Arrow performs Redo", failures)
	_press_key(sandbox, KEY_LEFT)
	await get_tree().process_frame
	sandbox.editor.select_cursor_tool()
	sandbox.editor.select_palette_piece(&"pawn", "white")
	sandbox.interaction.begin_palette_drag(&"pawn", "white")
	_press_key(sandbox, KEY_ESCAPE)
	_check(sandbox.editor.selected_tool == BoardEditorController.Tool.CURSOR and sandbox.interaction.drag_source == sandbox.interaction.DragSource.NONE and sandbox.interaction.drag_ghost == null, "Escape cancels palette drag state and restores Cursor", failures)
	sandbox.editor.select_palette_piece(&"queen", "black")
	sandbox.editor.place_selected(Vector2i(4, 4))
	_press_key(sandbox, KEY_R)
	_check(model.board[4][4] == null and sandbox.history.cursor == 0, "R restores the sandbox baseline and resets history", failures)
	sandbox.editor.select_cursor_tool()
	var first_square: Node = view.get_node("Squares").get_child(0)
	sandbox.editor.clear_board()
	await get_tree().process_frame
	_check(_count(model) == 0, "sandbox Clear empties authoritative model", failures)
	_check(view.get_node("Pieces").get_child_count() == 0 and adapter.piece_views.is_empty(), "whole-board rebuild removes stale PieceViews", failures)
	_check(is_instance_valid(first_square) and view.get_node("Squares").get_child(0) == first_square, "position rebuild preserves square input nodes", failures)
	_check(not sandbox.undo_button.disabled and sandbox.redo_button.disabled, "history buttons reflect a committed edit", failures)
	sandbox.undo()
	await get_tree().process_frame
	_check(_count(model) == 32, "sandbox Undo restores model", failures)
	_check(view.get_node("Pieces").get_child_count() == 32 and adapter.piece_views.size() == 32, "sandbox Undo rebuilds presentation mapping", failures)
	_check(not sandbox.redo_button.disabled, "Redo becomes available after Undo", failures)
	var empty_square: SquareView = null
	for square in view.get_node("Squares").get_children():
		if square.coordinate == Vector2i(4, 4):
			empty_square = square
			break
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	sandbox.editor.select_palette_piece(&"pawn", "white")
	empty_square._on_input_event(null, click, 0)
	await get_tree().process_frame
	_check(model.board[4][4] != null and is_instance_valid(empty_square), "click-to-place preserves the input-emitting square", failures)
	sandbox.editor.select_palette_piece(&"queen", "black")
	empty_square._on_input_event(null, click, 0)
	await get_tree().process_frame
	_check(model.board[4][4] != null and model.board[4][4].type == "queen" and model.board[4][4].color == "black", "piece-tool click replaces an occupied square", failures)
	sandbox.undo()
	await get_tree().process_frame
	sandbox.undo()
	await get_tree().process_frame
	sandbox.editor.select_cursor_tool()
	sandbox.interaction._on_square_pressed(Vector2i(6, 0))
	_check(sandbox.interaction.requested_cursor_shape == Input.CURSOR_DRAG, "picking up a piece displays the drag cursor", failures)
	_check(is_instance_valid(sandbox.interaction.drag_ghost) and is_equal_approx(sandbox.interaction.drag_ghost.modulate.a, 0.55), "dragging displays a translucent piece ghost", failures)
	sandbox.interaction._on_square_exited(Vector2i(6, 0))
	_check(sandbox.interaction.requested_cursor_shape == Input.CURSOR_FORBIDDEN, "dragging off-board displays the forbidden cursor", failures)
	sandbox.interaction._on_square_entered(Vector2i(4, 4))
	_check(sandbox.interaction.requested_cursor_shape == Input.CURSOR_CAN_DROP, "dragging over a destination displays the drop cursor", failures)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	sandbox.interaction._input(release)
	_check(sandbox.interaction.requested_cursor_shape == Input.CURSOR_ARROW, "finishing a drag restores the default cursor", failures)
	_check(sandbox.interaction.drag_ghost == null, "finishing a drag removes the piece ghost", failures)
	sandbox.undo()
	await get_tree().process_frame
	sandbox.editor.select_palette_piece(&"queen", "black")
	sandbox.interaction.begin_palette_drag(&"queen", "black")
	sandbox.interaction._on_square_entered(Vector2i(4, 4))
	sandbox.interaction._input(release)
	await get_tree().process_frame
	_check(model.board[4][4] != null and model.board[4][4].type == "queen" and model.board[4][4].color == "black", "palette drag places the requested piece", failures)
	sandbox.undo()
	await get_tree().process_frame
	var count_before_cancel := _count(model)
	sandbox.interaction.begin_palette_drag(&"rook", "white")
	sandbox.interaction._on_square_exited(Vector2i(4, 4))
	sandbox.interaction._input(release)
	_check(_count(model) == count_before_cancel, "dropping a palette piece off-board cancels without mutation", failures)
	sandbox.piece_palette.king_selector.select(1)
	sandbox.editor.select_palette_piece(&"classic_king", "white")
	sandbox.piece_palette._on_king_selected(1)
	_check(sandbox.piece_palette.king_items["white"].type_id == &"arakne_king" and sandbox.piece_palette.king_items["black"].type_id == &"arakne_king", "king selector rebuilds both color previews", failures)
	_check(sandbox.editor.selected_type_id == &"arakne_king" and sandbox.editor.selected_color == "white", "king selector updates an active king tool while preserving color", failures)
	sandbox._toggle_ai_side("white")
	sandbox._set_mode(sandbox.Mode.PLAY)
	_check(not sandbox.piece_palette.palette_enabled and sandbox.piece_palette.king_selector.disabled, "Play Mode leaves the palette visible but disabled", failures)
	_check(sandbox.clear_button.disabled and sandbox.paste_button.disabled and sandbox.turn_option.disabled, "editor-only controls are unclickable in Play Mode", failures)
	sandbox._configure_ai(ChessCpuPlayer.ExecutionMode.MANUAL)
	_check(sandbox.ai_side_buttons["white"].button_pressed and sandbox.ai_side_buttons["black"].button_pressed, "White and Black AI sides can be selected together", failures)
	_check(sandbox.game.white_cpu_player.execution_mode == ChessCpuPlayer.ExecutionMode.MANUAL and sandbox.game.black_cpu_player.execution_mode == ChessCpuPlayer.ExecutionMode.MANUAL, "both selected sides receive Manual AI mode", failures)
	_check(not sandbox.think_button.disabled and not sandbox.step_button.disabled, "manual AI controls become clickable when the current side is available", failures)
	_check(sandbox.think_button.focus_mode == Control.FOCUS_ALL and sandbox.step_button.focus_mode == Control.FOCUS_ALL, "re-enabled controls restore normal focus behavior", failures)
	sandbox.think_ai()
	_check(sandbox.thought_label.text != "No prepared action" and not sandbox.execute_button.disabled, "Think displays a prepared action and enables Execute", failures)
	sandbox._on_seed_changed(9)
	_check(sandbox.thought_label.text == "No prepared action" and sandbox.execute_button.disabled, "seed changes clear prepared AI actions", failures)
	sandbox._set_speed(sandbox.PresentationPolicy.Speed.SLOW)
	_check(sandbox.speed_value_label.text == "Slow" and int(sandbox.speed_slider.value) == sandbox.PresentationPolicy.Speed.SLOW and is_equal_approx(adapter.presentation_policy.duration_scale(), 2.0), "animation slider exposes a double-duration Slow speed", failures)
	sandbox._set_speed(sandbox.PresentationPolicy.Speed.FAST)
	_check(sandbox.speed_value_label.text == "Fast" and int(sandbox.speed_slider.value) == sandbox.PresentationPolicy.Speed.FAST, "animation slider and label synchronize", failures)
	sandbox._on_grip_toggled(true)
	_check(sandbox.grip_check.button_pressed and view.show_piece_grip_anchors, "Grip Anchors check state mirrors the board", failures)
	var grip_overlay: Node2D = view.get_node("Pieces").get_child(0).get_node("GripAnchorDebugOverlay")
	_check(grip_overlay.visible and grip_overlay.z_index > 0, "grip anchor indicators render in a foreground piece overlay", failures)
	sandbox._configure_ai(ChessCpuPlayer.ExecutionMode.DISABLED)
	sandbox._set_speed(sandbox.PresentationPolicy.Speed.INSTANT)
	await model.submit_move(model.board[6][0], Vector2i(4, 0))
	await model.submit_move(model.board[1][0], Vector2i(3, 0))
	_check(_timers_nonnegative(model), "completed gameplay actions never create negative timers", failures)
	sandbox.undo()
	await get_tree().process_frame
	_check(model.board[1][0] != null and model.board[3][0] == null and model.board[4][0] != null, "first gameplay Undo restores the intermediate model position", failures)
	_check(view.get_piece_node(Vector2i(1, 0)) != null and view.get_piece_node(Vector2i(3, 0)) == null and view.get_piece_node(Vector2i(4, 0)) != null, "first gameplay Undo visually restores the intermediate position", failures)
	sandbox.undo()
	await get_tree().process_frame
	_check(model.board[6][0] != null and model.board[4][0] == null, "second gameplay Undo restores the baseline", failures)
	if failures.is_empty():
		print("BOARD SANDBOX CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)

func _count(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null: count += 1
	return count

func _timers_nonnegative(model: ChessBoardModel) -> bool:
	for row in model.board:
		for piece in row:
			if piece != null:
				if piece.stun_timer < 0:
					return false
				if piece is KingPiece and (piece as KingPiece).current_cooldown < 0:
					return false
	return true

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)

func _press_key(sandbox, keycode: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = echo
	sandbox._unhandled_key_input(event)
