extends RefCounted
class_name DialogueParser

const ConversationScript := preload("res://scripts/dialogue/dialogue_conversation.gd")
const PageScript := preload("res://scripts/dialogue/dialogue_page.gd")
const ChoiceScript := preload("res://scripts/dialogue/dialogue_choice.gd")
const EventScript := preload("res://scripts/dialogue/dialogue_event.gd")
const ResultScript := preload("res://scripts/dialogue/dialogue_parse_result.gd")


static func parse_file(path: String) -> DialogueParseResult:
	if not FileAccess.file_exists(path):
		var missing := ResultScript.new() as DialogueParseResult
		missing.errors.append("%s: file does not exist" % path)
		return missing
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var unreadable := ResultScript.new() as DialogueParseResult
		unreadable.errors.append("%s: unable to open file (error %s)" % [path, FileAccess.get_open_error()])
		return unreadable
	return parse_text(file.get_as_text(), path)


static func parse_text(source: String, source_name: String = "<memory>") -> DialogueParseResult:
	var result := ResultScript.new() as DialogueParseResult
	var conversation := ConversationScript.new() as DialogueConversation
	result.conversation = conversation
	var current_page: DialoguePage
	var body_lines: PackedStringArray = PackedStringArray()
	var page_start_line := 0
	var lines := source.replace("\r\n", "\n").replace("\r", "\n").split("\n", true)
	for index in range(lines.size()):
		var line_number := index + 1
		var line: String = lines[index]
		var stripped := line.strip_edges()
		if stripped.begins_with("//"):
			continue
		if stripped.begins_with("@"):
			if stripped.begins_with("@conversation"):
				if current_page != null:
					_finalize_page(current_page, body_lines, result, source_name, page_start_line)
					body_lines.clear()
					current_page = null
				var conversation_id := stripped.trim_prefix("@conversation").strip_edges()
				if conversation_id.is_empty():
					_add_error(result, source_name, line_number, "@conversation requires an ID")
				elif not _is_valid_id(conversation_id):
					_add_error(result, source_name, line_number, "conversation ID must use only letters, numbers, underscores, dots, or hyphens")
				elif not conversation.id.is_empty():
					_add_error(result, source_name, line_number, "only one @conversation is allowed per file")
				else:
					conversation.id = conversation_id
			elif stripped.begins_with("@page"):
				if current_page != null:
					_finalize_page(current_page, body_lines, result, source_name, page_start_line)
					body_lines.clear()
				current_page = PageScript.new() as DialoguePage
				page_start_line = line_number
				conversation.pages.append(current_page)
				var attributes := _parse_attributes(stripped.trim_prefix("@page").strip_edges(), result, source_name, line_number)
				_reject_unknown_attributes(attributes, PackedStringArray(["speaker", "name", "known", "portrait"]), result, source_name, line_number, "@page")
				current_page.speaker_id = attributes.get("speaker", "")
				current_page.speaker_name = attributes.get("name", "")
				current_page.initial_portrait_id = _normalize_optional_id(attributes.get("portrait", ""))
				var known_value: String = attributes.get("known", "true").to_lower()
				if known_value != "true" and known_value != "false":
					_add_error(result, source_name, line_number, "page 'known' must be true or false")
				current_page.speaker_known = known_value == "true"
				if current_page.speaker_id.is_empty():
					_add_error(result, source_name, line_number, "@page requires speaker=<ID>")
				elif not _is_valid_id(current_page.speaker_id):
					_add_error(result, source_name, line_number, "speaker ID must use only letters, numbers, underscores, dots, or hyphens")
				if current_page.speaker_name.is_empty():
					_add_error(result, source_name, line_number, "@page requires name=<display name>")
				if not current_page.initial_portrait_id.is_empty() and not _is_valid_id(current_page.initial_portrait_id):
					_add_error(result, source_name, line_number, "portrait ID must use only letters, numbers, underscores, dots, or hyphens")
			elif stripped.begins_with("@choice"):
				if current_page == null:
					_add_error(result, source_name, line_number, "@choice must appear inside a page")
					continue
				var attributes := _parse_attributes(stripped.trim_prefix("@choice").strip_edges(), result, source_name, line_number)
				_reject_unknown_attributes(attributes, PackedStringArray(["text", "target"]), result, source_name, line_number, "@choice")
				var choice_text: String = attributes.get("text", "")
				var target: String = attributes.get("target", "")
				if choice_text.is_empty() or target.is_empty():
					_add_error(result, source_name, line_number, "@choice requires text=<label> and target=<ID>")
				elif not _is_valid_id(target):
					_add_error(result, source_name, line_number, "choice target must use only letters, numbers, underscores, dots, or hyphens")
				else:
					current_page.choices.append(ChoiceScript.new(choice_text, target))
			else:
				_add_error(result, source_name, line_number, "unknown directive '%s'" % stripped.get_slice(" ", 0))
		elif current_page != null:
			body_lines.append(line)
		elif not stripped.is_empty():
			_add_error(result, source_name, line_number, "text must appear inside a page")
	if current_page != null:
		_finalize_page(current_page, body_lines, result, source_name, page_start_line)
	if conversation.id.is_empty():
		_add_error(result, source_name, 1, "file requires @conversation <ID>")
	if conversation.pages.is_empty():
		_add_error(result, source_name, 1, "conversation requires at least one @page")
	return result


static func _parse_attributes(source: String, result: DialogueParseResult, source_name: String, line_number: int) -> Dictionary:
	var attributes := {}
	var regex := RegEx.new()
	regex.compile("([A-Za-z_][A-Za-z0-9_]*)=(?:\"([^\"]*)\"|([^\\s]+))")
	var consumed := PackedStringArray()
	for match_result in regex.search_all(source):
		var key := match_result.get_string(1)
		var value := match_result.get_string(2) if not match_result.get_string(2).is_empty() else match_result.get_string(3)
		if attributes.has(key):
			_add_error(result, source_name, line_number, "duplicate attribute '%s'" % key)
		attributes[key] = value
		consumed.append(match_result.get_string(0))
	var remainder := source
	for token in consumed:
		remainder = remainder.replace(token, "")
	if not remainder.strip_edges().is_empty():
		_add_error(result, source_name, line_number, "malformed attributes near '%s'" % remainder.strip_edges())
	return attributes


static func _finalize_page(page: DialoguePage, body_lines: PackedStringArray, result: DialogueParseResult, source_name: String, page_line: int) -> void:
	while not body_lines.is_empty() and body_lines[0].strip_edges().is_empty():
		body_lines.remove_at(0)
	while not body_lines.is_empty() and body_lines[-1].strip_edges().is_empty():
		body_lines.remove_at(body_lines.size() - 1)
	var raw_text := "\n".join(body_lines)
	var parsed := _parse_inline_events(raw_text, result, source_name, page_line)
	page.text = parsed.text
	page.events = parsed.events
	if page.text.is_empty():
		_add_error(result, source_name, page_line, "page requires visible text")


static func _parse_inline_events(raw_text: String, result: DialogueParseResult, source_name: String, page_line: int) -> Dictionary:
	var visible_text := ""
	var events: Array[DialogueEvent] = []
	var cursor := 0
	while cursor < raw_text.length():
		if raw_text[cursor] != "[":
			visible_text += raw_text[cursor]
			cursor += 1
			continue
		var closing := raw_text.find("]", cursor + 1)
		if closing < 0:
			_add_error(result, source_name, page_line, "unclosed inline tag")
			visible_text += raw_text.substr(cursor)
			break
		var tag := raw_text.substr(cursor + 1, closing - cursor - 1)
		if tag.begins_with("portrait="):
			var portrait_id := _normalize_optional_id(tag.trim_prefix("portrait=").strip_edges())
			if portrait_id.is_empty():
				_add_error(result, source_name, page_line, "portrait tag requires a non-'none' portrait ID")
			elif not _is_valid_id(portrait_id):
				_add_error(result, source_name, page_line, "portrait event ID must use only letters, numbers, underscores, dots, or hyphens")
			else:
				events.append(EventScript.new(EventScript.Kind.PORTRAIT, visible_text.length(), portrait_id))
		else:
			_add_error(result, source_name, page_line, "unknown inline tag '[%s]'" % tag)
		cursor = closing + 1
	return {"text": visible_text, "events": events}


static func _normalize_optional_id(value: String) -> String:
	return "" if value.to_lower() == "none" else value


static func _reject_unknown_attributes(attributes: Dictionary, allowed: PackedStringArray, result: DialogueParseResult, source_name: String, line_number: int, directive: String) -> void:
	for key in attributes:
		if not allowed.has(key):
			_add_error(result, source_name, line_number, "%s has unknown attribute '%s'" % [directive, key])


static func _is_valid_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_.-]+$")
	return regex.search(value) != null


static func _add_error(result: DialogueParseResult, source_name: String, line_number: int, message: String) -> void:
	result.errors.append("%s:%d: %s" % [source_name, line_number, message])
