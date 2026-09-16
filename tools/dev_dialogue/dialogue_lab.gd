extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const SessionRunnerScript := preload("res://scripts/dialogue/dialogue_session_runner.gd")
const TextSpanScript := preload("res://scripts/dialogue/dialogue_text_span.gd")
const VoiceEmitterScript := preload("res://scripts/dialogue/dialogue_voice_emitter.gd")
const VoicePlayerScript := preload("res://scripts/ui/dialogue_voice_player.gd")
const ChoiceSoundPlayerScript := preload("res://scripts/ui/dialogue_choice_sound_player.gd")
const SPEAKER_CATALOG := preload("res://assets/ui/dialogue/dialogue_speaker_catalog.tres")
const PIXEL_OPERATOR_8 := preload("res://assets/ui/fonts/pixel_operator/PixelOperator8.ttf")
const PIXEL_OPERATOR_8_BOLD := preload("res://assets/ui/fonts/pixel_operator/PixelOperator8-Bold.ttf")
const PIXEL_OPERATOR_MONO_8 := preload("res://assets/ui/fonts/pixel_operator/PixelOperatorMono8.ttf")
const PIXEL_OPERATOR_MONO_8_BOLD := preload("res://assets/ui/fonts/pixel_operator/PixelOperatorMono8-Bold.ttf")
const PIXEL_OPERATOR := preload("res://assets/ui/fonts/pixel_operator/PixelOperator.ttf")
const PIXEL_OPERATOR_BOLD := preload("res://assets/ui/fonts/pixel_operator/PixelOperator-Bold.ttf")
const DEMO_PATH := "res://content/dialogue/hood_authoring_demo.dialogue"

var dialogue_view
var lab_skin
var conversation
var session_runner
var voice_emitter
var voice_player
var choice_sound_player
var page_selector: OptionButton
var event_selector: OptionButton
var placement_selector: OptionButton
var speed_selector: OptionButton
var font_selector: OptionButton
var font_size_selector: OptionButton
var play_button: Button
var instant_toggle: CheckButton
var voice_toggle: CheckButton
var animated_text_toggle: CheckButton
var reduced_motion_toggle: CheckButton
var status_label: Label
var playing := true
var current_portrait_id := ""
var current_portrait_event_index := -1
var current_font_label := "Pixel Operator 8 + Bold plaque"
var logical_font_size := 8
var last_voice_description := "none"
var last_choice_result := "none"


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var parsed = DialogueParserScript.parse_file(DEMO_PATH)
	conversation = parsed.conversation
	_build_background()
	dialogue_view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(dialogue_view)
	lab_skin = dialogue_view.skin.duplicate(true)
	session_runner = SessionRunnerScript.new()
	session_runner.name = "DialogueSessionRunner"
	add_child(session_runner)
	voice_emitter = VoiceEmitterScript.new()
	voice_player = VoicePlayerScript.new()
	voice_player.name = "DialogueVoicePlayer"
	add_child(voice_player)
	choice_sound_player = ChoiceSoundPlayerScript.new()
	choice_sound_player.name = "DialogueChoiceSoundPlayer"
	choice_sound_player.set_skin(lab_skin)
	add_child(choice_sound_player)
	session_runner.visibility_changed.connect(_on_visibility_changed)
	session_runner.portrait_changed.connect(_on_portrait_changed)
	session_runner.character_revealed.connect(voice_emitter.on_character_revealed)
	voice_emitter.voice_requested.connect(voice_player.play_request)
	voice_emitter.voice_requested.connect(_on_voice_requested)
	session_runner.page_started.connect(_on_page_started)
	session_runner.page_completed.connect(_on_page_completed)
	session_runner.choice_selection_changed.connect(_on_choice_selection_changed)
	session_runner.choice_confirmed.connect(_on_choice_confirmed)
	session_runner.target_emitted.connect(_on_target_emitted)
	session_runner.choice_cancel_requested.connect(_on_choice_cancel_requested)
	session_runner.choice_sound_requested.connect(choice_sound_player.play_cue)
	session_runner.setting_changed.connect(_on_setting_changed)
	session_runner.conversation_finished.connect(_on_conversation_finished)
	_build_controls()
	_apply_font_candidate(2)
	if parsed.is_valid():
		_populate_pages()
		_refresh_page()
	else:
		status_label.text = "Fixture errors:\n%s" % "\n".join(parsed.errors)


func _process(delta: float) -> void:
	if playing and session_runner != null:
		session_runner.advance(delta)


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("23272d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "DIALOGUE LAB\nInteractive choices"
	title.position = Vector2(20, 18)
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color("8e969f")
	background.add_child(title)


func _build_controls() -> void:
	var controls_panel := PanelContainer.new()
	controls_panel.name = "LabControls"
	controls_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_panel.offset_left = -316
	controls_panel.offset_top = 16
	controls_panel.offset_right = -16
	controls_panel.custom_minimum_size = Vector2(300, 0)
	controls_panel.z_index = 20
	add_child(controls_panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls_panel.add_child(controls)
	var heading := Label.new()
	heading.text = "Parsed conversation"
	heading.add_theme_font_size_override("font_size", 16)
	controls.add_child(heading)
	var source := Label.new()
	source.text = DEMO_PATH.get_file()
	source.modulate = Color("aeb5bd")
	controls.add_child(source)
	page_selector = _add_option(controls, "Page", [])
	event_selector = _add_option(controls, "Portrait state", [])
	placement_selector = _add_option(controls, "Placement", ["Bottom", "Top", "Center", "Battle near", "Battle far"])
	font_selector = _add_option(controls, "Dialogue font", ["Engine default", "Pixel Operator 8", "Pixel Operator 8 + Bold plaque", "Pixel Operator Mono 8 + Bold", "Pixel Operator + Bold"])
	font_selector.select(2)
	font_size_selector = _add_option(controls, "Logical font size", ["8 px", "16 px"])
	speed_selector = _add_option(controls, "Player speed", ["50%", "100%", "200%", "400%"])
	speed_selector.select(1)
	page_selector.item_selected.connect(func(_index: int): _refresh_page())
	event_selector.item_selected.connect(func(_index: int): _refresh_portrait_state())
	placement_selector.item_selected.connect(func(index: int): dialogue_view.set_placement(index))
	font_selector.item_selected.connect(_apply_font_candidate)
	font_size_selector.item_selected.connect(_on_font_size_selected)
	speed_selector.item_selected.connect(_on_speed_selected)
	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	play_button = _add_button(buttons, "Pause", _toggle_playing)
	_add_button(buttons, "Restart", _restart_page)
	_add_button(buttons, "Step", _step_character)
	var action_buttons := HBoxContainer.new()
	controls.add_child(action_buttons)
	_add_button(action_buttons, "Complete", _complete_page)
	_add_button(action_buttons, "Confirm", _confirm_page)
	var choice_buttons := HBoxContainer.new()
	controls.add_child(choice_buttons)
	_add_button(choice_buttons, "Choice ←", func(): _move_choice(-1))
	_add_button(choice_buttons, "Choice →", func(): _move_choice(1))
	_add_button(choice_buttons, "Cancel", _cancel_choice)
	instant_toggle = CheckButton.new()
	instant_toggle.text = "Instant text"
	instant_toggle.toggled.connect(_on_instant_toggled)
	controls.add_child(instant_toggle)
	voice_toggle = CheckButton.new()
	voice_toggle.text = "Character voice requests"
	voice_toggle.button_pressed = true
	voice_toggle.toggled.connect(_on_voice_toggled)
	controls.add_child(voice_toggle)
	animated_text_toggle = CheckButton.new()
	animated_text_toggle.text = "Animated text"
	animated_text_toggle.button_pressed = true
	animated_text_toggle.toggled.connect(_on_animated_text_toggled)
	controls.add_child(animated_text_toggle)
	reduced_motion_toggle = CheckButton.new()
	reduced_motion_toggle.text = "Reduced motion"
	reduced_motion_toggle.toggled.connect(_on_reduced_motion_toggled)
	controls.add_child(reduced_motion_toggle)
	status_label = Label.new()
	status_label.name = "ParserStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 280
	status_label.modulate = Color("b8bec5")
	controls.add_child(status_label)


func _add_option(parent: Control, label_text: String, values: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for value in values:
		option.add_item(value)
	parent.add_child(option)
	return option


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _populate_pages() -> void:
	page_selector.clear()
	for index in range(conversation.pages.size()):
		var page = conversation.pages[index]
		page_selector.add_item("%d: %s" % [index + 1, page.text.replace("\n", " ").left(28)])
	var requested_page := _requested_initial_page()
	if requested_page >= 0 and requested_page < page_selector.item_count:
		page_selector.select(requested_page)


func _requested_initial_page() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dialogue-page="):
			var value := argument.trim_prefix("--dialogue-page=")
			if value.is_valid_int():
				return value.to_int() - 1
	return -1


func _refresh_page() -> void:
	if conversation == null or conversation.pages.is_empty():
		return
	session_runner.start(conversation, page_selector.selected)


func _on_page_started(page, page_index: int, _page_count: int) -> void:
	if page_selector.selected != page_index:
		page_selector.select(page_index)
	event_selector.clear()
	event_selector.add_item("Initial: %s" % _portrait_label(page.initial_portrait_id))
	event_selector.set_item_metadata(0, page.initial_portrait_id)
	for event in page.events:
		event_selector.add_item("@%d → %s" % [event.visible_character_index, event.value])
		event_selector.set_item_metadata(event_selector.item_count - 1, event.value)
	event_selector.select(0)
	var choices := PackedStringArray()
	for index in range(page.choices.size()):
		choices.append(page.choices[index].text)
	var speaker_profile = SPEAKER_CATALOG.profile(page.speaker_id)
	voice_emitter.set_profile(speaker_profile)
	last_voice_description = "none"
	last_choice_result = "none"
	current_portrait_id = page.initial_portrait_id
	current_portrait_event_index = -1
	var display_name: String = page.speaker_name if not page.speaker_name.is_empty() else (speaker_profile.default_display_name if speaker_profile != null else "")
	dialogue_view.configure(display_name, page.speaker_known, page.text, _resolve_portrait(page.initial_portrait_id), choices, page.presentation_spans)
	dialogue_view.set_page_complete(false)
	dialogue_view.set_visible_character_count(0)
	playing = not session_runner.settings.instant_text
	play_button.text = "Pause" if playing else "Play"


func _refresh_portrait_state() -> void:
	if conversation == null or conversation.pages.is_empty() or event_selector.item_count == 0:
		return
	var page = conversation.pages[page_selector.selected]
	var portrait_id: String = event_selector.get_item_metadata(event_selector.selected)
	var visible_index: int = -1 if event_selector.selected == 0 else page.events[event_selector.selected - 1].visible_character_index
	_apply_portrait(portrait_id, visible_index)


func _refresh_status(page, portrait_id: String, visible_index: int) -> void:
	var event_description := "initial portrait" if visible_index < 0 else "event at visible character %d" % visible_index
	var targets := PackedStringArray()
	for choice in page.choices:
		targets.append("%s → %s" % [choice.text, choice.target])
	var revealed: int = session_runner.visible_character_count() if session_runner != null else 0
	var reveal_state := "complete" if session_runner != null and session_runner.is_page_complete() else ("playing" if playing else "paused")
	var next_delay: float = session_runner.next_character_delay() if session_runner != null else 0.0
	var speaker_profile = SPEAKER_CATALOG.profile(page.speaker_id)
	var voice_asset_state := "silent profile" if speaker_profile != null and not speaker_profile.voice_enabled else ("asset ready" if speaker_profile != null and not speaker_profile.voice_clips.is_empty() else "awaiting voice asset")
	var content_size: Vector2i = dialogue_view.text_content_size()
	var overflow_state := "OVERFLOW" if dialogue_view.text_overflows() else "fits"
	var motion_state := "reduced" if reduced_motion_toggle.button_pressed else ("animated" if animated_text_toggle.button_pressed else "disabled")
	var choice_state := "inactive" if not session_runner.choices_are_active() else "selected %d/%d" % [session_runner.selected_choice_index() + 1, page.choices.size()]
	status_label.text = "Font: %s @ %d logical px\nConversation:\n  %s\nSpeaker ID: %s (%s)\nPortrait: %s\n  %s\nReveal: %d / %d (%s)\nNext delay: %.3fs\nLayout: %dx%d (%s)\nMotion: %s\nVoice requests: %d (%s)\nLast voice: %s\nPresentation: %s\nEvents: %d\nChoices: %s\nChoice state: %s\nLast choice: %s" % [
		current_font_label,
		logical_font_size,
		conversation.id,
		page.speaker_id,
		voice_asset_state,
		_portrait_label(portrait_id),
		event_description,
		revealed,
		page.text.length(),
		reveal_state,
		next_delay,
		content_size.x,
		content_size.y,
		overflow_state,
		motion_state,
		voice_emitter.request_count if voice_emitter != null else 0,
		"enabled" if voice_emitter != null and voice_emitter.enabled else "disabled",
		last_voice_description,
		_presentation_description(page),
		page.events.size(),
		", ".join(targets) if not targets.is_empty() else "none",
		choice_state,
		last_choice_result,
	]


func _presentation_description(page) -> String:
	var descriptions := PackedStringArray()
	for span in page.presentation_spans:
		var kind := "color:%s" % span.value if span.kind == TextSpanScript.Kind.COLOR else ("size:%s" % span.value if span.kind == TextSpanScript.Kind.FONT_SIZE else ("jiggle:%s" % span.value if span.kind == TextSpanScript.Kind.JIGGLE else "caps"))
		descriptions.append("%s@%d..%d" % [kind, span.start_index, span.end_index])
	return ", ".join(descriptions) if not descriptions.is_empty() else "none"


func _apply_font_candidate(index: int) -> void:
	match index:
		0:
			current_font_label = "Engine default"
			lab_skin.body_font = null
			lab_skin.name_font = null
		1:
			current_font_label = "Pixel Operator 8"
			lab_skin.body_font = PIXEL_OPERATOR_8
			lab_skin.name_font = PIXEL_OPERATOR_8
		2:
			current_font_label = "Pixel Operator 8 + Bold plaque"
			lab_skin.body_font = PIXEL_OPERATOR_8
			lab_skin.name_font = PIXEL_OPERATOR_8_BOLD
		3:
			current_font_label = "Pixel Operator Mono 8 + Bold"
			lab_skin.body_font = PIXEL_OPERATOR_MONO_8
			lab_skin.name_font = PIXEL_OPERATOR_MONO_8_BOLD
		4:
			current_font_label = "Pixel Operator + Bold"
			lab_skin.body_font = PIXEL_OPERATOR
			lab_skin.name_font = PIXEL_OPERATOR_BOLD
	lab_skin.body_font_size = logical_font_size
	lab_skin.name_font_size = logical_font_size
	lab_skin.choice_font_size = logical_font_size
	lab_skin.semantic_size_values = PackedInt32Array([maxi(1, roundi(logical_font_size * 0.75)), logical_font_size, maxi(1, roundi(logical_font_size * 1.5))])
	dialogue_view.set_skin(lab_skin)
	choice_sound_player.set_skin(lab_skin)
	if page_selector != null and page_selector.item_count > 0:
		_restart_page()


func _on_font_size_selected(index: int) -> void:
	logical_font_size = 8 if index == 0 else 16
	_apply_font_candidate(font_selector.selected)


func _on_visibility_changed(count: int) -> void:
	dialogue_view.set_visible_character_count(count)
	if conversation != null and not conversation.pages.is_empty():
		_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_portrait_changed(portrait_id: String, visible_index: int) -> void:
	_apply_portrait(portrait_id, visible_index)
	var page = conversation.pages[page_selector.selected]
	var selector_index := 0
	for index in range(page.events.size()):
		if page.events[index].visible_character_index == visible_index and page.events[index].value == portrait_id:
			selector_index = index + 1
			break
	event_selector.select(selector_index)


func _apply_portrait(portrait_id: String, visible_index: int) -> void:
	current_portrait_id = portrait_id
	current_portrait_event_index = visible_index
	dialogue_view.portrait_texture.texture = _resolve_portrait(portrait_id)
	dialogue_view.portrait_texture.visible = not portrait_id.is_empty()
	dialogue_view.empty_portrait.visible = portrait_id.is_empty()
	if conversation != null and not conversation.pages.is_empty():
		_refresh_status(conversation.pages[page_selector.selected], portrait_id, visible_index)


func _toggle_playing() -> void:
	playing = not playing and not session_runner.is_page_complete()
	play_button.text = "Pause" if playing else "Play"
	session_runner.set_paused(not playing)
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _restart_page() -> void:
	session_runner.restart_page()


func _step_character() -> void:
	playing = false
	session_runner.set_paused(true)
	play_button.text = "Play"
	session_runner.reveal_one()


func _complete_page() -> void:
	session_runner.complete_page()


func _confirm_page() -> void:
	session_runner.confirm()


func _move_choice(direction: int) -> void:
	session_runner.move_choice(direction)


func _cancel_choice() -> void:
	session_runner.cancel_choice()


func _on_speed_selected(index: int) -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0]
	session_runner.set_player_speed(speeds[index])
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_instant_toggled(enabled: bool) -> void:
	session_runner.set_instant_text(enabled)


func _on_voice_toggled(enabled: bool) -> void:
	session_runner.set_voice_enabled(enabled)


func _on_animated_text_toggled(enabled: bool) -> void:
	session_runner.set_animated_text_enabled(enabled)


func _on_reduced_motion_toggled(enabled: bool) -> void:
	session_runner.set_reduced_motion(enabled)


func _on_voice_requested(stream: AudioStream, pitch: float, _volume_db: float, visible_index: int, character: String) -> void:
	last_voice_description = "@%d '%s' pitch %.2f%s" % [visible_index, character, pitch, " (no clip yet)" if stream == null else ""]


func _on_page_completed(_page, _page_index: int) -> void:
	playing = false
	play_button.text = "Play"
	dialogue_view.set_page_complete(true)
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_choice_selection_changed(selected_index: int) -> void:
	dialogue_view.set_selected_choice(selected_index)
	if conversation != null and not conversation.pages.is_empty():
		_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_choice_confirmed(selected_index: int, text: String, target: String) -> void:
	last_choice_result = "confirmed #%d '%s'" % [selected_index + 1, text]
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_target_emitted(target: String) -> void:
	last_choice_result += " → %s (emitted only)" % target
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_choice_cancel_requested() -> void:
	last_choice_result = "cancel requested (no story mutation)"
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	match setting:
		&"instant_text":
			if bool(value):
				playing = false
				play_button.text = "Play"
		&"animated_text_enabled":
			dialogue_view.set_animated_text_enabled(bool(value))
		&"reduced_motion":
			dialogue_view.set_reduced_motion(bool(value))
		&"voice_enabled":
			voice_emitter.enabled = bool(value)
			voice_player.enabled = bool(value)
		&"ui_sounds_enabled":
			choice_sound_player.enabled = bool(value)
	if conversation != null and not conversation.pages.is_empty() and page_selector.item_count > 0:
		_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_conversation_finished(conversation_id: String) -> void:
	playing = false
	play_button.text = "Play"
	last_choice_result = "conversation finished: %s" % conversation_id
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left") and session_runner.choices_are_active():
		_move_choice(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") and session_runner.choices_are_active():
		_move_choice(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_confirm_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") and session_runner.choices_are_active():
		_cancel_choice()
		get_viewport().set_input_as_handled()


func _resolve_portrait(portrait_id: String) -> Texture2D:
	if portrait_id.is_empty() or conversation == null or conversation.pages.is_empty():
		return null
	return SPEAKER_CATALOG.portrait(conversation.pages[page_selector.selected].speaker_id, portrait_id)


func _portrait_label(portrait_id: String) -> String:
	return portrait_id if not portrait_id.is_empty() else "none"
