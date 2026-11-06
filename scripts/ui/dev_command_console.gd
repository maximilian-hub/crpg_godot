extends CanvasLayer
class_name DevCommandConsole

const ENABLED_SETTING := "dev_console/enabled"
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const SANDBOX_SCENE_PATH := "res://scenes/sandbox/board_sandbox.tscn"
const TEST_TAVERN_SCENE_PATH := "res://scenes/overworld/test_tavern.tscn"
const COMMANDS := [
	{"command": "/game", "description": "Open the main game", "path": GAME_SCENE_PATH},
	{"command": "/sandbox", "description": "Open the board sandbox", "path": SANDBOX_SCENE_PATH},
	{"command": "/test_tavern", "description": "Open the tavern overworld test", "path": TEST_TAVERN_SCENE_PATH},
]

@onready var panel: PanelContainer = $Panel
@onready var command_input: LineEdit = $Panel/Layout/CommandInput
@onready var results_panel: PanelContainer = $Panel/Layout/ResultsPanel
@onready var results_list: VBoxContainer = $Panel/Layout/ResultsPanel/Results
@onready var feedback_label: Label = $Panel/Layout/FeedbackLabel

var console_enabled := true
var filtered_commands: Array[Dictionary] = []
var selected_result_index := 0


func _ready() -> void:
	# The keyboard-oriented developer console is intentionally unavailable in
	# Android builds even when it remains enabled for desktop development.
	console_enabled = (
		bool(ProjectSettings.get_setting(ENABLED_SETTING, true))
		and not OS.has_feature("android")
	)
	panel.visible = false
	set_process_input(console_enabled)
	command_input.text_submitted.connect(_on_command_submitted)
	command_input.text_changed.connect(_on_command_text_changed)
	command_input.gui_input.connect(_on_command_input_gui_input)


func _input(event: InputEvent) -> void:
	if not console_enabled or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _is_toggle_key(key_event):
		get_viewport().set_input_as_handled()
		if panel.visible:
			close_console()
		else:
			open_console()
		return
	if panel.visible and key_event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_console()


func open_console() -> void:
	if not console_enabled:
		return
	panel.visible = true
	command_input.clear()
	feedback_label.text = ""
	_refresh_results("")
	command_input.grab_focus()


func close_console() -> void:
	command_input.release_focus()
	get_viewport().gui_release_focus()
	panel.visible = false


func _on_command_submitted(command: String) -> void:
	var result := resolve_command(command, get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "")
	if not result.path.is_empty():
		close_console()
		call_deferred("_change_scene", result.path)
		return
	feedback_label.text = result.message
	command_input.select_all()
	_refresh_results(command)

func _on_command_text_changed(new_text: String) -> void:
	feedback_label.text = ""
	selected_result_index = 0
	_refresh_results(new_text)

func _on_command_input_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_UP:
			_move_result_selection(-1)
			command_input.accept_event()
		KEY_DOWN:
			_move_result_selection(1)
			command_input.accept_event()
		KEY_TAB:
			_complete_selected_result()
			command_input.accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if not filtered_commands.is_empty():
				var selected := filtered_commands[selected_result_index]
				command_input.accept_event()
				_on_command_submitted(selected.command)

func _move_result_selection(direction: int) -> void:
	if filtered_commands.is_empty():
		return
	selected_result_index = wrapi(selected_result_index + direction, 0, filtered_commands.size())
	_rebuild_result_labels()

func _complete_selected_result() -> void:
	if filtered_commands.is_empty():
		return
	command_input.text = filtered_commands[selected_result_index].command
	command_input.caret_column = command_input.text.length()
	selected_result_index = 0
	_refresh_results(command_input.text)

func _refresh_results(query: String) -> void:
	filtered_commands = search_commands(query)
	if filtered_commands.is_empty():
		selected_result_index = 0
	else:
		selected_result_index = clampi(selected_result_index, 0, filtered_commands.size() - 1)
	_rebuild_result_labels()

func _rebuild_result_labels() -> void:
	for child in results_list.get_children():
		child.free()
	results_panel.visible = not filtered_commands.is_empty()
	for index in range(filtered_commands.size()):
		var entry := filtered_commands[index]
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "%s%s  %s" % ["> " if index == selected_result_index else "  ", entry.command, entry.description]
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.42) if index == selected_result_index else Color(0.72, 0.76, 0.8))
		results_list.add_child(label)


func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error == OK:
		return
	open_console()
	feedback_label.text = "Could not open scene (error %d)." % error


static func resolve_command(command: String, current_scene_path: String = "") -> Dictionary:
	var normalized := command.strip_edges().to_lower()
	if normalized.is_empty():
		return {"path": "", "message": "Enter a command."}
	var destination := ""
	for entry in COMMANDS:
		if entry.command == normalized:
			destination = entry.path
			break
	if destination.is_empty():
		return {"path": "", "message": "Unknown command: %s" % command.strip_edges()}
	if current_scene_path == destination:
		return {"path": "", "message": "That scene is already active."}
	return {"path": destination, "message": ""}

static func search_commands(query: String) -> Array[Dictionary]:
	var normalized := query.strip_edges().to_lower()
	var prefix_matches: Array[Dictionary] = []
	var other_matches: Array[Dictionary] = []
	for entry in COMMANDS:
		var command: String = entry.command
		var description: String = entry.description
		if normalized.is_empty() or command.begins_with(normalized):
			prefix_matches.append(entry)
		elif normalized in command or normalized in description.to_lower():
			other_matches.append(entry)
	prefix_matches.append_array(other_matches)
	return prefix_matches


static func _is_toggle_key(event: InputEventKey) -> bool:
	return (
		event.physical_keycode == KEY_QUOTELEFT
		or event.keycode == KEY_QUOTELEFT
		or event.unicode == 96
		or event.unicode == 126
	)
