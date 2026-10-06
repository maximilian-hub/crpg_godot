extends Node
class_name LaunchRouter

const GAME_SCENE_PATH := "res://scenes/main.tscn"
const SANDBOX_SCENE_PATH := "res://scenes/sandbox/board_sandbox.tscn"


func _ready() -> void:
	var destination := destination_path(OS.has_feature("sandbox_build"))
	var scene := load(destination) as PackedScene
	if scene == null:
		push_error("Unable to load launch destination: %s" % destination)
		return
	add_child(scene.instantiate())


static func destination_path(sandbox_build: bool) -> String:
	return SANDBOX_SCENE_PATH if sandbox_build else GAME_SCENE_PATH
