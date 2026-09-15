extends RefCounted
class_name DialogueParseResult

var conversation: DialogueConversation
var errors: PackedStringArray = PackedStringArray()


func is_valid() -> bool:
	return conversation != null and errors.is_empty()
