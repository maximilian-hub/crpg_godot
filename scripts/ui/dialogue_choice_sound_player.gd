extends Node
class_name DialogueChoiceSoundPlayer

const ChoiceControllerScript := preload("res://scripts/dialogue/dialogue_choice_controller.gd")

var skin: Resource
var enabled := true
var played_count := 0


func set_skin(value: Resource) -> void:
	skin = value


func play_cue(cue: StringName) -> void:
	if not enabled or skin == null:
		return
	var stream := stream_for_cue(cue)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	played_count += 1
	player.finished.connect(player.queue_free)
	player.play()


func stream_for_cue(cue: StringName) -> AudioStream:
	if skin == null:
		return null
	match cue:
		ChoiceControllerScript.CUE_NAVIGATE:
			return skin.choice_navigation_sound
		ChoiceControllerScript.CUE_CONFIRM:
			return skin.choice_confirm_sound
		ChoiceControllerScript.CUE_CANCEL:
			return skin.choice_cancel_sound
	return null


func stop_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.free()
