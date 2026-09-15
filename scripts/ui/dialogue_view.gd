extends Control
class_name DialogueView

enum Placement { BOTTOM, TOP, CENTER, BATTLE_NEAR, BATTLE_FAR }

const REFERENCE_HEIGHT := 180
const MAX_PANEL_WIDTH := 304
const PANEL_HEIGHT := 58
const OUTER_MARGIN := 8
const PORTRAIT_SIZE := 48

var placement := Placement.BOTTOM
var content_stage: Control
var dialogue_panel: Panel
var portrait_panel: Panel
var portrait_texture: TextureRect
var empty_portrait: Control
var speaker_plate: Panel
var speaker_label: Label
var dialogue_text: RichTextLabel
var choice_label: Label
var continue_indicator: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_view()
	get_viewport().size_changed.connect(_layout_from_viewport)
	_layout_from_viewport()


func configure(speaker: String, identified: bool, text: String, portrait: Texture2D = null, choices: PackedStringArray = PackedStringArray()) -> void:
	_ensure_built()
	speaker_label.text = speaker if identified and not speaker.is_empty() else "???"
	dialogue_text.text = text
	portrait_texture.texture = portrait
	portrait_texture.visible = portrait != null
	empty_portrait.visible = portrait == null
	choice_label.text = "   ".join(choices)
	choice_label.visible = not choices.is_empty()
	continue_indicator.visible = choices.is_empty()


func set_placement(value: Placement) -> void:
	placement = value
	if is_inside_tree():
		_layout_from_viewport()


func apply_window_size(window_size: Vector2i) -> void:
	_ensure_built()
	var layout := calculate_layout(window_size, placement)
	content_stage.position = Vector2.ZERO
	content_stage.size = Vector2(layout.logical_size)
	content_stage.scale = Vector2.ONE * layout.ui_scale
	dialogue_panel.position = layout.panel_rect.position
	dialogue_panel.size = layout.panel_rect.size
	_layout_panel_contents(layout.panel_rect.size)


static func calculate_layout(window_size: Vector2i, requested_placement: Placement = Placement.BOTTOM) -> Dictionary:
	var safe_window := Vector2i(maxi(1, window_size.x), maxi(1, window_size.y))
	var ui_scale := maxi(1, floori(float(safe_window.y) / REFERENCE_HEIGHT))
	var logical_size := Vector2i(
		maxi(1, floori(float(safe_window.x) / ui_scale)),
		maxi(1, floori(float(safe_window.y) / ui_scale))
	)
	var panel_width := mini(MAX_PANEL_WIDTH, maxi(1, logical_size.x - OUTER_MARGIN * 2))
	var panel_height := mini(PANEL_HEIGHT, maxi(1, logical_size.y - OUTER_MARGIN * 2))
	var panel_x := floori((logical_size.x - panel_width) * 0.5)
	var panel_y := logical_size.y - panel_height - OUTER_MARGIN
	match requested_placement:
		Placement.TOP, Placement.BATTLE_FAR:
			panel_y = OUTER_MARGIN
		Placement.CENTER:
			panel_y = floori((logical_size.y - panel_height) * 0.5)
		Placement.BOTTOM, Placement.BATTLE_NEAR:
			pass
	return {
		"ui_scale": ui_scale,
		"logical_size": logical_size,
		"panel_rect": Rect2i(panel_x, panel_y, panel_width, panel_height),
	}


func _ensure_built() -> void:
	if content_stage == null:
		_build_view()


func _build_view() -> void:
	if content_stage != null:
		return
	content_stage = Control.new()
	content_stage.name = "ContentStage"
	content_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_stage)

	dialogue_panel = Panel.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.add_theme_stylebox_override("panel", _box(Color("17191d"), Color("899097"), 2, 2))
	content_stage.add_child(dialogue_panel)

	portrait_panel = Panel.new()
	portrait_panel.name = "PortraitPanel"
	portrait_panel.add_theme_stylebox_override("panel", _box(Color("292d32"), Color("a8afb5"), 2, 1))
	dialogue_panel.add_child(portrait_panel)

	portrait_texture = TextureRect.new()
	portrait_texture.name = "PortraitTexture"
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_panel.add_child(portrait_texture)

	empty_portrait = Control.new()
	empty_portrait.name = "EmptyPortrait"
	portrait_panel.add_child(empty_portrait)
	var silhouette := Label.new()
	silhouette.name = "Silhouette"
	silhouette.text = "?"
	silhouette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	silhouette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	silhouette.modulate = Color("6f757b")
	silhouette.add_theme_font_size_override("font_size", 26)
	silhouette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_portrait.add_child(silhouette)

	dialogue_text = RichTextLabel.new()
	dialogue_text.name = "DialogueText"
	dialogue_text.fit_content = false
	dialogue_text.scroll_active = false
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.add_theme_font_size_override("normal_font_size", 8)
	dialogue_text.add_theme_color_override("default_color", Color("f0eee8"))
	dialogue_panel.add_child(dialogue_text)

	choice_label = Label.new()
	choice_label.name = "ChoiceList"
	choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	choice_label.add_theme_font_size_override("font_size", 7)
	choice_label.modulate = Color("d8c590")
	dialogue_panel.add_child(choice_label)

	continue_indicator = Label.new()
	continue_indicator.name = "ContinueIndicator"
	continue_indicator.text = "▼"
	continue_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_indicator.add_theme_font_size_override("font_size", 7)
	dialogue_panel.add_child(continue_indicator)

	speaker_plate = Panel.new()
	speaker_plate.name = "SpeakerPlate"
	speaker_plate.add_theme_stylebox_override("panel", _box(Color("b6b9b8"), Color("555b61"), 1, 1))
	dialogue_panel.add_child(speaker_plate)
	speaker_label = Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.add_theme_font_size_override("font_size", 8)
	speaker_label.add_theme_color_override("font_color", Color("191b1e"))
	speaker_plate.add_child(speaker_label)


func _layout_from_viewport() -> void:
	apply_window_size(Vector2i(get_viewport_rect().size))


func _layout_panel_contents(panel_size: Vector2) -> void:
	var portrait_side := minf(PORTRAIT_SIZE, panel_size.y - 8.0)
	portrait_panel.position = Vector2(4, 4)
	portrait_panel.size = Vector2(portrait_side, portrait_side)
	portrait_texture.position = Vector2(2, 2)
	portrait_texture.size = portrait_panel.size - Vector2(4, 4)
	empty_portrait.position = Vector2(2, 2)
	empty_portrait.size = portrait_panel.size - Vector2(4, 4)

	var text_left := portrait_panel.position.x + portrait_panel.size.x + 6.0
	var text_width := maxf(1.0, panel_size.x - text_left - 6.0)
	speaker_plate.position = Vector2(text_left - 2.0, -5.0)
	speaker_plate.size = Vector2(minf(92.0, text_width + 2.0), 13.0)
	speaker_label.position = Vector2(5, 0)
	speaker_label.size = speaker_plate.size - Vector2(10, 0)
	dialogue_text.position = Vector2(text_left, 10)
	dialogue_text.size = Vector2(text_width, maxf(1.0, panel_size.y - 24.0))
	choice_label.position = Vector2(text_left, panel_size.y - 13.0)
	choice_label.size = Vector2(text_width - 14.0, 10.0)
	continue_indicator.position = Vector2(panel_size.x - 14.0, panel_size.y - 13.0)
	continue_indicator.size = Vector2(10, 10)


func _box(fill: Color, border: Color, border_width: int, corner_radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style
