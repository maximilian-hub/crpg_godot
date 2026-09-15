extends RefCounted
class_name DialogueChoice

var text := ""
var target := ""


func _init(choice_text: String = "", choice_target: String = "") -> void:
	text = choice_text
	target = choice_target
