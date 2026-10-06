extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")
const ROUTER := preload("res://scripts/launch_router.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var sandbox = SANDBOX.instantiate()
	sandbox.force_mobile_layout_for_testing = true
	add_child(sandbox)
	await get_tree().process_frame
	var model: ChessBoardModel = sandbox.model
	var view: ChessBoardView = sandbox.get_node("ChessGame/CanvasLayer/ChessBoard")

	_check(ROUTER.destination_path(false) == ROUTER.GAME_SCENE_PATH, "normal builds route to the game", failures)
	_check(ROUTER.destination_path(true) == ROUTER.SANDBOX_SCENE_PATH, "sandbox builds route directly to the sandbox", failures)
	_check(sandbox.mobile_root != null and not sandbox.panel.visible, "mobile layout replaces the desktop panel", failures)
	_check(sandbox.mode_button.text == "Edit" and sandbox.undo_button.text == "Back" and sandbox.redo_button.text == "Forward", "mobile toolbar uses compact labels", failures)
	_check(sandbox.ai_mode_buttons.has(ChessCpuPlayer.ExecutionMode.DISABLED) and sandbox.ai_mode_buttons.has(ChessCpuPlayer.ExecutionMode.AUTO), "mobile AI panel exposes Off and Auto", failures)
	_check(not sandbox.ai_mode_buttons.has(ChessCpuPlayer.ExecutionMode.MANUAL), "mobile AI panel omits unusable Manual mode", failures)
	_check(sandbox.speed_slider == null and sandbox.grip_check == null and sandbox.view_side_button == null, "desktop-only tuning and view controls are omitted", failures)
	_check(sandbox.piece_palette.mobile_layout and sandbox.piece_palette.piece_items.size() == 10, "mobile tray exposes the complete ordinary piece palette", failures)
	_check(sandbox.piece_palette.king_select_button != null and sandbox.piece_palette.king_select_button.text.begins_with("Select King"), "king selection is a full tray button", failures)
	_check(sandbox.piece_palette.cursor_item.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "mobile piece tiles stretch to fill available tray width", failures)
	_route_touch_button(sandbox, sandbox.mode_button, 11)
	await get_tree().process_frame
	_check(sandbox.mode == sandbox.Mode.PLAY, "native touch activates top toolbar buttons", failures)
	_route_touch_button(sandbox, sandbox.mode_button, 11)
	await get_tree().process_frame
	_route_touch_button(sandbox, sandbox.piece_palette.king_select_button, 12)
	await get_tree().process_frame
	_check(sandbox.piece_palette.king_picker.visible, "Select King opens the in-scene mobile picker", failures)
	sandbox.piece_palette.king_picker.visible = false
	sandbox.piece_palette._select_mobile_king(1)
	_check(sandbox.piece_palette.king_selector.selected == 1 and sandbox.piece_palette.king_select_button.text.contains("Arakne"), "mobile king picker changes both king tiles", failures)
	var pawn_item = sandbox.piece_palette.piece_items["pawn:white"]
	_route_touch_button(sandbox, pawn_item, 13)
	_check(sandbox.editor.selected_type_id == &"pawn" and sandbox.editor.selected_color == "white", "root touch routing selects a piece from the tray", failures)

	sandbox.editor.select_palette_piece(&"queen", "black")
	sandbox.interaction._on_square_pressed(Vector2i(4, 4))
	_check(model.board[4][4] != null and model.board[4][4].get_position_type_id() == &"queen", "tap-to-place remains available", failures)
	sandbox.undo()
	sandbox.editor.select_cursor_tool()

	var source := Vector2i(6, 0)
	var destination := Vector2i(4, 0)
	var source_point := view.projection.get_cell_center(source)
	var destination_point := view.projection.get_cell_center(destination)
	var press := InputEventScreenTouch.new()
	press.index = 3
	press.position = source_point
	press.pressed = true
	sandbox.interaction._input(press)
	sandbox.interaction._on_square_pressed(source)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = destination_point
	sandbox.interaction._input(drag)
	var unrelated_release := InputEventScreenTouch.new()
	unrelated_release.index = 4
	unrelated_release.position = destination_point
	unrelated_release.pressed = false
	sandbox.interaction._input(unrelated_release)
	_check(sandbox.interaction.drag_source != BoardEditorInteraction.DragSource.NONE, "an unrelated finger cannot finish a drag", failures)
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.position = destination_point
	release.pressed = false
	sandbox.interaction._input(release)
	_check(model.board[destination.x][destination.y] != null and model.board[destination.x][destination.y].get_position_type_id() == &"pawn" and model.board[source.x][source.y] == null, "touch drag moves an existing board piece", failures)
	sandbox.undo()

	sandbox.editor.select_palette_piece(&"rook", "white")
	sandbox.interaction.begin_palette_drag(&"rook", "white", 7)
	var palette_drag := InputEventScreenDrag.new()
	palette_drag.index = 7
	palette_drag.position = view.projection.get_cell_center(Vector2i(4, 4))
	sandbox.interaction._input(palette_drag)
	var palette_release := InputEventScreenTouch.new()
	palette_release.index = 7
	palette_release.position = palette_drag.position
	palette_release.pressed = false
	sandbox.interaction._input(palette_release)
	_check(model.board[4][4] != null and model.board[4][4].get_position_type_id() == &"rook", "touch drag places a palette piece", failures)
	sandbox.undo()

	sandbox.interaction.begin_palette_drag(&"bishop", "black", 8)
	var outside_release := InputEventScreenTouch.new()
	outside_release.index = 8
	outside_release.position = Vector2(-100, -100)
	outside_release.pressed = false
	sandbox.interaction._input(outside_release)
	_check(model.board[4][4] == null and sandbox.interaction.drag_source == BoardEditorInteraction.DragSource.NONE, "off-board touch release cancels palette placement", failures)

	if failures.is_empty():
		print("MOBILE BOARD SANDBOX CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		printerr("MOBILE BOARD SANDBOX CHARACTERIZATION: FAIL")
		for failure in failures:
			printerr(" - ", failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _route_touch_button(sandbox, button: Control, pointer_index: int) -> void:
	var position := button.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = pointer_index
	press.position = position
	press.pressed = true
	sandbox._input(press)
	var release := InputEventScreenTouch.new()
	release.index = pointer_index
	release.position = position
	release.pressed = false
	sandbox._input(release)
