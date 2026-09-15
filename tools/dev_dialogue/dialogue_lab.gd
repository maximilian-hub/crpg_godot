extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueViewScript := preload("res://scripts/ui/dialogue_view.gd")
const HOOD_PLACEHOLDER := preload("res://assets/overworld/characters/hood/hood_down_0001.png")

var dialogue_view
var portrait_selector: OptionButton
var identity_selector: OptionButton
var placement_selector: OptionButton
var content_selector: OptionButton


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_build_background()
	dialogue_view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(dialogue_view)
	_build_controls()
	_refresh_sample()


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("23272d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := Label.new()
	title.text = "DIALOGUE LAB\nStatic layout milestone"
	title.position = Vector2(20, 18)
	title.add_theme_font_size_override("font_size", 18)
	title.modulate = Color("8e969f")
	background.add_child(title)


func _build_controls() -> void:
	var controls_panel := PanelContainer.new()
	controls_panel.name = "LabControls"
	controls_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls_panel.position = Vector2(-250, 16)
	controls_panel.custom_minimum_size = Vector2(234, 0)
	controls_panel.z_index = 20
	add_child(controls_panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls_panel.add_child(controls)
	var heading := Label.new()
	heading.text = "Presentation states"
	heading.add_theme_font_size_override("font_size", 16)
	controls.add_child(heading)
	portrait_selector = _add_option(controls, "Portrait", ["Hood placeholder", "Empty state"])
	identity_selector = _add_option(controls, "Identity", ["Known: Hood", "Unknown: ???"])
	placement_selector = _add_option(controls, "Placement", ["Bottom", "Top", "Center", "Battle near", "Battle far"])
	content_selector = _add_option(controls, "Content", ["Ordinary page", "Long wrapping page", "Choices"])
	portrait_selector.item_selected.connect(func(_index: int): _refresh_sample())
	identity_selector.item_selected.connect(func(_index: int): _refresh_sample())
	placement_selector.item_selected.connect(func(_index: int): _refresh_sample())
	content_selector.item_selected.connect(func(_index: int): _refresh_sample())
	var note := Label.new()
	note.text = "Resize the window to exercise the independent 320×180-style logical UI grid and integer scale breakpoints."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 214
	note.modulate = Color("b8bec5")
	controls.add_child(note)


func _add_option(parent: Control, label_text: String, values: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for value in values:
		option.add_item(value)
	parent.add_child(option)
	return option


func _refresh_sample() -> void:
	var sample_text := "The stones remember every move. Shall we begin?"
	var choices := PackedStringArray()
	match content_selector.selected:
		1:
			sample_text = "This deliberately longer sample checks readable left-justified wrapping, punctuation, apostrophes, numbers like 128, and a proper name: Ernest."
		2:
			sample_text = "Will you challenge me?"
			choices = PackedStringArray(["▶ Yes", "  No"])
	var portrait: Texture2D = HOOD_PLACEHOLDER if portrait_selector.selected == 0 else null
	dialogue_view.set_placement(placement_selector.selected)
	dialogue_view.configure("Hood", identity_selector.selected == 0, sample_text, portrait, choices)
