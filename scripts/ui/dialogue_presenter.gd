extends Control
class_name DialoguePresenter

const DialogueViewScene := preload("res://scenes/ui/dialogue_view.tscn")
const ParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RunnerScript := preload("res://scripts/dialogue/dialogue_session_runner.gd")
const VoiceEmitterScript := preload("res://scripts/dialogue/dialogue_voice_emitter.gd")
const VoicePlayerScript := preload("res://scripts/ui/dialogue_voice_player.gd")
const ChoiceSoundPlayerScript := preload("res://scripts/ui/dialogue_choice_sound_player.gd")
const DEFAULT_SPEAKER_CATALOG := preload("res://assets/ui/dialogue/dialogue_speaker_catalog.tres")

signal conversation_started(conversation_id: String)
signal conversation_finished(conversation_id: String)
signal target_emitted(target: String)
signal choice_cancel_requested()
signal conversation_failed(source_path: String, errors: PackedStringArray)

@export var speaker_catalog: DialogueSpeakerCatalog = DEFAULT_SPEAKER_CATALOG

var dialogue_view: DialogueView
var session_runner: DialogueSessionRunner
var voice_emitter: DialogueVoiceEmitter
var voice_player: DialogueVoicePlayer
var choice_sound_player: DialogueChoiceSoundPlayer
var conversation: DialogueConversation
var active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_runtime()
	visible = false


func _process(delta: float) -> void:
	if active:
		session_runner.advance(delta)


func start_file(path: String, placement := DialogueView.Placement.BOTTOM, start_page_index := 0) -> bool:
	var parsed: DialogueParseResult = ParserScript.parse_file(path)
	if not parsed.is_valid():
		var errors := PackedStringArray(parsed.errors)
		for error in errors:
			printerr(error)
		conversation_failed.emit(path, errors)
		return false
	return start_conversation(parsed.conversation, placement, start_page_index)


func start_conversation(value: DialogueConversation, placement := DialogueView.Placement.BOTTOM, start_page_index := 0) -> bool:
	_build_runtime()
	if value == null or value.pages.is_empty():
		var errors := PackedStringArray(["Dialogue conversation is empty."])
		conversation_failed.emit("", errors)
		return false
	voice_player.stop_all()
	choice_sound_player.stop_all()
	conversation = value
	dialogue_view.set_placement(placement)
	visible = true
	active = true
	conversation_started.emit(conversation.id)
	if not session_runner.start(conversation, start_page_index):
		active = false
		visible = false
		return false
	return true


func confirm() -> DialogueSessionRunner.ConfirmResult:
	return session_runner.confirm() if active else DialogueSessionRunner.ConfirmResult.IGNORED


func move_choice(direction: int) -> bool:
	return session_runner.move_choice(direction) if active else false


func cancel_choice() -> bool:
	return session_runner.cancel_choice() if active else false


func stop() -> void:
	if session_runner != null:
		session_runner.active = false
	if voice_player != null:
		voice_player.stop_all()
	if choice_sound_player != null:
		choice_sound_player.stop_all()
	active = false
	conversation = null
	visible = false


func set_skin(skin: DialogueSkin) -> void:
	_build_runtime()
	dialogue_view.set_skin(skin)
	voice_emitter.set_skin(dialogue_view.skin)
	choice_sound_player.set_skin(dialogue_view.skin)


func _build_runtime() -> void:
	if dialogue_view != null:
		return
	dialogue_view = DialogueViewScene.instantiate() as DialogueView
	add_child(dialogue_view)
	session_runner = RunnerScript.new() as DialogueSessionRunner
	session_runner.name = "DialogueSessionRunner"
	add_child(session_runner)
	voice_emitter = VoiceEmitterScript.new() as DialogueVoiceEmitter
	voice_emitter.set_skin(dialogue_view.skin)
	voice_player = VoicePlayerScript.new() as DialogueVoicePlayer
	voice_player.name = "DialogueVoicePlayer"
	add_child(voice_player)
	choice_sound_player = ChoiceSoundPlayerScript.new() as DialogueChoiceSoundPlayer
	choice_sound_player.name = "DialogueChoiceSoundPlayer"
	choice_sound_player.set_skin(dialogue_view.skin)
	add_child(choice_sound_player)

	session_runner.page_started.connect(_on_page_started)
	session_runner.visibility_changed.connect(dialogue_view.set_visible_character_count)
	session_runner.portrait_changed.connect(_on_portrait_changed)
	session_runner.character_revealed.connect(voice_emitter.on_character_revealed)
	session_runner.bulk_reveal_started.connect(voice_emitter.on_bulk_reveal_started)
	session_runner.bulk_reveal_finished.connect(voice_emitter.on_bulk_reveal_finished)
	session_runner.page_completed.connect(func(_page, _index: int): dialogue_view.set_page_complete(true))
	session_runner.choice_selection_changed.connect(dialogue_view.set_selected_choice)
	session_runner.target_emitted.connect(func(target: String): target_emitted.emit(target))
	session_runner.choice_cancel_requested.connect(func(): choice_cancel_requested.emit())
	session_runner.choice_sound_requested.connect(choice_sound_player.play_cue)
	session_runner.setting_changed.connect(_on_setting_changed)
	session_runner.conversation_finished.connect(_on_conversation_finished)
	voice_emitter.voice_requested.connect(voice_player.play_request)


func _on_page_started(page: DialoguePage, _page_index: int, _page_count: int) -> void:
	var profile := speaker_catalog.profile(page.speaker_id) if speaker_catalog != null else null
	voice_emitter.set_profile(profile)
	voice_emitter.set_page(page)
	var choices := PackedStringArray()
	for choice in page.choices:
		choices.append(choice.text)
	var display_name: String = page.speaker_name
	if display_name.is_empty() and profile != null:
		display_name = profile.default_display_name
	dialogue_view.configure(
		display_name,
		page.speaker_known,
		page.text,
		_resolve_portrait(page.speaker_id, page.initial_portrait_id),
		choices,
		page.presentation_spans
	)
	dialogue_view.set_page_complete(false)
	dialogue_view.set_visible_character_count(0)


func _on_portrait_changed(portrait_id: String, _visible_character_index: int) -> void:
	var page: DialoguePage = session_runner.current_page()
	if page != null:
		dialogue_view.set_portrait(_resolve_portrait(page.speaker_id, portrait_id))


func _resolve_portrait(speaker_id: String, portrait_id: String) -> Texture2D:
	if speaker_catalog == null or portrait_id.is_empty():
		return null
	return speaker_catalog.portrait(speaker_id, portrait_id)


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	match setting:
		&"animated_text_enabled":
			dialogue_view.set_animated_text_enabled(bool(value))
		&"reduced_motion":
			dialogue_view.set_reduced_motion(bool(value))
		&"voice_enabled":
			voice_emitter.enabled = bool(value)
			voice_player.enabled = bool(value)
		&"ui_sounds_enabled":
			choice_sound_player.enabled = bool(value)


func _on_conversation_finished(conversation_id: String) -> void:
	voice_player.stop_all()
	choice_sound_player.stop_all()
	active = false
	visible = false
	conversation_finished.emit(conversation_id)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("move_left") and session_runner.choices_are_active():
		move_choice(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") and session_runner.choices_are_active():
		move_choice(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") and session_runner.choices_are_active():
		cancel_choice()
		get_viewport().set_input_as_handled()
