extends Node

const CONSOLE_SCENE := preload("res://scenes/ui/dev_command_console.tscn")
const Console := preload("res://scripts/ui/dev_command_console.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var original_setting := bool(ProjectSettings.get_setting(Console.ENABLED_SETTING, true))
	ProjectSettings.set_setting(Console.ENABLED_SETTING, true)
	var console := CONSOLE_SCENE.instantiate()
	add_child(console)

	_check(not console.panel.visible and console.layer > 1000, "console starts hidden above gameplay, dialogue, sandbox UI, and fades")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_QUOTELEFT
	toggle.pressed = true
	console._input(toggle)
	_check(console.panel.visible and get_viewport().gui_get_focus_owner() == console.command_input, "grave opens the console and focuses its command line")
	console._input(toggle)
	_check(not console.panel.visible and get_viewport().gui_get_focus_owner() == null, "grave closes the console and releases focus")

	var shifted_toggle := InputEventKey.new()
	shifted_toggle.keycode = KEY_QUOTELEFT
	shifted_toggle.unicode = 126
	shifted_toggle.shift_pressed = true
	shifted_toggle.pressed = true
	console._input(shifted_toggle)
	_check(console.panel.visible, "shifted tilde opens the same console")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	console._input(escape)
	_check(not console.panel.visible, "Escape closes the console")

	var sandbox_result := Console.resolve_command("  /SANDBox  ", Console.GAME_SCENE_PATH)
	var game_result := Console.resolve_command("/game", Console.SANDBOX_SCENE_PATH)
	_check(sandbox_result.path == Console.SANDBOX_SCENE_PATH and game_result.path == Console.GAME_SCENE_PATH, "commands normalize whitespace and case and resolve both scene destinations")
	_check(Console.resolve_command("/game", Console.GAME_SCENE_PATH).path.is_empty(), "same-scene commands do not restart the active root")
	_check(Console.resolve_command("/wat", "").message.begins_with("Unknown command"), "unknown commands return concise feedback")

	console.open_console()
	console._on_command_submitted("/wat")
	_check(console.panel.visible and console.feedback_label.text.begins_with("Unknown command") and console.command_input.has_focus(), "invalid submissions remain open and focused")
	console.queue_free()
	await get_tree().process_frame

	ProjectSettings.set_setting(Console.ENABLED_SETTING, false)
	var disabled_console := CONSOLE_SCENE.instantiate()
	add_child(disabled_console)
	disabled_console._input(toggle)
	_check(not disabled_console.console_enabled and not disabled_console.panel.visible, "project setting disables the shortcut and overlay in every build type")
	ProjectSettings.set_setting(Console.ENABLED_SETTING, original_setting)

	var main_scene := load(Console.GAME_SCENE_PATH) as PackedScene
	var sandbox_scene := load(Console.SANDBOX_SCENE_PATH) as PackedScene
	var main := main_scene.instantiate()
	var sandbox := sandbox_scene.instantiate()
	_check(main.has_node("DevCommandConsole") and sandbox.has_node("DevCommandConsole"), "Main and BoardSandbox both compose the shared console")
	main.free()
	sandbox.free()
	disabled_console.queue_free()

	if failures.is_empty():
		print("DEV COMMAND CONSOLE CHARACTERIZATION: PASS (%d checks)" % checks)
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
