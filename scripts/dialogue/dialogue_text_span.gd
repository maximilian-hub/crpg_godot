extends RefCounted
class_name DialogueTextSpan

enum Kind { COLOR, CAPITALIZATION, FONT_SIZE, JIGGLE }

var kind: Kind
var start_index := 0
var end_index := 0
var value := ""


func _init(new_kind: Kind = Kind.COLOR, new_start_index: int = 0, new_end_index: int = 0, new_value: String = "") -> void:
	kind = new_kind
	start_index = new_start_index
	end_index = new_end_index
	value = new_value


static func effective_value_at(spans: Array, requested_kind: Kind, visible_character_index: int, fallback: String = "") -> String:
	var best_value := fallback
	var best_start := -1
	var best_end := 0x7fffffff
	for span in spans:
		if span.kind != requested_kind or visible_character_index < span.start_index or visible_character_index >= span.end_index:
			continue
		if span.start_index > best_start or (span.start_index == best_start and span.end_index <= best_end):
			best_value = span.value
			best_start = span.start_index
			best_end = span.end_index
	return best_value
