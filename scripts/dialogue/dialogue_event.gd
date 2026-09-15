extends RefCounted
class_name DialogueEvent

enum Kind { PORTRAIT }

var kind := Kind.PORTRAIT
var visible_character_index := 0
var value := ""


func _init(event_kind: Kind = Kind.PORTRAIT, character_index: int = 0, event_value: String = "") -> void:
	kind = event_kind
	visible_character_index = character_index
	value = event_value
