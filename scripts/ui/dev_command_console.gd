extends CanvasLayer
class_name DevCommandConsole

const ENABLED_SETTING := "dev_console/enabled"
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const SANDBOX_SCENE_PATH := "res://scenes/sandbox/board_sandbox.tscn"

@onready var panel: PanelContainer = $Panel
@onready var command_input: LineEdit = $Panel/Layout/CommandInput
@onready var feedback_label: Label = $Panel/Layout/FeedbackLabel

var console_enabled := true


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


func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error == OK:
		return
	open_console()
	feedback_label.text = "Could not open scene (error %d)." % error


static func resolve_command(command: String, current_scene_path: String = "") -> Dictionary:
	var normalized := command.strip_edges().to_lower()
	var destination := ""
	match normalized:
		"/sandbox":
			destination = SANDBOX_SCENE_PATH
		"/game":
			destination = GAME_SCENE_PATH
		"":
			return {"path": "", "message": "Enter /sandbox or /game."}
		_:
			return {"path": "", "message": "Unknown command: %s" % command.strip_edges()}
	if current_scene_path == destination:
		return {"path": "", "message": "That scene is already active."}
	return {"path": destination, "message": ""}


static func _is_toggle_key(event: InputEventKey) -> bool:
	return (
		event.physical_keycode == KEY_QUOTELEFT
		or event.keycode == KEY_QUOTELEFT
		or event.unicode == 96
		or event.unicode == 126
	)
