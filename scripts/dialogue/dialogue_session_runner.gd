extends Node
class_name DialogueSessionRunner

const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")
const ChoiceControllerScript := preload("res://scripts/dialogue/dialogue_choice_controller.gd")
const SettingsScript := preload("res://scripts/dialogue/dialogue_session_settings.gd")

signal session_started(conversation_id: String)
signal page_started(page, page_index: int, page_count: int)
signal portrait_changed(portrait_id: String, visible_character_index: int)
signal character_revealed(visible_character_index: int, character: String)
signal visibility_changed(visible_character_count: int)
signal page_completed(page, page_index: int)
signal choice_selection_changed(selected_index: int)
signal choice_confirmed(selected_index: int, text: String, target: String)
signal target_emitted(target: String)
signal choice_cancel_requested
signal choice_sound_requested(cue: StringName)
signal setting_changed(setting: StringName, value: Variant)
signal conversation_finished(conversation_id: String)

enum ConfirmResult { IGNORED, COMPLETED_PAGE, CONFIRMED_CHOICE, ADVANCED_PAGE, FINISHED_CONVERSATION }

var reveal_controller
var choice_controller
var settings
var conversation
var current_page_index := -1
var active := false
var choice_committed := false


func _init() -> void:
	reveal_controller = RevealScript.new()
	choice_controller = ChoiceControllerScript.new()
	settings = SettingsScript.new()
	reveal_controller.portrait_changed.connect(func(id: String, index: int): portrait_changed.emit(id, index))
	reveal_controller.character_revealed.connect(func(index: int, character: String): character_revealed.emit(index, character))
	reveal_controller.visibility_changed.connect(func(count: int): visibility_changed.emit(count))
	reveal_controller.page_completed.connect(_on_page_completed)
	choice_controller.selection_changed.connect(func(index: int): choice_selection_changed.emit(index))
	choice_controller.choice_confirmed.connect(_on_choice_confirmed)
	choice_controller.cancel_requested.connect(func(): choice_cancel_requested.emit())
	choice_controller.sound_requested.connect(_on_choice_sound_requested)
	settings.changed.connect(_on_setting_changed)


func start(new_conversation, start_page_index: int = 0) -> bool:
	conversation = new_conversation
	current_page_index = -1
	active = conversation != null and not conversation.pages.is_empty()
	if not active:
		return false
	var clamped_index := clampi(start_page_index, 0, conversation.pages.size() - 1)
	session_started.emit(conversation.id)
	_start_page(clamped_index)
	return true


func advance(delta: float) -> void:
	if active:
		reveal_controller.advance(delta)


func confirm() -> ConfirmResult:
	if not active:
		return ConfirmResult.IGNORED
	if not reveal_controller.completed:
		reveal_controller.confirm()
		return ConfirmResult.COMPLETED_PAGE
	if choice_controller.is_active():
		return ConfirmResult.CONFIRMED_CHOICE if choice_controller.confirm() else ConfirmResult.IGNORED
	if choice_committed:
		return ConfirmResult.IGNORED
	if current_page_index + 1 < conversation.pages.size():
		_start_page(current_page_index + 1)
		return ConfirmResult.ADVANCED_PAGE
	finish()
	return ConfirmResult.FINISHED_CONVERSATION


func advance_page() -> bool:
	if not active or current_page_index + 1 >= conversation.pages.size():
		return false
	_start_page(current_page_index + 1)
	return true


func restart_page() -> bool:
	if not active or current_page_index < 0:
		return false
	_start_page(current_page_index)
	return true


func finish() -> void:
	if not active:
		return
	active = false
	choice_controller.set_page_complete(false)
	conversation_finished.emit(conversation.id)


func reveal_one() -> bool:
	return reveal_controller.reveal_one() if active else false


func complete_page() -> void:
	if active:
		reveal_controller.complete_immediately()


func move_choice(direction: int) -> bool:
	return choice_controller.move(direction) if active else false


func cancel_choice() -> bool:
	return choice_controller.cancel() if active else false


func set_paused(value: bool) -> void:
	reveal_controller.paused = value


func set_player_speed(value: float) -> void:
	settings.set_player_speed(value)


func set_instant_text(value: bool) -> void:
	settings.set_instant_text(value)


func set_animated_text_enabled(value: bool) -> void:
	settings.set_animated_text_enabled(value)


func set_reduced_motion(value: bool) -> void:
	settings.set_reduced_motion(value)


func set_voice_enabled(value: bool) -> void:
	settings.set_voice_enabled(value)


func set_ui_sounds_enabled(value: bool) -> void:
	settings.set_ui_sounds_enabled(value)


func current_page():
	if conversation == null or current_page_index < 0 or current_page_index >= conversation.pages.size():
		return null
	return conversation.pages[current_page_index]


func visible_character_count() -> int:
	return reveal_controller.visible_character_count


func is_page_complete() -> bool:
	return reveal_controller.completed


func next_character_delay() -> float:
	return 0.0 if reveal_controller.completed else reveal_controller.delay_before_next_character()


func choices_are_active() -> bool:
	return choice_controller.is_active()


func selected_choice_index() -> int:
	return choice_controller.selected_index


func _start_page(index: int) -> void:
	current_page_index = index
	choice_committed = false
	var page = current_page()
	page_started.emit(page, current_page_index, conversation.pages.size())
	choice_controller.start(page.choices)
	choice_controller.set_page_complete(false)
	reveal_controller.set_player_speed(settings.player_speed_multiplier)
	reveal_controller.instant_text = settings.instant_text
	reveal_controller.paused = false
	reveal_controller.start(page)


func _on_page_completed() -> void:
	choice_controller.set_page_complete(true)
	page_completed.emit(current_page(), current_page_index)


func _on_choice_confirmed(selected_index: int, text: String, target: String) -> void:
	choice_committed = true
	choice_controller.set_page_complete(false)
	choice_confirmed.emit(selected_index, text, target)
	target_emitted.emit(target)


func _on_choice_sound_requested(cue: StringName) -> void:
	if settings.ui_sounds_enabled:
		choice_sound_requested.emit(cue)


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	match setting:
		&"player_speed_multiplier":
			reveal_controller.set_player_speed(float(value))
		&"instant_text":
			reveal_controller.set_instant_text(bool(value))
	setting_changed.emit(setting, value)
