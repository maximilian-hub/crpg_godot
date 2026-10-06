extends Node
class_name BoardSandbox

const PresentationPolicy = preload("res://scripts/view/chess_presentation_policy.gd")
const BoardPiecePaletteScript = preload("res://scripts/editor/board_piece_palette.gd")

enum Mode { EDIT, PLAY }

@export var force_mobile_layout_for_testing := false

const COLOR_INACTIVE := Color("252331")
const COLOR_EDIT := Color("2878c7")
const COLOR_PLAY := Color("d36a25")
const COLOR_AUTO := Color("2d9b59")
const COLOR_MANUAL := Color("c58a24")
const COLOR_GOLD := Color("d1a43a")
const COLOR_CYAN := Color("28b8c7")
const COLOR_ULTRA_SLOW := Color("7659b8")
const COLOR_SLOW := Color("668dcc")
const COLOR_INSTANT := Color("b34fb5")
const COLOR_WHITE_SIDE := Color("e8e2d2")
const COLOR_BLACK_SIDE := Color("5b5568")

@onready var game: ChessGame = $ChessGame
@onready var model: ChessBoardModel = $ChessGame/ChessModel
@onready var game_controller: ChessBoardController = $ChessGame/ChessController
@onready var editor: BoardEditorController = $BoardEditorController
@onready var interaction: BoardEditorInteraction = $BoardEditorInteraction
@onready var panel: VBoxContainer = $SandboxLayer/Panel

var mode := Mode.EDIT
var history := BoardPositionHistory.new()
var restoring_history := false
var baseline: ChessPosition
var ai_mode := ChessCpuPlayer.ExecutionMode.DISABLED
var ai_sides := {"white": false, "black": true}
var seed_value := 1

var mode_button: Button
var view_side_button: Button
var undo_button: Button
var redo_button: Button
var reset_button: Button
var clear_button: Button
var copy_button: Button
var paste_button: Button
var ai_mode_buttons := {}
var ai_side_buttons := {}
var think_button: Button
var step_button: Button
var speed_slider: HSlider
var speed_value_label: Label
var cooldowns_check: CheckButton
var grip_check: CheckButton
var grip_profile_option: OptionButton
var grip_x_spin: SpinBox
var grip_y_spin: SpinBox
var grip_save_button: Button
var grip_status_label: Label
var seed_spin: SpinBox
var preset_option: OptionButton
var turn_option: OptionButton
var piece_palette
var thought_label: Label
var execute_button: Button
var grip_profile_ids: Array[StringName] = []
var syncing_grip_controls := false
var mobile_layout := false
var mobile_root: Control
var mobile_ai_panel: PanelContainer
var mobile_palette_button: Button
var mobile_toolbar_panel: PanelContainer
var reset_confirmation: ConfirmationDialog
var clear_confirmation: ConfirmationDialog
var mobile_ui_pointer := -1
var mobile_ui_touch_target: Variant = null
var mobile_button_callbacks: Dictionary = {}

func _ready() -> void:
	mobile_layout = force_mobile_layout_for_testing or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	editor.model = model
	var board_view: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	interaction.configure(model, editor, board_view)
	board_view.square_selected.connect(_release_gui_focus)
	editor.edit_committed.connect(_on_edit_committed)
	editor.tool_selection_changed.connect(func(_tool: BoardEditorController.Tool, _type_id: StringName, _color: String): _refresh_control_states())
	model.settled_action_completed.connect(_on_settled_action_completed)
	model.action_started.connect(func(_owner_color: String): _refresh_control_states())
	model.action_finished.connect(_refresh_control_states)
	model.action_cancelled.connect(_refresh_control_states)
	model.board_rebuilt.connect(_on_board_rebuilt)
	history.changed.connect(func(_can_undo: bool, _can_redo: bool): _refresh_control_states())
	game.white_cpu_player.thought_changed.connect(func(_thought): _refresh_control_states())
	game.black_cpu_player.thought_changed.connect(func(_thought): _refresh_control_states())
	_build_panel()
	_set_mode(Mode.EDIT)
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Normal Start")
	_refresh_control_states()

func _build_panel() -> void:
	if mobile_layout:
		_build_mobile_panel()
	else:
		_build_desktop_panel()

func _build_desktop_panel() -> void:
	mode_button = _add_button("", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	view_side_button = _add_button("", _toggle_viewing_side)
	var history_row := HBoxContainer.new()
	panel.add_child(history_row)
	undo_button = _add_button_to(history_row, "Undo [←]", undo)
	redo_button = _add_button_to(history_row, "Redo [→]", redo)
	reset_button = _add_button("Reset [R]", reset)
	clear_button = _add_button("Clear", func(): editor.clear_board())
	copy_button = _add_button("Copy Position", copy_position)
	paste_button = _add_button("Paste Position", paste_position)

	_add_section_label("AI Mode")
	var mode_row := HBoxContainer.new()
	panel.add_child(mode_row)
	_add_ai_mode_button(mode_row, "Off", ChessCpuPlayer.ExecutionMode.DISABLED)
	_add_ai_mode_button(mode_row, "Auto", ChessCpuPlayer.ExecutionMode.AUTO)
	_add_ai_mode_button(mode_row, "Manual", ChessCpuPlayer.ExecutionMode.MANUAL)

	_add_section_label("AI Sides")
	var side_row := HBoxContainer.new()
	panel.add_child(side_row)
	_add_ai_side_button(side_row, "White", "white")
	_add_ai_side_button(side_row, "Black", "black")

	think_button = _add_button("AI Think", think_ai)
	execute_button = _add_button("AI Execute", execute_ai)
	step_button = _add_button("AI Step", step_ai)
	thought_label = Label.new()
	thought_label.text = "No prepared action"
	thought_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thought_label.custom_minimum_size.x = 168.0
	panel.add_child(thought_label)

	_add_section_label("Animation Speed")
	var speed_row := HBoxContainer.new()
	panel.add_child(speed_row)
	speed_slider = HSlider.new()
	speed_slider.min_value = PresentationPolicy.Speed.ULTRA_SLOW
	speed_slider.max_value = PresentationPolicy.Speed.INSTANT
	speed_slider.step = 1.0
	speed_slider.value = PresentationPolicy.Speed.NORMAL
	speed_slider.custom_minimum_size.x = 104.0
	speed_slider.value_changed.connect(func(value: float): _set_speed(int(value)))
	speed_row.add_child(speed_slider)
	speed_value_label = Label.new()
	speed_value_label.custom_minimum_size.x = 72.0
	speed_row.add_child(speed_value_label)

	cooldowns_check = CheckButton.new()
	cooldowns_check.text = "Disable Cooldowns"
	cooldowns_check.tooltip_text = "Keep King active abilities ready for sandbox testing"
	cooldowns_check.toggled.connect(_on_cooldowns_toggled)
	panel.add_child(cooldowns_check)

	grip_check = CheckButton.new()
	grip_check.text = "Grip Anchors"
	grip_check.toggled.connect(_on_grip_toggled)
	panel.add_child(grip_check)

	_add_section_label("Piece Grip Tuning")
	grip_profile_option = OptionButton.new()
	for profile_id in PieceView.PIECE_ART_PROFILES.keys():
		grip_profile_ids.append(profile_id)
	grip_profile_ids.sort()
	for profile_id in grip_profile_ids:
		grip_profile_option.add_item(String(profile_id).capitalize())
	grip_profile_option.item_selected.connect(_load_grip_profile_controls)
	_add_labeled_control("Piece", grip_profile_option)
	var grip_row := HBoxContainer.new()
	panel.add_child(grip_row)
	grip_x_spin = _make_grip_spin_box()
	grip_y_spin = _make_grip_spin_box()
	grip_row.add_child(_make_compact_labeled_control("X", grip_x_spin))
	grip_row.add_child(_make_compact_labeled_control("Y", grip_y_spin))
	grip_x_spin.value_changed.connect(func(_value: float): _apply_live_piece_grip())
	grip_y_spin.value_changed.connect(func(_value: float): _apply_live_piece_grip())
	grip_save_button = _add_button("Save Piece Grip", _save_piece_grip)
	grip_status_label = Label.new()
	grip_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(grip_status_label)
	_load_grip_profile_controls(0)

	seed_spin = SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 2147483647
	seed_spin.value = seed_value
	seed_spin.value_changed.connect(_on_seed_changed)
	_add_labeled_control("AI Seed", seed_spin)

	preset_option = OptionButton.new()
	preset_option.add_item("Normal Start")
	preset_option.add_item("Empty Board")
	preset_option.add_item("Debug Layout")
	preset_option.item_selected.connect(_on_preset_selected)
	_add_labeled_control("Preset", preset_option)

	turn_option = OptionButton.new()
	turn_option.add_item("White")
	turn_option.add_item("Black")
	turn_option.item_selected.connect(func(index: int): editor.set_current_turn("white" if index == 0 else "black"))
	_add_labeled_control("Side to Move", turn_option)

	piece_palette = BoardPiecePaletteScript.new()
	piece_palette.name = "PiecePalette"
	piece_palette.cursor_selected.connect(editor.select_cursor_tool)
	piece_palette.delete_selected.connect(editor.select_delete_tool)
	piece_palette.piece_selected.connect(editor.select_palette_piece)
	piece_palette.piece_drag_requested.connect(_on_palette_piece_drag_requested)
	$SandboxLayer.add_child(piece_palette)
	piece_palette.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	piece_palette.offset_left = -180.0
	piece_palette.offset_top = 140.0
	piece_palette.offset_right = -12.0
	piece_palette.offset_bottom = 140.0

func _build_mobile_panel() -> void:
	panel.visible = false
	mobile_root = Control.new()
	mobile_root.name = "MobileSandboxControls"
	mobile_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SandboxLayer.add_child(mobile_root)

	mobile_toolbar_panel = PanelContainer.new()
	mobile_toolbar_panel.name = "Toolbar"
	mobile_toolbar_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mobile_root.add_child(mobile_toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	mobile_toolbar_panel.add_child(toolbar)
	mode_button = _add_button_to(toolbar, "", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	undo_button = _add_button_to(toolbar, "Back", undo)
	redo_button = _add_button_to(toolbar, "Forward", redo)
	reset_button = _add_button_to(toolbar, "Reset", reset)
	clear_button = _add_button_to(toolbar, "Clear", func(): editor.clear_board())
	mobile_palette_button = _add_button_to(toolbar, "Pieces", _toggle_mobile_palette)
	_add_button_to(toolbar, "AI", _toggle_mobile_ai_panel)

	mobile_ai_panel = PanelContainer.new()
	mobile_ai_panel.name = "AISettings"
	mobile_ai_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mobile_ai_panel.offset_left = -286.0
	mobile_ai_panel.offset_top = 74.0
	mobile_ai_panel.offset_right = -16.0
	mobile_ai_panel.offset_bottom = 238.0
	mobile_ai_panel.visible = false
	mobile_root.add_child(mobile_ai_panel)
	var ai_column := VBoxContainer.new()
	ai_column.add_theme_constant_override("separation", 6)
	mobile_ai_panel.add_child(ai_column)
	var ai_title := Label.new()
	ai_title.text = "AI Mode"
	ai_column.add_child(ai_title)
	var mode_row := HBoxContainer.new()
	ai_column.add_child(mode_row)
	_add_ai_mode_button(mode_row, "Off", ChessCpuPlayer.ExecutionMode.DISABLED)
	_add_ai_mode_button(mode_row, "Auto", ChessCpuPlayer.ExecutionMode.AUTO)
	var sides_title := Label.new()
	sides_title.text = "AI Sides"
	ai_column.add_child(sides_title)
	var side_row := HBoxContainer.new()
	ai_column.add_child(side_row)
	_add_ai_side_button(side_row, "White", "white")
	_add_ai_side_button(side_row, "Black", "black")
	cooldowns_check = CheckButton.new()
	cooldowns_check.text = "Disable Cooldowns"
	cooldowns_check.toggled.connect(_on_cooldowns_toggled)
	ai_column.add_child(cooldowns_check)

	piece_palette = BoardPiecePaletteScript.new()
	piece_palette.name = "PiecePalette"
	piece_palette.configure_mobile_layout()
	piece_palette.cursor_selected.connect(editor.select_cursor_tool)
	piece_palette.delete_selected.connect(editor.select_delete_tool)
	piece_palette.piece_selected.connect(editor.select_palette_piece)
	piece_palette.piece_drag_requested.connect(_on_palette_piece_drag_requested)
	mobile_root.add_child(piece_palette)
	piece_palette.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	piece_palette.offset_left = 16.0
	piece_palette.offset_top = -108.0
	piece_palette.offset_right = -16.0
	piece_palette.offset_bottom = -12.0

	reset_confirmation = _make_confirmation("Reset position?", "Restore the normal starting position and discard position history.", reset)
	clear_confirmation = _make_confirmation("Clear position?", "Remove every piece from the board? This can be undone.", func(): editor.clear_board())
	get_viewport().size_changed.connect(_layout_mobile_controls)
	_layout_mobile_controls()

func _layout_mobile_controls() -> void:
	if mobile_root == null:
		return
	var left := 16.0
	var right := 16.0
	var top := 12.0
	var bottom := 12.0
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var viewport_size := get_viewport().get_visible_rect().size
	if screen_size.x > 0.0 and screen_size.y > 0.0 and viewport_size.x > 0.0 and viewport_size.y > 0.0:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var scale := viewport_size / screen_size
		left = maxf(left, safe.position.x * scale.x)
		right = maxf(right, (screen_size.x - safe.end.x) * scale.x)
		top = maxf(top, safe.position.y * scale.y)
		bottom = maxf(bottom, (screen_size.y - safe.end.y) * scale.y)
	mobile_toolbar_panel.offset_left = left
	mobile_toolbar_panel.offset_top = top
	mobile_toolbar_panel.offset_right = -right
	mobile_toolbar_panel.offset_bottom = top + 54.0
	mobile_ai_panel.offset_left = -(right + 270.0)
	mobile_ai_panel.offset_top = top + 62.0
	mobile_ai_panel.offset_right = -right
	mobile_ai_panel.offset_bottom = top + 226.0
	piece_palette.offset_left = left
	piece_palette.offset_top = -(bottom + 96.0)
	piece_palette.offset_right = -right
	piece_palette.offset_bottom = -bottom

func _make_confirmation(title: String, message: String, callback: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(callback)
	mobile_root.add_child(dialog)
	_enable_mobile_touch_activation(dialog.get_ok_button())
	_enable_mobile_touch_activation(dialog.get_cancel_button())
	return dialog

func _request_reset() -> void:
	reset_confirmation.popup_centered(Vector2i(460, 190))

func _request_clear() -> void:
	clear_confirmation.popup_centered(Vector2i(460, 190))

func _toggle_mobile_palette() -> void:
	piece_palette.visible = not piece_palette.visible
	if piece_palette.visible:
		mobile_ai_panel.visible = false

func _toggle_mobile_ai_panel() -> void:
	mobile_ai_panel.visible = not mobile_ai_panel.visible
	if mobile_ai_panel.visible:
		piece_palette.visible = false

func _on_palette_piece_drag_requested(type_id: StringName, color: String) -> void:
	if editor.select_palette_piece(type_id, color):
		var pointer_index: int = piece_palette.last_drag_pointer_index
		var initial_position: Vector2 = piece_palette.last_drag_viewport_position if pointer_index >= 0 else Vector2.INF
		interaction.begin_palette_drag(type_id, color, pointer_index, initial_position)

func _release_gui_focus(_coordinate := Vector2i.ZERO) -> void:
	get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if mobile_layout and _route_mobile_ui_touch(event):
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_release_text_focus_if_scene_clicked(get_viewport().gui_get_hovered_control())

func _route_mobile_ui_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if mobile_ui_pointer >= 0:
				return false
			mobile_ui_touch_target = _mobile_button_at(touch.position)
			if mobile_ui_touch_target != null:
				pass
			elif piece_palette != null and piece_palette.mobile_contains(touch.position):
				if not piece_palette.handle_mobile_touch_pressed(touch.position, touch.index):
					return false
				mobile_ui_touch_target = piece_palette
			else:
				return false
			mobile_ui_pointer = touch.index
			get_viewport().set_input_as_handled()
			return true
		if touch.index != mobile_ui_pointer:
			return false
		if mobile_ui_touch_target == piece_palette:
			if interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
				interaction._input(touch)
			piece_palette.handle_mobile_touch_released(touch.index)
		elif mobile_ui_touch_target is Button:
			var button := mobile_ui_touch_target as Button
			if not button.disabled and button.get_global_rect().has_point(touch.position):
				var callback: Callable = mobile_button_callbacks.get(button, Callable())
				if callback.is_valid():
					callback.call()
		mobile_ui_pointer = -1
		mobile_ui_touch_target = null
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != mobile_ui_pointer:
			return false
		if mobile_ui_touch_target == piece_palette:
			piece_palette.handle_mobile_touch_drag(drag.position, drag.index)
			if interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
				interaction._input(drag)
		get_viewport().set_input_as_handled()
		return true
	return false

func _mobile_button_at(position: Vector2) -> Button:
	for candidate: Button in mobile_button_callbacks:
		if candidate.is_visible_in_tree() and candidate.get_global_rect().has_point(position):
			return candidate
	return null


func _release_text_focus_if_scene_clicked(hovered_control: Control) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if _is_text_input(focus_owner) and hovered_control == null:
		_release_gui_focus()


func _is_text_input(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		if key_event.keycode == KEY_ESCAPE and mode == Mode.EDIT:
			_release_gui_focus()
			_restore_cursor_tool()
			get_viewport().set_input_as_handled()
			return
		if _is_text_input(focus_owner):
			return

	match key_event.keycode:
		KEY_LEFT:
			if not undo_button.disabled:
				undo()
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if not redo_button.disabled:
				redo()
				get_viewport().set_input_as_handled()
		KEY_P:
			if not mode_button.disabled:
				_set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT)
				get_viewport().set_input_as_handled()
		KEY_R:
			if not reset_button.disabled:
				reset()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if mode == Mode.EDIT:
				_restore_cursor_tool()
				get_viewport().set_input_as_handled()

func _restore_cursor_tool() -> void:
	interaction.cancel_drag()
	editor.select_cursor_tool()


func _toggle_viewing_side() -> void:
	if not model.is_settled():
		return
	_restore_cursor_tool()
	var board_view: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	game.set_viewing_color("black" if board_view.viewing_color == "white" else "white")
	_refresh_control_states()

func _add_ai_mode_button(parent: Control, label: String, value: ChessCpuPlayer.ExecutionMode) -> void:
	var button := _add_button_to(parent, label, func(): _configure_ai(value))
	button.toggle_mode = true
	ai_mode_buttons[value] = button

func _add_ai_side_button(parent: Control, label: String, color: String) -> void:
	var button := _add_button_to(parent, label, func(): _toggle_ai_side(color))
	button.toggle_mode = true
	ai_side_buttons[color] = button

func _add_labeled_control(label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 76.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	panel.add_child(row)

func _make_compact_labeled_control(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _make_grip_spin_box() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -256.0
	spin.max_value = 256.0
	spin.step = 1.0
	spin.allow_lesser = true
	spin.allow_greater = true
	return spin

func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("d8c6a0"))
	panel.add_child(label)

func _add_button(label: String, callback: Callable) -> Button:
	return _add_button_to(panel, label, callback)

func _add_button_to(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	_style_button(button, false, COLOR_INACTIVE)
	if mobile_layout:
		mobile_button_callbacks[button] = callback
		_enable_mobile_touch_activation(button)
	return button

func _enable_mobile_touch_activation(button: Button) -> void:
	if button == null or button.has_meta(&"mobile_touch_enabled"):
		return
	button.set_meta(&"mobile_touch_enabled", true)
	button.gui_input.connect(func(event: InputEvent):
		if not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			button.set_meta(&"mobile_touch_index", touch.index)
			button.accept_event()
			return
		if int(button.get_meta(&"mobile_touch_index", -1)) != touch.index:
			return
		button.set_meta(&"mobile_touch_index", -1)
		button.accept_event()
		if not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(touch.position):
			button.pressed.emit()
	)

func _set_mode(next: Mode) -> void:
	if not model.is_settled():
		return
	mode = next
	editor.set_enabled(mode == Mode.EDIT)
	if piece_palette != null:
		piece_palette.set_palette_enabled(mode == Mode.EDIT)
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()
	if mode == Mode.PLAY:
		model.resolve_unplayable_turns()

func _on_edit_committed(_before: ChessPosition, after: ChessPosition, label: String) -> void:
	if not restoring_history:
		history.push(after, label)
	_refresh_control_states()

func _on_settled_action_completed() -> void:
	_clear_ai_thoughts()
	if mode == Mode.PLAY and not restoring_history:
		history.push(model.capture_position(), "Gameplay action")
	_refresh_control_states()

func _on_board_rebuilt(_board: Array) -> void:
	_clear_ai_thoughts()
	_refresh_control_states()

func undo() -> void:
	_restore(history.undo())

func redo() -> void:
	_restore(history.redo())

func reset() -> void:
	_restore(history.get_baseline())
	if baseline != null:
		history.establish_baseline(baseline)

func _restore(position: ChessPosition) -> void:
	if position == null or not model.is_settled():
		return
	restoring_history = true
	model.load_position(position)
	restoring_history = false
	_refresh_control_states()

func _on_preset_selected(index: int) -> void:
	var position := ChessPositionPresets.normal_start()
	if index == 1:
		position = ChessPositionPresets.empty()
	if index == 2:
		position = ChessPositionPresets.debug_layout()
	if not editor.editor_enabled:
		_set_mode(Mode.EDIT)
	restoring_history = true
	model.load_position(position)
	restoring_history = false
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Preset")
	editor.select_cursor_tool()
	_refresh_control_states()

func _toggle_ai_side(color: String) -> void:
	ai_sides[color] = not ai_sides[color]
	_clear_ai_thoughts()
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()

func _configure_ai(next_mode: ChessCpuPlayer.ExecutionMode) -> void:
	ai_mode = next_mode
	_clear_ai_thoughts()
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()

func _apply_ai_configuration() -> void:
	game.white_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "white")
	game.black_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "black")
	if mode != Mode.PLAY or ai_mode == ChessCpuPlayer.ExecutionMode.DISABLED:
		return
	for color in ["white", "black"]:
		if ai_sides[color]:
			var cpu := game.white_cpu_player if color == "white" else game.black_cpu_player
			cpu.set_random_seed(seed_value)
			cpu.configure_mode(ai_mode, color)

func _apply_play_control() -> void:
	var colors: Array[String] = []
	if mode == Mode.PLAY:
		colors.assign(["white", "black"])
		if ai_mode != ChessCpuPlayer.ExecutionMode.DISABLED:
			for color in ["white", "black"]:
				if ai_sides[color]:
					colors.erase(color)
	game_controller.configure_player_controlled_colors(colors)

func _manual_cpu() -> ChessCpuPlayer:
	if not ai_sides.get(model.current_turn, false):
		return null
	return game.white_cpu_player if model.current_turn == "white" else game.black_cpu_player

func think_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		cpu.think()
	_refresh_control_states()

func execute_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		await cpu.execute_thought()
	_refresh_control_states()

func step_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		await cpu.step()
	_refresh_control_states()

func _on_seed_changed(value: float) -> void:
	seed_value = int(value)
	game.white_cpu_player.set_random_seed(seed_value)
	game.black_cpu_player.set_random_seed(seed_value)
	_refresh_control_states()

func copy_position() -> void:
	DisplayServer.clipboard_set(ChessPositionCodec.to_json(model.capture_position()))

func paste_position() -> void:
	if mode != Mode.EDIT:
		return
	var decoded := ChessPositionCodec.from_json(DisplayServer.clipboard_get())
	if decoded.position != null:
		restoring_history = true
		model.load_position(decoded.position)
		restoring_history = false
		baseline = model.capture_position()
		history.establish_baseline(baseline, "Imported position")
	_refresh_control_states()

func _set_speed(speed: int) -> void:
	var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
	adapter.set_presentation_speed(speed)
	_refresh_control_states()

func _on_grip_toggled(enabled: bool) -> void:
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.show_piece_grip_anchors = enabled
	_refresh_control_states()

func _on_cooldowns_toggled(disabled: bool) -> void:
	model.set_active_ability_cooldowns_disabled(disabled)
	_clear_ai_thoughts()
	_refresh_control_states()

func _selected_grip_profile() -> PieceArtProfile:
	if grip_profile_option == null or grip_profile_option.selected < 0 or grip_profile_option.selected >= grip_profile_ids.size():
		return null
	return PieceView.PIECE_ART_PROFILES.get(grip_profile_ids[grip_profile_option.selected]) as PieceArtProfile

func _load_grip_profile_controls(index: int) -> void:
	if index < 0 or index >= grip_profile_ids.size():
		return
	grip_profile_option.select(index)
	var profile := _selected_grip_profile()
	if profile == null:
		return
	syncing_grip_controls = true
	grip_x_spin.set_value_no_signal(profile.grip_anchor.x)
	grip_y_spin.set_value_no_signal(profile.grip_anchor.y)
	syncing_grip_controls = false
	grip_status_label.text = profile.resource_path

func _apply_live_piece_grip() -> void:
	if syncing_grip_controls:
		return
	var profile := _selected_grip_profile()
	if profile == null:
		return
	profile.grip_anchor = Vector2(grip_x_spin.value, grip_y_spin.value)
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.show_piece_grip_anchors = true
	for piece in board.get_node("Pieces").get_children():
		if piece is PieceView and piece.art_profile == profile:
			piece.refresh_grip_anchor_from_profile()
	grip_check.set_pressed_no_signal(true)
	grip_status_label.text = "Unsaved: %s" % profile.resource_path

func _save_piece_grip() -> void:
	var profile := _selected_grip_profile()
	if profile == null or profile.resource_path.is_empty():
		grip_status_label.text = "Save failed: profile has no resource path"
		return
	var error := ResourceSaver.save(profile, profile.resource_path)
	grip_status_label.text = "Saved: %s" % profile.resource_path if error == OK else "Save failed (%s): %s" % [error, profile.resource_path]

func _clear_ai_thoughts() -> void:
	game.white_cpu_player.clear_thought()
	game.black_cpu_player.clear_thought()

func _refresh_control_states() -> void:
	if mode_button == null:
		return
	var settled := model.is_settled()
	var editing := mode == Mode.EDIT and settled
	if mobile_layout:
		mode_button.text = "Edit" if mode == Mode.EDIT else "Play"
	else:
		mode_button.text = "Mode: Edit [P]" if mode == Mode.EDIT else "Mode: Play [P]"
	mode_button.disabled = not settled
	_style_button(mode_button, true, COLOR_EDIT if mode == Mode.EDIT else COLOR_PLAY)
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	if view_side_button != null:
		view_side_button.text = "View: White" if board.viewing_color == "white" else "View: Black"
		view_side_button.disabled = not settled
		_style_button(view_side_button, true, COLOR_WHITE_SIDE if board.viewing_color == "white" else COLOR_BLACK_SIDE, board.viewing_color == "white")
	undo_button.disabled = not settled or not history.can_undo()
	redo_button.disabled = not settled or not history.can_redo()
	reset_button.disabled = not settled or not history.can_undo()
	clear_button.disabled = not editing
	if copy_button != null:
		copy_button.disabled = not settled
	if paste_button != null:
		paste_button.disabled = not editing
	if preset_option != null:
		preset_option.disabled = not settled
	if turn_option != null:
		turn_option.disabled = not editing
	for value in ai_mode_buttons:
		ai_mode_buttons[value].disabled = not settled
		var active: bool = value == ai_mode
		var color := Color("67626f")
		if value == ChessCpuPlayer.ExecutionMode.AUTO:
			color = COLOR_AUTO
		elif value == ChessCpuPlayer.ExecutionMode.MANUAL:
			color = COLOR_MANUAL
		ai_mode_buttons[value].set_pressed_no_signal(active)
		_style_button(ai_mode_buttons[value], active, color)
	for color_name in ai_side_buttons:
		ai_side_buttons[color_name].disabled = not settled
		var active: bool = ai_sides[color_name]
		ai_side_buttons[color_name].set_pressed_no_signal(active)
		_style_button(ai_side_buttons[color_name], active, COLOR_WHITE_SIDE if color_name == "white" else COLOR_BLACK_SIDE, color_name == "white")
	if speed_slider != null:
		var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
		var speed: int = adapter.presentation_policy.speed
		speed_slider.set_value_no_signal(speed)
		var speed_names := ["Ultra Slow", "Slow", "Normal", "Fast", "Instant"]
		var speed_colors := [COLOR_ULTRA_SLOW, COLOR_SLOW, COLOR_EDIT, COLOR_MANUAL, COLOR_INSTANT]
		speed_value_label.text = speed_names[speed]
		speed_value_label.add_theme_color_override("font_color", speed_colors[speed])
	cooldowns_check.set_pressed_no_signal(model.active_ability_cooldowns_disabled)
	cooldowns_check.add_theme_color_override("font_color", COLOR_CYAN if model.active_ability_cooldowns_disabled else Color.WHITE)
	if grip_check != null:
		grip_check.set_pressed_no_signal(board.show_piece_grip_anchors)
		grip_check.add_theme_color_override("font_color", COLOR_CYAN if board.show_piece_grip_anchors else Color.WHITE)
	if turn_option != null:
		turn_option.select(0 if model.current_turn == "white" else 1)
	piece_palette.set_palette_enabled(editing)
	piece_palette.sync_selection(editor.selected_tool, editor.selected_type_id, editor.selected_color)
	if grip_profile_option != null:
		grip_profile_option.disabled = not settled
		grip_x_spin.editable = settled
		grip_y_spin.editable = settled
		grip_save_button.disabled = not settled
	var manual_ai_available := mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and _manual_cpu() != null and settled and not model.battle_over
	if think_button != null:
		think_button.disabled = not manual_ai_available
		step_button.disabled = not manual_ai_available
		_refresh_thought_state()
	_sync_disabled_focus_states()

func _refresh_thought_state() -> void:
	if execute_button == null or thought_label == null:
		return
	var cpu := _manual_cpu()
	var thought = cpu.get_last_thought() if cpu != null else null
	var valid: bool = thought != null and thought.model_revision == model.position_revision and thought.color == model.current_turn
	execute_button.disabled = not valid or mode != Mode.PLAY or ai_mode != ChessCpuPlayer.ExecutionMode.MANUAL
	if not valid:
		thought_label.text = "No prepared action"
		thought_label.add_theme_color_override("font_color", Color("9a96a3"))
		return
	var kind := "Move" if thought.action_kind == ChessPrimaryAction.Kind.MOVE else "Ability"
	thought_label.text = "%s: %s %s → %s" % [kind, thought.piece_type_id, thought.piece_coordinate, thought.target]
	thought_label.add_theme_color_override("font_color", COLOR_MANUAL)

func _style_button(button: Button, active: bool, color: Color, dark_text := false) -> void:
	var background := color if active else COLOR_INACTIVE
	var normal := StyleBoxFlat.new()
	normal.bg_color = background
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = color if active else Color("494553")
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", normal)
	var hover := normal.duplicate()
	hover.bg_color = background.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var disabled_style := normal.duplicate()
	disabled_style.bg_color = Color("36353a")
	disabled_style.border_color = Color("494553")
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_color", Color("181620") if active and dark_text else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("181620") if active and dark_text else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("85818b"))

func _sync_disabled_focus_states() -> void:
	var controls: Array[Control] = [
		mode_button, view_side_button, undo_button, redo_button, reset_button, clear_button,
		copy_button, paste_button, think_button, execute_button, step_button,
		preset_option, turn_option,
	]
	for button in ai_mode_buttons.values():
		controls.append(button)
	for button in ai_side_buttons.values():
		controls.append(button)
	for control in controls:
		if control == null:
			continue
		var disabled: bool = control.get("disabled")
		if disabled:
			control.release_focus()
			control.focus_mode = Control.FOCUS_NONE
		else:
			control.focus_mode = Control.FOCUS_ALL
