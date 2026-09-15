extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueParserScript := preload("res://scripts/dialogue/dialogue_parser.gd")
const HOOD_PORTRAIT := preload("res://assets/ui/portraits/hood_test_portrait.png")
const DEMO_PATH := "res://content/dialogue/hood_authoring_demo.dialogue"

var dialogue_view
var conversation
var page_selector: OptionButton
var event_selector: OptionButton
var placement_selector: OptionButton
var status_label: Label


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var parsed = DialogueParserScript.parse_file(DEMO_PATH)
	conversation = parsed.conversation
	_build_background()
	dialogue_view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(dialogue_view)
	_build_controls()
	if parsed.is_valid():
		_populate_pages()
		_refresh_page()
	else:
		status_label.text = "Fixture errors:\n%s" % "\n".join(parsed.errors)


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("23272d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "DIALOGUE LAB\nExternal authoring milestone"
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
	page_selector.item_selected.connect(func(_index: int): _refresh_page())
	event_selector.item_selected.connect(func(_index: int): _refresh_portrait_state())
	placement_selector.item_selected.connect(func(index: int): dialogue_view.set_placement(index))
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
	_refresh_status(page, page.initial_portrait_id, -1)


func _refresh_portrait_state() -> void:
	if conversation == null or conversation.pages.is_empty() or event_selector.item_count == 0:
		return
	var page = conversation.pages[page_selector.selected]
	var portrait_id: String = event_selector.get_item_metadata(event_selector.selected)
	dialogue_view.portrait_texture.texture = _resolve_portrait(portrait_id)
	dialogue_view.portrait_texture.visible = not portrait_id.is_empty()
	dialogue_view.empty_portrait.visible = portrait_id.is_empty()
	var visible_index: int = -1 if event_selector.selected == 0 else page.events[event_selector.selected - 1].visible_character_index
	_refresh_status(page, portrait_id, visible_index)


func _refresh_status(page, portrait_id: String, visible_index: int) -> void:
	var event_description := "initial portrait" if visible_index < 0 else "event at visible character %d" % visible_index
	var targets := PackedStringArray()
	for choice in page.choices:
		targets.append("%s → %s" % [choice.text, choice.target])
	status_label.text = "Conversation:\n  %s\nSpeaker ID: %s\nPortrait: %s\n  %s\nVisible chars: %d\nEvents: %d\nChoices: %s" % [
		conversation.id,
		page.speaker_id,
		_portrait_label(portrait_id),
		event_description,
		page.text.length(),
		page.events.size(),
		", ".join(targets) if not targets.is_empty() else "none",
	]


func _resolve_portrait(portrait_id: String) -> Texture2D:
	return null if portrait_id.is_empty() else HOOD_PORTRAIT


func _portrait_label(portrait_id: String) -> String:
	return portrait_id if not portrait_id.is_empty() else "none"
