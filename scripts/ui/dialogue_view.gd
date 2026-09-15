extends Control
class_name DialogueView

enum Placement { BOTTOM, TOP, CENTER, BATTLE_NEAR, BATTLE_FAR }

const REFERENCE_HEIGHT := 180
const MAX_PRESENTATION_WIDTH := 304
const OUTER_MARGIN := 8
const DEFAULT_SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")

@export var skin: Resource = DEFAULT_SKIN

var placement := Placement.BOTTOM
var content_stage: Control
var dialogue_panel: Panel
var portrait_panel: Panel
var portrait_texture: TextureRect
var empty_portrait: Control
var empty_portrait_texture: TextureRect
var speaker_plate: Panel
var speaker_label: Label
var dialogue_text: RichTextLabel
var text_interior: TextureRect
var choice_label: Label
var continue_indicator: Label
var continue_indicator_texture: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_view()
	_apply_skin()
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
	continue_indicator.visible = choices.is_empty() and skin.continue_indicator_texture == null
	continue_indicator_texture.visible = choices.is_empty() and skin.continue_indicator_texture != null


func set_skin(value: Resource) -> void:
	skin = value if value != null else DEFAULT_SKIN
	_ensure_built()
	_apply_skin()
	if is_inside_tree():
		_layout_from_viewport()


func set_placement(value: Placement) -> void:
	placement = value
	if is_inside_tree():
		_layout_from_viewport()


func apply_window_size(window_size: Vector2i) -> void:
	_ensure_built()
	var layout := calculate_layout(window_size, placement, skin)
	content_stage.position = Vector2.ZERO
	content_stage.size = Vector2(layout.logical_size)
	content_stage.scale = Vector2.ONE * layout.ui_scale
	portrait_panel.position = layout.portrait_rect.position
	portrait_panel.size = layout.portrait_rect.size
	dialogue_panel.position = layout.text_rect.position
	dialogue_panel.size = layout.text_rect.size
	_layout_panel_contents()


static func calculate_layout(window_size: Vector2i, requested_placement: Placement = Placement.BOTTOM, requested_skin: Resource = null) -> Dictionary:
	var active_skin: Resource = requested_skin if requested_skin != null else DEFAULT_SKIN
	var safe_window := Vector2i(maxi(1, window_size.x), maxi(1, window_size.y))
	var ui_scale := maxi(1, floori(float(safe_window.y) / REFERENCE_HEIGHT))
	var logical_size := Vector2i(
		maxi(1, floori(float(safe_window.x) / ui_scale)),
		maxi(1, floori(float(safe_window.y) / ui_scale))
	)
	var group_width: int = mini(MAX_PRESENTATION_WIDTH, maxi(1, logical_size.x - OUTER_MARGIN * 2))
	var text_panel_height: int = mini(active_skin.panel_height, maxi(1, logical_size.y - OUTER_MARGIN * 2 - active_skin.name_plate_size.y))
	var group_height: int = text_panel_height + active_skin.name_plate_size.y
	var portrait_width: int = mini(group_width, maxi(1, roundi(group_height * active_skin.portrait_aspect_ratio)))
	var text_width: int = maxi(1, group_width - portrait_width + active_skin.panel_join_overlap)
	var group_x: int = floori((logical_size.x - group_width) * 0.5)
	var group_y: int = logical_size.y - group_height - OUTER_MARGIN
	match requested_placement:
		Placement.TOP, Placement.BATTLE_FAR:
			group_y = OUTER_MARGIN
		Placement.CENTER:
			group_y = floori((logical_size.y - group_height) * 0.5)
		Placement.BOTTOM, Placement.BATTLE_NEAR:
			pass
	return {
		"ui_scale": ui_scale,
		"logical_size": logical_size,
		"group_rect": Rect2i(group_x, group_y, group_width, group_height),
		"portrait_rect": Rect2i(group_x, group_y, portrait_width, group_height),
		"text_rect": Rect2i(group_x + portrait_width - active_skin.panel_join_overlap, group_y + active_skin.name_plate_size.y, text_width, text_panel_height),
	}


func _ensure_built() -> void:
	if content_stage == null:
		_build_view()
		_apply_skin()


func _build_view() -> void:
	if content_stage != null:
		return
	content_stage = Control.new()
	content_stage.name = "ContentStage"
	content_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_stage)

	portrait_panel = Panel.new()
	portrait_panel.name = "PortraitPanel"
	content_stage.add_child(portrait_panel)
	portrait_texture = TextureRect.new()
	portrait_texture.name = "PortraitTexture"
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_panel.add_child(portrait_texture)
	empty_portrait = Control.new()
	empty_portrait.name = "EmptyPortrait"
	portrait_panel.add_child(empty_portrait)
	empty_portrait_texture = TextureRect.new()
	empty_portrait_texture.name = "EmptyPortraitTexture"
	empty_portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	empty_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	empty_portrait_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	empty_portrait.add_child(empty_portrait_texture)
	var silhouette := Label.new()
	silhouette.name = "Silhouette"
	silhouette.text = "?"
	silhouette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	silhouette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_portrait.add_child(silhouette)

	dialogue_panel = Panel.new()
	dialogue_panel.name = "TextPanel"
	content_stage.add_child(dialogue_panel)
	text_interior = TextureRect.new()
	text_interior.name = "TextInterior"
	text_interior.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	text_interior.stretch_mode = TextureRect.STRETCH_TILE
	text_interior.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	text_interior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.add_child(text_interior)
	dialogue_text = RichTextLabel.new()
	dialogue_text.name = "DialogueText"
	dialogue_text.fit_content = false
	dialogue_text.scroll_active = false
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_panel.add_child(dialogue_text)
	choice_label = Label.new()
	choice_label.name = "ChoiceList"
	choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dialogue_panel.add_child(choice_label)
	continue_indicator = Label.new()
	continue_indicator.name = "ContinueIndicator"
	continue_indicator.text = "▼"
	continue_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_panel.add_child(continue_indicator)
	continue_indicator_texture = TextureRect.new()
	continue_indicator_texture.name = "ContinueIndicatorTexture"
	continue_indicator_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	continue_indicator_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	continue_indicator_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dialogue_panel.add_child(continue_indicator_texture)

	speaker_plate = Panel.new()
	speaker_plate.name = "SpeakerPlate"
	content_stage.add_child(speaker_plate)
	speaker_label = Label.new()
	speaker_label.name = "SpeakerLabel"
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_plate.add_child(speaker_label)


func _apply_skin() -> void:
	if skin == null:
		skin = DEFAULT_SKIN
	dialogue_panel.add_theme_stylebox_override("panel", skin.text_panel_style)
	portrait_panel.add_theme_stylebox_override("panel", skin.portrait_panel_style)
	speaker_plate.add_theme_stylebox_override("panel", skin.name_plate_style)
	text_interior.texture = skin.text_interior_texture
	text_interior.visible = skin.text_interior_texture != null
	empty_portrait_texture.texture = skin.empty_portrait_texture
	empty_portrait_texture.visible = skin.empty_portrait_texture != null
	continue_indicator_texture.texture = skin.continue_indicator_texture
	if skin.body_font != null:
		dialogue_text.add_theme_font_override("normal_font", skin.body_font)
	if skin.name_font != null:
		speaker_label.add_theme_font_override("font", skin.name_font)
	dialogue_text.add_theme_font_size_override("normal_font_size", skin.body_font_size)
	dialogue_text.add_theme_color_override("default_color", skin.body_color)
	speaker_label.add_theme_font_size_override("font_size", skin.name_font_size)
	speaker_label.add_theme_color_override("font_color", skin.name_color)
	choice_label.add_theme_font_size_override("font_size", skin.choice_font_size)
	choice_label.modulate = skin.choice_color
	var silhouette := empty_portrait.get_node("Silhouette") as Label
	silhouette.visible = skin.empty_portrait_texture == null
	silhouette.modulate = skin.empty_portrait_color
	silhouette.add_theme_font_size_override("font_size", 26)


func _layout_from_viewport() -> void:
	apply_window_size(Vector2i(get_viewport_rect().size))


func _layout_panel_contents() -> void:
	var portrait_padding := float(skin.portrait_inner_padding)
	portrait_texture.position = Vector2.ONE * portrait_padding
	portrait_texture.size = portrait_panel.size - Vector2.ONE * portrait_padding * 2.0
	empty_portrait.position = Vector2.ONE * portrait_padding
	empty_portrait.size = portrait_panel.size - Vector2.ONE * portrait_padding * 2.0
	empty_portrait_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(empty_portrait.get_node("Silhouette") as Label).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var padding := float(skin.panel_inner_padding)
	text_interior.position = Vector2.ONE * padding
	text_interior.size = dialogue_panel.size - Vector2.ONE * padding * 2.0
	dialogue_text.position = Vector2(padding, padding + 2.0)
	dialogue_text.size = Vector2(maxf(1.0, dialogue_panel.size.x - padding * 2.0), maxf(1.0, dialogue_panel.size.y - padding * 2.0 - 12.0))
	choice_label.position = Vector2(padding, dialogue_panel.size.y - padding - 9.0)
	choice_label.size = Vector2(maxf(1.0, dialogue_panel.size.x - padding * 2.0 - 12.0), 9.0)
	continue_indicator.position = Vector2(dialogue_panel.size.x - padding - 9.0, dialogue_panel.size.y - padding - 9.0)
	continue_indicator.size = Vector2(9, 9)
	continue_indicator_texture.position = continue_indicator.position
	continue_indicator_texture.size = continue_indicator.size

	speaker_plate.position = dialogue_panel.position + Vector2(skin.name_plate_horizontal_offset, -skin.name_plate_size.y)
	speaker_plate.size = Vector2(skin.name_plate_size)
	speaker_label.position = Vector2(5, 0)
	speaker_label.size = speaker_plate.size - Vector2(10, 0)
