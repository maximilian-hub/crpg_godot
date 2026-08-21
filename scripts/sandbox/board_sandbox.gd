extends Node
class_name BoardSandbox

const PresentationPolicy = preload("res://scripts/view/chess_presentation_policy.gd")
const BoardPiecePaletteScript = preload("res://scripts/editor/board_piece_palette.gd")

enum Mode { EDIT, PLAY }

const COLOR_INACTIVE := Color("252331")
const COLOR_EDIT := Color("2878c7")
const COLOR_PLAY := Color("d36a25")
const COLOR_AUTO := Color("2d9b59")
const COLOR_MANUAL := Color("c58a24")
const COLOR_GOLD := Color("d1a43a")
const COLOR_CYAN := Color("28b8c7")
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
var grip_check: CheckButton
var seed_spin: SpinBox
var preset_option: OptionButton
var turn_option: OptionButton
var piece_palette
var thought_label: Label
var execute_button: Button

func _ready() -> void:
	editor.model = model
	interaction.configure(model, editor, $ChessGame/CanvasLayer/ChessBoard)
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
	mode_button = _add_button("", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	var history_row := HBoxContainer.new()
	panel.add_child(history_row)
	undo_button = _add_button_to(history_row, "Undo", undo)
	redo_button = _add_button_to(history_row, "Redo", redo)
	reset_button = _add_button("Reset", reset)
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
	speed_slider.min_value = PresentationPolicy.Speed.NORMAL
	speed_slider.max_value = PresentationPolicy.Speed.INSTANT
	speed_slider.step = 1.0
	speed_slider.value = PresentationPolicy.Speed.NORMAL
	speed_slider.custom_minimum_size.x = 104.0
	speed_slider.value_changed.connect(func(value: float): _set_speed(int(value)))
	speed_row.add_child(speed_slider)
	speed_value_label = Label.new()
	speed_value_label.custom_minimum_size.x = 58.0
	speed_row.add_child(speed_value_label)

	grip_check = CheckButton.new()
	grip_check.text = "Grip Anchors"
	grip_check.toggled.connect(_on_grip_toggled)
	panel.add_child(grip_check)

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

func _on_palette_piece_drag_requested(type_id: StringName, color: String) -> void:
	if editor.select_palette_piece(type_id, color):
		interaction.begin_palette_drag(type_id, color)

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
	return button

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

func _clear_ai_thoughts() -> void:
	game.white_cpu_player.clear_thought()
	game.black_cpu_player.clear_thought()

func _refresh_control_states() -> void:
	if mode_button == null:
		return
	var settled := model.is_settled()
	var editing := mode == Mode.EDIT and settled
	mode_button.text = "Mode: Edit" if mode == Mode.EDIT else "Mode: Play"
	mode_button.disabled = not settled
	_style_button(mode_button, true, COLOR_EDIT if mode == Mode.EDIT else COLOR_PLAY)
	undo_button.disabled = not settled or not history.can_undo()
	redo_button.disabled = not settled or not history.can_redo()
	reset_button.disabled = not settled or not history.can_undo()
	clear_button.disabled = not editing
	copy_button.disabled = not settled
	paste_button.disabled = not editing
	preset_option.disabled = not settled
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
	var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
	var speed: int = adapter.presentation_policy.speed
	speed_slider.set_value_no_signal(speed)
	var speed_names := ["Normal", "Fast", "Instant"]
	var speed_colors := [COLOR_EDIT, COLOR_MANUAL, COLOR_INSTANT]
	speed_value_label.text = speed_names[speed]
	speed_value_label.add_theme_color_override("font_color", speed_colors[speed])
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	grip_check.set_pressed_no_signal(board.show_piece_grip_anchors)
	grip_check.add_theme_color_override("font_color", COLOR_CYAN if board.show_piece_grip_anchors else Color.WHITE)
	turn_option.select(0 if model.current_turn == "white" else 1)
	piece_palette.set_palette_enabled(editing)
	piece_palette.sync_selection(editor.selected_tool, editor.selected_type_id, editor.selected_color)
	var manual_ai_available := mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and _manual_cpu() != null and settled and not model.battle_over
	think_button.disabled = not manual_ai_available
	step_button.disabled = not manual_ai_available
	_refresh_thought_state()
	_sync_disabled_focus_states()

func _refresh_thought_state() -> void:
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
		mode_button, undo_button, redo_button, reset_button, clear_button,
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
