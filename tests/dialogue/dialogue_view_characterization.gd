extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueViewScript := preload("res://scripts/ui/dialogue_view.gd")
const DIALOGUE_SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")
const HOOD_PORTRAIT := preload("res://assets/ui/portraits/hood/hood_neutral.png")
const PIXEL_OPERATOR_8 := preload("res://assets/ui/fonts/pixel_operator/PixelOperator8.ttf")
const PIXEL_OPERATOR_8_BOLD := preload("res://assets/ui/fonts/pixel_operator/PixelOperator8-Bold.ttf")
const TextSpanScript := preload("res://scripts/dialogue/dialogue_text_span.gd")
const JiggleEffectScript := preload("res://scripts/ui/dialogue_jiggle_effect.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_layout_calculation()
	_test_static_states()
	if failures.is_empty():
		print("DIALOGUE VIEW CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE VIEW FAILURE: ", failure)
		get_tree().quit(1)


func _test_layout_calculation() -> void:
	var hd: Dictionary = DialogueViewScript.calculate_layout(Vector2i(1920, 1080), DialogueViewScript.Placement.BOTTOM)
	_check(hd.ui_scale == 6, "1080p selects a uniform 6x UI scale")
	_check(hd.logical_size == Vector2i(320, 180), "1080p resolves to the 320x180 reference grid")
	_check(hd.group_rect == Rect2i(8, 94, 304, 78), "bottom presentation includes the plaque above the text panel within its margins")
	_check(hd.portrait_rect.size == Vector2i(59, 78), "portrait panel grows upward at the supplied portrait's 3:4 aspect ratio")
	_check(hd.text_rect.position.x == hd.portrait_rect.end.x - DIALOGUE_SKIN.panel_join_overlap, "text panel joins the portrait panel at one shared seam")
	_check(hd.portrait_rect.end.y == hd.text_rect.end.y, "portrait and text panels retain a shared bottom edge")
	_check(hd.portrait_rect.position.y == hd.text_rect.position.y - DIALOGUE_SKIN.name_plate_size.y, "portrait top aligns with the top of the plaque row")
	var wide: Dictionary = DialogueViewScript.calculate_layout(Vector2i(2560, 1080), DialogueViewScript.Placement.CENTER)
	_check(wide.logical_size == Vector2i(426, 180), "ultrawide expands logical width without stretching UI pixels")
	_check(wide.group_rect.position == Vector2i(61, 51), "maximum-width center presentation is centered in ultrawide logical space")
	var narrow: Dictionary = DialogueViewScript.calculate_layout(Vector2i(900, 1080), DialogueViewScript.Placement.TOP)
	_check(narrow.logical_size == Vector2i(150, 180), "narrow window preserves the height-derived integer scale")
	_check(narrow.group_rect == Rect2i(8, 8, 134, 78), "narrow presentation contracts while preserving margins")
	var near: Dictionary = DialogueViewScript.calculate_layout(Vector2i(1920, 1080), DialogueViewScript.Placement.BATTLE_NEAR)
	var far: Dictionary = DialogueViewScript.calculate_layout(Vector2i(1920, 1080), DialogueViewScript.Placement.BATTLE_FAR)
	_check(near.group_rect.position.y > far.group_rect.position.y, "battle-near and battle-far map to opposing vertical placements")
	_check(DIALOGUE_SKIN.text_panel_style != null and DIALOGUE_SKIN.portrait_panel_style != null and DIALOGUE_SKIN.name_plate_style != null, "skin supplies independently replaceable panel and plaque styles")
	_check(DIALOGUE_SKIN.portrait_aspect_ratio == float(HOOD_PORTRAIT.get_width()) / float(HOOD_PORTRAIT.get_height()), "skin aspect ratio matches the supplied portrait asset")
	_check(DIALOGUE_SKIN.empty_portrait_texture != null and DIALOGUE_SKIN.empty_portrait_texture.get_size() == Vector2(96, 128), "skin supplies the correctly sized empty portrait asset")


func _test_static_states() -> void:
	var view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(view)
	view.apply_window_size(Vector2i(1920, 1080))
	_check(view.content_stage.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "dialogue stage enforces nearest filtering independently of its host viewport")
	_check(PIXEL_OPERATOR_8.antialiasing == 0, "Pixel Operator 8 disables grayscale antialiasing")
	_check(PIXEL_OPERATOR_8.subpixel_positioning == 0, "Pixel Operator 8 disables subpixel positioning")
	_check(is_equal_approx(PIXEL_OPERATOR_8.oversampling, 1.0), "Pixel Operator 8 fixes font oversampling at native 1x")
	var font_skin = DIALOGUE_SKIN.duplicate(true)
	font_skin.body_font = PIXEL_OPERATOR_8
	font_skin.name_font = PIXEL_OPERATOR_8_BOLD
	view.set_skin(font_skin)
	_check(view.dialogue_text.get_theme_font("normal_font") == PIXEL_OPERATOR_8 and view.speaker_label.get_theme_font("font") == PIXEL_OPERATOR_8_BOLD, "DialogueSkin independently applies body and plaque font candidates")
	_check(font_skin.has_semantic_color("warning") and font_skin.semantic_color("warning") != font_skin.body_color, "DialogueSkin resolves named semantic colors independently of authored text")
	_check(font_skin.has_semantic_size("large") and font_skin.semantic_size("large") > font_skin.semantic_size("normal"), "DialogueSkin resolves semantic sizes independently of authored text")
	_check(font_skin.has_semantic_jiggle("strong") and font_skin.semantic_jiggle("strong").amplitude > font_skin.semantic_jiggle("standard").amplitude, "DialogueSkin resolves named jiggle motion independently of authored text")
	var color_spans: Array = [TextSpanScript.new(TextSpanScript.Kind.COLOR, 1, 3, "warning")]
	view.configure("Hood", true, "A[B]", null, PackedStringArray(), color_spans)
	_check(view.dialogue_text.get_total_character_count() == 4, "structured rich text retains one rendered character per visible source character")
	_check(view.dialogue_text.get_parsed_text() == "A[B]", "structured rich text preserves literal bracket characters without interpreting authored text as markup")
	var wrapping_text := "Mixed size words wrap across the dialogue panel cleanly."
	view.configure("Hood", true, wrapping_text)
	var normal_content_size: Vector2i = view.text_content_size()
	var large_spans: Array = [TextSpanScript.new(TextSpanScript.Kind.FONT_SIZE, 0, wrapping_text.length(), "large")]
	view.configure("Hood", true, wrapping_text, null, PackedStringArray(), large_spans)
	var large_content_size: Vector2i = view.text_content_size()
	_check(large_content_size.y > normal_content_size.y, "semantic large text participates in shaping and increases wrapped layout height")
	var laid_out_height := large_content_size.y
	view.dialogue_text.visible_characters = 0
	_check(view.text_content_size().y == laid_out_height, "mixed-size layout is complete before progressive reveal begins")
	var overflowing_text := "overflow ".repeat(80)
	var overflowing_spans: Array = [TextSpanScript.new(TextSpanScript.Kind.FONT_SIZE, 0, overflowing_text.length(), "large")]
	view.configure("Hood", true, overflowing_text, null, PackedStringArray(), overflowing_spans)
	_check(view.text_overflows(), "fully shaped content reports overflow without shrinking or automatic pagination")
	_check(view.dialogue_text.get_theme_font_size("normal_font_size") == font_skin.body_font_size, "overflow detection leaves the configured base font size unchanged")
	var motion_text := "Motion leaves layout alone."
	view.configure("Hood", true, motion_text)
	var static_motion_size: Vector2i = view.text_content_size()
	var jiggle_spans: Array = [TextSpanScript.new(TextSpanScript.Kind.JIGGLE, 0, motion_text.length(), "strong")]
	view.configure("Hood", true, motion_text, null, PackedStringArray(), jiggle_spans)
	_check(view.text_content_size() == static_motion_size, "jiggle draw offsets do not affect shaping, wrapping, or overflow measurements")
	view.set_visible_character_count(0)
	_check(view.jiggle_effect.revealed_at.is_empty(), "hidden jiggle characters have no animation start time")
	view.set_visible_character_count(1)
	_check(view.jiggle_effect.revealed_at.has(0) and not view.jiggle_effect.revealed_at.has(1), "jiggle animation begins only when each indexed character is revealed")
	var effect = JiggleEffectScript.new()
	effect.reveal_through(1)
	effect.advance(0.125)
	var deterministic_offset: Vector2 = effect.offset_for(0, 2.0, 7.0)
	var repeated_effect = JiggleEffectScript.new()
	repeated_effect.reveal_through(1)
	repeated_effect.advance(0.125)
	_check(repeated_effect.offset_for(0, 2.0, 7.0) == deterministic_offset, "jiggle offset is deterministic for matching character index and elapsed reveal time")
	_check(deterministic_offset.x == roundf(deterministic_offset.x) and deterministic_offset.y == roundf(deterministic_offset.y), "jiggle offsets snap to whole logical pixels")
	_check(effect.offset_for(1, 2.0, 7.0) == Vector2.ZERO, "unrevealed characters remain motionless")
	effect.reduced_motion = true
	_check(effect.offset_for(0, 2.0, 7.0) == Vector2.ZERO, "reduced motion renders authored jiggle spans statically")
	effect.reduced_motion = false
	effect.animation_enabled = false
	_check(effect.offset_for(0, 2.0, 7.0) == Vector2.ZERO, "global animated-text control disables authored motion")
	view.configure("Hood", true, "Left aligned sample.")
	_check(view.portrait_panel.visible, "portrait panel remains visible without portrait art")
	_check(view.empty_portrait.visible and not view.portrait_texture.visible, "missing portrait uses an intentional empty state")
	_check(view.speaker_label.text == "Hood", "known speaker displays authored name")
	_check(view.portrait_panel.get_parent() == view.dialogue_panel.get_parent(), "portrait and text panels are siblings rather than nested boxes")
	_check(view.portrait_panel.position.y == view.speaker_plate.position.y, "live portrait top aligns with the name plaque top (%s vs %s)" % [view.portrait_panel.position.y, view.speaker_plate.position.y])
	_check(view.portrait_panel.position.y + view.portrait_panel.size.y == view.dialogue_panel.position.y + view.dialogue_panel.size.y, "live portrait and text panels share a bottom edge")
	_check(view.dialogue_panel.position.x <= view.portrait_panel.position.x + view.portrait_panel.size.x, "live panels meet at a connected seam")
	_check(view.speaker_plate.position.y + view.speaker_plate.size.y == view.dialogue_panel.position.y, "speaker plate sits directly atop the text panel without overlap (%s + %s vs %s)" % [view.speaker_plate.position.y, view.speaker_plate.size.y, view.dialogue_panel.position.y])
	_check(view.speaker_plate.position.x >= view.dialogue_panel.position.x, "speaker plate is anchored to the text panel rather than the portrait")
	_check(view.dialogue_text.text_direction == Control.TEXT_DIRECTION_AUTO, "dialogue text retains normal left-to-right auto direction")
	view.configure("Hood", true, "Portrait sample.", HOOD_PORTRAIT)
	_check(view.portrait_texture.visible and not view.empty_portrait.visible, "supplied hood portrait replaces the empty state")
	view.configure("Hood", false, "Unknown speaker.")
	_check(view.speaker_label.text == "???", "unidentified speaker displays question marks")
	view.configure("", true, "Off-screen speaker.", null, PackedStringArray(["▶ Listen", "  Leave"]))
	_check(view.speaker_label.text == "???", "empty speaker name safely falls back to question marks")
	_check(view.choice_label.visible and not view.continue_indicator.visible, "choice state replaces the continue indicator")
	view.set_page_complete(false)
	_check(not view.choice_label.visible and not view.continue_indicator.visible and not view.continue_indicator_texture.visible, "incomplete reveal hides choices and all continue indicators")
	view.set_page_complete(true)
	_check(view.choice_label.visible, "completion restores the configured choice presentation")
	view.queue_free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
