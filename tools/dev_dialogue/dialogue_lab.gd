extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const RevealScript := preload("res://scripts/dialogue/dialogue_reveal_controller.gd")
const HOOD_PORTRAIT := preload("res://assets/ui/portraits/hood_test_portrait.png")
const DEMO_PATH := "res://content/dialogue/hood_authoring_demo.dialogue"

var dialogue_view
var conversation
var reveal_controller
var page_selector: OptionButton
var event_selector: OptionButton
var placement_selector: OptionButton
var speed_selector: OptionButton
var play_button: Button
var instant_toggle: CheckButton
var status_label: Label
var playing := true
var current_portrait_id := ""
var current_portrait_event_index := -1


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var parsed = DialogueParserScript.parse_file(DEMO_PATH)
	conversation = parsed.conversation
	_build_background()
	dialogue_view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(dialogue_view)
	reveal_controller = RevealScript.new()
	reveal_controller.visibility_changed.connect(_on_visibility_changed)
	reveal_controller.portrait_changed.connect(_on_portrait_changed)
	reveal_controller.page_completed.connect(_on_page_completed)
	reveal_controller.advance_requested.connect(_on_advance_requested)
	_build_controls()
	if parsed.is_valid():
		_populate_pages()
		_refresh_page()
	else:
		status_label.text = "Fixture errors:\n%s" % "\n".join(parsed.errors)


func _process(delta: float) -> void:
	if playing and reveal_controller != null:
		reveal_controller.advance(delta)


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("23272d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "DIALOGUE LAB\nDeterministic reveal milestone"
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
	speed_selector = _add_option(controls, "Player speed", ["50%", "100%", "200%", "400%"])
	speed_selector.select(1)
	page_selector.item_selected.connect(func(_index: int): _refresh_page())
	event_selector.item_selected.connect(func(_index: int): _refresh_portrait_state())
	placement_selector.item_selected.connect(func(index: int): dialogue_view.set_placement(index))
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
	instant_toggle = CheckButton.new()
	instant_toggle.text = "Instant text"
	instant_toggle.toggled.connect(_on_instant_toggled)
	controls.add_child(instant_toggle)
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


func _refresh_page() -> void:
	if conversation == null or conversation.pages.is_empty():
		return
	var page = conversation.pages[page_selector.selected]
	event_selector.clear()
	event_selector.add_item("Initial: %s" % _portrait_label(page.initial_portrait_id))
	event_selector.set_item_metadata(0, page.initial_portrait_id)
	for event in page.events:
		event_selector.add_item("@%d → %s" % [event.visible_character_index, event.value])
		event_selector.set_item_metadata(event_selector.item_count - 1, event.value)
	event_selector.select(0)
	var choices := PackedStringArray()
	for index in range(page.choices.size()):
		choices.append("%s%s" % ["▶ " if index == 0 else "  ", page.choices[index].text])
	dialogue_view.configure(page.speaker_name, page.speaker_known, page.text, _resolve_portrait(page.initial_portrait_id), choices)
	dialogue_view.set_page_complete(false)
	dialogue_view.dialogue_text.visible_characters = 0
	reveal_controller.paused = false
	playing = not reveal_controller.instant_text
	play_button.text = "Pause" if playing else "Play"
	reveal_controller.start(page)


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
	var revealed: int = reveal_controller.visible_character_count if reveal_controller != null else 0
	var reveal_state := "complete" if reveal_controller != null and reveal_controller.completed else ("playing" if playing else "paused")
	var next_delay: float = reveal_controller.delay_before_next_character() if reveal_controller != null and not reveal_controller.completed else 0.0
	status_label.text = "Conversation:\n  %s\nSpeaker ID: %s\nPortrait: %s\n  %s\nReveal: %d / %d (%s)\nNext delay: %.3fs\nEvents: %d\nChoices: %s" % [
		conversation.id,
		page.speaker_id,
		_portrait_label(portrait_id),
		event_description,
		revealed,
		page.text.length(),
		reveal_state,
		next_delay,
		page.events.size(),
		", ".join(targets) if not targets.is_empty() else "none",
	]


func _on_visibility_changed(count: int) -> void:
	dialogue_view.dialogue_text.visible_characters = count
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
	playing = not playing and not reveal_controller.completed
	play_button.text = "Pause" if playing else "Play"
	reveal_controller.paused = not playing
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _restart_page() -> void:
	reveal_controller.paused = false
	_refresh_page()


func _step_character() -> void:
	playing = false
	reveal_controller.paused = true
	play_button.text = "Play"
	reveal_controller.reveal_one()


func _complete_page() -> void:
	reveal_controller.complete_immediately()


func _confirm_page() -> void:
	reveal_controller.confirm()


func _on_speed_selected(index: int) -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0]
	reveal_controller.set_player_speed(speeds[index])
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_instant_toggled(enabled: bool) -> void:
	reveal_controller.set_instant_text(enabled)
	if enabled:
		playing = false
		play_button.text = "Play"


func _on_page_completed() -> void:
	playing = false
	play_button.text = "Play"
	dialogue_view.set_page_complete(true)
	_refresh_status(conversation.pages[page_selector.selected], current_portrait_id, current_portrait_event_index)


func _on_advance_requested() -> void:
	var next_page: int = (page_selector.selected + 1) % conversation.pages.size()
	page_selector.select(next_page)
	_refresh_page()


func _resolve_portrait(portrait_id: String) -> Texture2D:
	return null if portrait_id.is_empty() else HOOD_PORTRAIT


func _portrait_label(portrait_id: String) -> String:
	return portrait_id if not portrait_id.is_empty() else "none"
