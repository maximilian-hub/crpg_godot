extends RefCounted
class_name DialogueRevealController

signal portrait_changed(portrait_id: String, visible_character_index: int)
signal character_revealed(visible_character_index: int, character: String)
signal visibility_changed(visible_character_count: int)
signal page_completed
signal advance_requested

enum ConfirmResult { COMPLETED_PAGE, REQUESTED_ADVANCE }

var base_character_delay := 0.04
var comma_pause_multiplier := 2.0
var sentence_pause_multiplier := 4.0
var newline_pause_multiplier := 3.0
var player_speed_multiplier := 1.0
var instant_text := false
var paused := false

var page
var visible_character_count := 0
var completed := false
var elapsed := 0.0
var event_cursor := 0


func start(new_page) -> void:
	page = new_page
	visible_character_count = 0
	completed = false
	elapsed = 0.0
	event_cursor = 0
	visibility_changed.emit(0)
	if page == null:
		_complete_page()
		return
	portrait_changed.emit(page.initial_portrait_id, -1)
	if page.text.is_empty() or instant_text:
		complete_immediately()


func advance(delta: float) -> void:
	if page == null or completed or paused:
		return
	if instant_text:
		complete_immediately()
		return
	elapsed += maxf(0.0, delta)
	while not completed:
		var delay := delay_before_next_character()
		if elapsed + 0.000001 < delay:
			break
		elapsed -= delay
		reveal_one()


func reveal_one() -> bool:
	if page == null or completed:
		return false
	if visible_character_count >= page.text.length():
		_dispatch_events_at(visible_character_count)
		_complete_page()
		return false
	_dispatch_events_at(visible_character_count)
	var character: String = page.text[visible_character_count]
	character_revealed.emit(visible_character_count, character)
	visible_character_count += 1
	visibility_changed.emit(visible_character_count)
	if visible_character_count >= page.text.length():
		_dispatch_events_at(visible_character_count)
		_complete_page()
	return true


func complete_immediately() -> void:
	if page == null or completed:
		return
	while visible_character_count < page.text.length():
		_dispatch_events_at(visible_character_count)
		var character: String = page.text[visible_character_count]
		character_revealed.emit(visible_character_count, character)
		visible_character_count += 1
	_dispatch_events_at(visible_character_count)
	visibility_changed.emit(visible_character_count)
	_complete_page()


func confirm() -> ConfirmResult:
	if not completed:
		complete_immediately()
		return ConfirmResult.COMPLETED_PAGE
	advance_requested.emit()
	return ConfirmResult.REQUESTED_ADVANCE


func set_player_speed(value: float) -> void:
	player_speed_multiplier = maxf(0.01, value)


func set_instant_text(enabled: bool) -> void:
	instant_text = enabled
	if enabled and page != null and not completed:
		complete_immediately()


func delay_before_next_character() -> float:
	if page == null or visible_character_count >= page.text.length():
		return 0.0
	var authored_speed := 1.0
	if visible_character_count < page.character_speed_multipliers.size():
		authored_speed = maxf(0.01, page.character_speed_multipliers[visible_character_count])
	var punctuation_multiplier := 1.0
	if visible_character_count > 0:
		punctuation_multiplier = _pause_after(page.text[visible_character_count - 1])
	return base_character_delay * punctuation_multiplier / authored_speed / player_speed_multiplier


func _pause_after(character: String) -> float:
	if character == "\n":
		return newline_pause_multiplier
	if character in [".", "?", "!"]:
		return sentence_pause_multiplier
	if character in [",", ";", ":"]:
		return comma_pause_multiplier
	return 1.0


func _dispatch_events_at(index: int) -> void:
	while event_cursor < page.events.size():
		var event = page.events[event_cursor]
		if event.visible_character_index > index:
			break
		if event.kind == DialogueEvent.Kind.PORTRAIT:
			portrait_changed.emit(event.value, event.visible_character_index)
		event_cursor += 1


func _complete_page() -> void:
	if completed:
		return
	completed = true
	elapsed = 0.0
	page_completed.emit()
