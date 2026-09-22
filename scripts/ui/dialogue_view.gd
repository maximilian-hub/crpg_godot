extends Control
class_name DialogueView

enum Placement { BOTTOM, TOP, CENTER, BATTLE_NEAR, BATTLE_FAR }

const REFERENCE_HEIGHT := 180
const MAX_PRESENTATION_WIDTH := 304
const OUTER_MARGIN := 8
const DEFAULT_SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")
const TextSpanScript := preload("res://scripts/dialogue/dialogue_text_span.gd")
const JiggleEffectScript := preload("res://scripts/ui/dialogue_jiggle_effect.gd")

@export var skin: Resource = DEFAULT_SKIN

var placement := Placement.BOTTOM
var content_stage: Control
var complete_frame: TextureRect
var dialogue_panel: Panel
var portrait_panel: Panel
var portrait_texture: TextureRect
var empty_portrait: Control
var empty_portrait_texture: TextureRect
var portrait_shadow
var speaker_plate: Panel
var speaker_label: Label
var dialogue_text: RichTextLabel
var text_interior: TextureRect
var choice_label: Label
var continue_indicator: Label
var continue_indicator_texture: TextureRect
var page_has_choices := false
var page_is_complete := true
var choice_texts := PackedStringArray()
var selected_choice_index := -1
var presented_text := ""
var presented_spans: Array = []
var construction_preview := false
var jiggle_effect
var transparent_panel_style := StyleBoxEmpty.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_view()
	_apply_skin()
	get_viewport().size_changed.connect(_layout_from_viewport)
	_layout_from_viewport()


func _process(delta: float) -> void:
	if jiggle_effect != null:
		jiggle_effect.advance(delta)


func configure(speaker: String, identified: bool, text: String, portrait: Texture2D = null, choices: PackedStringArray = PackedStringArray(), presentation_spans: Array = []) -> void:
	_ensure_built()
	speaker_label.text = speaker if identified and not speaker.is_empty() else "???"
	presented_text = text
	presented_spans = presentation_spans.duplicate()
	jiggle_effect.reset()
	_set_presented_text(text, presentation_spans)
	dialogue_text.visible_characters = -1
	jiggle_effect.reveal_through(text.length())
	set_portrait(portrait)
	choice_texts = choices.duplicate()
	page_has_choices = not choices.is_empty()
	selected_choice_index = 0 if page_has_choices else -1
	_render_choices()
	set_page_complete(true)


func _set_presented_text(text: String, presentation_spans: Array) -> void:
	dialogue_text.clear()
	var active_spans: Array = []
	for span in presentation_spans:
		if span.kind in [TextSpanScript.Kind.COLOR, TextSpanScript.Kind.FONT_SIZE, TextSpanScript.Kind.JIGGLE] and span.start_index < span.end_index:
			active_spans.append(span)
	active_spans.sort_custom(func(a, b):
		return a.start_index < b.start_index if a.start_index != b.start_index else a.end_index > b.end_index
	)
	for index in range(text.length()):
		var color_name := ""
		var size_name := ""
		var jiggle_name := ""
		for span in active_spans:
			if span.start_index <= index and index < span.end_index:
				if span.kind == TextSpanScript.Kind.COLOR:
					color_name = span.value
				elif span.kind == TextSpanScript.Kind.FONT_SIZE:
					size_name = span.value
				elif span.kind == TextSpanScript.Kind.JIGGLE:
					jiggle_name = span.value
		var pushed := 0
		if not color_name.is_empty():
			dialogue_text.push_color(skin.semantic_color(color_name))
			pushed += 1
		if not size_name.is_empty():
			dialogue_text.push_font_size(skin.semantic_size(size_name))
			pushed += 1
		if not jiggle_name.is_empty():
			dialogue_text.push_customfx(jiggle_effect, skin.semantic_jiggle(jiggle_name))
			pushed += 1
		dialogue_text.add_text(text[index])
		for _pop in range(pushed):
			dialogue_text.pop()


func text_overflows() -> bool:
	return dialogue_text.get_content_height() > ceili(dialogue_text.size.y) or dialogue_text.get_content_width() > ceili(dialogue_text.size.x)


func text_content_size() -> Vector2i:
	return Vector2i(dialogue_text.get_content_width(), dialogue_text.get_content_height())


func set_visible_character_count(count: int) -> void:
	var clamped_count := clampi(count, 0, presented_text.length())
	var previous_count := presented_text.length() if dialogue_text.visible_characters < 0 else dialogue_text.visible_characters
	if clamped_count < previous_count:
		jiggle_effect.reset()
	dialogue_text.visible_characters = clamped_count
	jiggle_effect.reveal_through(clamped_count)


func set_animated_text_enabled(enabled: bool) -> void:
	jiggle_effect.animation_enabled = enabled


func set_reduced_motion(enabled: bool) -> void:
	jiggle_effect.reduced_motion = enabled


func set_page_complete(value: bool) -> void:
	page_is_complete = value
	_apply_content_visibility()


func set_portrait(texture: Texture2D) -> void:
	portrait_texture.texture = texture
	_apply_content_visibility()


func set_construction_preview(enabled: bool) -> void:
	construction_preview = enabled
	_apply_content_visibility()


func set_selected_choice(index: int) -> void:
	selected_choice_index = clampi(index, 0, choice_texts.size() - 1) if not choice_texts.is_empty() else -1
	_render_choices()


func _render_choices() -> void:
	var rendered := PackedStringArray()
	for index in range(choice_texts.size()):
		var cursor: String = skin.choice_cursor if index == selected_choice_index else " ".repeat(skin.choice_cursor.length())
		rendered.append("%s %s" % [cursor, choice_texts[index]])
	choice_label.text = "   ".join(rendered)


func set_skin(value: Resource) -> void:
	var visible_count := dialogue_text.visible_characters if dialogue_text != null else -1
	skin = value if value != null else DEFAULT_SKIN
	_ensure_built()
	_apply_skin()
	_set_presented_text(presented_text, presented_spans)
	_render_choices()
	dialogue_text.visible_characters = visible_count
	set_page_complete(page_is_complete)
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
	complete_frame.position = layout.group_rect.position
	complete_frame.size = layout.group_rect.size
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
	content_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(content_stage)
	complete_frame = TextureRect.new()
	complete_frame.name = "CompleteFrame"
	complete_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	complete_frame.stretch_mode = TextureRect.STRETCH_SCALE
	complete_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	complete_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_stage.add_child(complete_frame)

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
	portrait_shadow = preload("res://scripts/ui/dialogue_portrait_shadow.gd").new()
	portrait_shadow.name = "PortraitInsetShadow"
	portrait_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.add_child(portrait_shadow)

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
	dialogue_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jiggle_effect = JiggleEffectScript.new()
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
	var uses_complete_frame: bool = skin.complete_frame_texture != null
	complete_frame.texture = skin.complete_frame_texture
	complete_frame.visible = uses_complete_frame
	dialogue_panel.add_theme_stylebox_override("panel", transparent_panel_style if uses_complete_frame else skin.text_panel_style)
	portrait_panel.add_theme_stylebox_override("panel", transparent_panel_style if uses_complete_frame else skin.portrait_panel_style)
	speaker_plate.add_theme_stylebox_override("panel", transparent_panel_style if uses_complete_frame else skin.name_plate_style)
	text_interior.texture = skin.text_interior_texture
	text_interior.visible = skin.text_interior_texture != null
	empty_portrait_texture.texture = skin.empty_portrait_texture
	empty_portrait_texture.visible = skin.empty_portrait_texture != null
	continue_indicator_texture.texture = skin.continue_indicator_texture
	if skin.body_font != null:
		dialogue_text.add_theme_font_override("normal_font", skin.body_font)
	else:
		dialogue_text.remove_theme_font_override("normal_font")
	if skin.name_font != null:
		speaker_label.add_theme_font_override("font", skin.name_font)
	else:
		speaker_label.remove_theme_font_override("font")
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
	portrait_shadow.configure(
		skin.portrait_shadow_enabled,
		skin.portrait_shadow_opening_insets if skin.portrait_shadow_opening_insets != Vector4.ZERO else skin.portrait_content_insets,
		skin.portrait_shadow_edge_thickness,
		skin.portrait_shadow_edge_opacity,
		skin.portrait_shadow_color,
		skin.portrait_shadow_frame_overlap,
		skin.portrait_shadow_bottom_offset
	)
	_apply_content_visibility()


func _apply_content_visibility() -> void:
	if dialogue_text == null:
		return
	var show_content := not construction_preview
	speaker_label.visible = show_content
	dialogue_text.visible = show_content
	text_interior.visible = show_content and skin.text_interior_texture != null
	portrait_texture.visible = show_content and portrait_texture.texture != null
	empty_portrait.visible = show_content and portrait_texture.texture == null
	choice_label.visible = show_content and page_is_complete and page_has_choices
	continue_indicator.visible = show_content and page_is_complete and not page_has_choices and skin.continue_indicator_texture == null
	continue_indicator_texture.visible = show_content and page_is_complete and not page_has_choices and skin.continue_indicator_texture != null


func _layout_from_viewport() -> void:
	apply_window_size(Vector2i(get_viewport_rect().size))


func _layout_panel_contents() -> void:
	var portrait_padding := float(skin.portrait_inner_padding)
	var portrait_insets: Vector4 = skin.portrait_content_insets
	if portrait_insets == Vector4.ZERO:
		portrait_insets = Vector4(portrait_padding, portrait_padding, portrait_padding, portrait_padding)
	var portrait_content_position := Vector2(portrait_insets.x, portrait_insets.y)
	var portrait_content_size := Vector2(
		maxf(1.0, portrait_panel.size.x - portrait_insets.x - portrait_insets.z),
		maxf(1.0, portrait_panel.size.y - portrait_insets.y - portrait_insets.w)
	)
	portrait_texture.position = portrait_content_position
	portrait_texture.size = portrait_content_size
	empty_portrait.position = portrait_content_position
	empty_portrait.size = portrait_content_size
	portrait_shadow.position = Vector2.ZERO
	portrait_shadow.size = portrait_panel.size
	empty_portrait_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(empty_portrait.get_node("Silhouette") as Label).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var padding := float(skin.panel_inner_padding)
	var text_insets: Vector4 = skin.text_content_insets
	if text_insets == Vector4.ZERO:
		text_insets = Vector4(padding, padding + 2.0, padding, padding)
	var text_left := text_insets.x
	var text_top := text_insets.y
	var text_right := text_insets.z
	var text_bottom := text_insets.w
	text_interior.position = Vector2(text_left, text_top)
	text_interior.size = Vector2(
		maxf(1.0, dialogue_panel.size.x - text_left - text_right),
		maxf(1.0, dialogue_panel.size.y - text_top - text_bottom)
	)
	dialogue_text.position = Vector2(text_left, text_top) + skin.body_text_offset
	dialogue_text.size = Vector2(
		maxf(1.0, dialogue_panel.size.x - text_left - text_right - skin.body_text_offset.x),
		maxf(1.0, dialogue_panel.size.y - text_top - text_bottom - float(skin.body_text_bottom_reserve) - skin.body_text_offset.y)
	)
	choice_label.position = Vector2(text_left, dialogue_panel.size.y - text_bottom - 9.0)
	choice_label.size = Vector2(maxf(1.0, dialogue_panel.size.x - text_left - text_right - 12.0), 9.0)
	continue_indicator.position = Vector2(dialogue_panel.size.x - text_right - 9.0, dialogue_panel.size.y - text_bottom - 9.0)
	continue_indicator.size = Vector2(9, 9)
	continue_indicator_texture.position = continue_indicator.position
	continue_indicator_texture.size = continue_indicator.size

	speaker_plate.position = dialogue_panel.position + Vector2(skin.name_plate_horizontal_offset, -skin.name_plate_size.y)
	speaker_plate.size = Vector2(skin.name_plate_size)
	speaker_label.position = skin.name_text_offset
	speaker_label.size = speaker_plate.size - skin.name_text_offset - Vector2(5, 0)
