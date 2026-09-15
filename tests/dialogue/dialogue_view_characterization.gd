extends Node

const DIALOGUE_VIEW_SCENE := preload("res://scenes/ui/dialogue_view.tscn")
const DialogueViewScript := preload("res://scripts/ui/dialogue_view.gd")
const DIALOGUE_SKIN := preload("res://assets/ui/dialogue/dialogue_skin_provisional.tres")
const HOOD_PORTRAIT := preload("res://assets/ui/portraits/hood_test_portrait.png")

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
	_check(hd.group_rect == Rect2i(8, 108, 304, 64), "bottom presentation observes logical margins and maximum width")
	_check(hd.portrait_rect.size == Vector2i(48, 64), "portrait panel follows the supplied portrait's 3:4 aspect ratio")
	_check(hd.text_rect.position.x == hd.portrait_rect.end.x - DIALOGUE_SKIN.panel_join_overlap, "text panel joins the portrait panel at one shared seam")
	_check(hd.text_rect.size.y == hd.portrait_rect.size.y, "portrait and text panels have equal height")
	var wide: Dictionary = DialogueViewScript.calculate_layout(Vector2i(2560, 1080), DialogueViewScript.Placement.CENTER)
	_check(wide.logical_size == Vector2i(426, 180), "ultrawide expands logical width without stretching UI pixels")
	_check(wide.group_rect.position == Vector2i(61, 58), "maximum-width center presentation is centered in ultrawide logical space")
	var narrow: Dictionary = DialogueViewScript.calculate_layout(Vector2i(900, 1080), DialogueViewScript.Placement.TOP)
	_check(narrow.logical_size == Vector2i(150, 180), "narrow window preserves the height-derived integer scale")
	_check(narrow.group_rect == Rect2i(8, 8, 134, 64), "narrow presentation contracts while preserving margins")
	var near: Dictionary = DialogueViewScript.calculate_layout(Vector2i(1920, 1080), DialogueViewScript.Placement.BATTLE_NEAR)
	var far: Dictionary = DialogueViewScript.calculate_layout(Vector2i(1920, 1080), DialogueViewScript.Placement.BATTLE_FAR)
	_check(near.group_rect.position.y > far.group_rect.position.y, "battle-near and battle-far map to opposing vertical placements")
	_check(DIALOGUE_SKIN.text_panel_style != null and DIALOGUE_SKIN.portrait_panel_style != null and DIALOGUE_SKIN.name_plate_style != null, "skin supplies independently replaceable panel and plaque styles")
	_check(DIALOGUE_SKIN.portrait_aspect_ratio == float(HOOD_PORTRAIT.get_width()) / float(HOOD_PORTRAIT.get_height()), "skin aspect ratio matches the supplied portrait asset")


func _test_static_states() -> void:
	var view = DIALOGUE_VIEW_SCENE.instantiate()
	add_child(view)
	view.apply_window_size(Vector2i(1920, 1080))
	view.configure("Hood", true, "Left aligned sample.")
	_check(view.portrait_panel.visible, "portrait panel remains visible without portrait art")
	_check(view.empty_portrait.visible and not view.portrait_texture.visible, "missing portrait uses an intentional empty state")
	_check(view.speaker_label.text == "Hood", "known speaker displays authored name")
	_check(view.portrait_panel.get_parent() == view.dialogue_panel.get_parent(), "portrait and text panels are siblings rather than nested boxes")
	_check(view.portrait_panel.size.y == view.dialogue_panel.size.y, "live portrait and text panels have equal height")
	_check(view.dialogue_panel.position.x <= view.portrait_panel.position.x + view.portrait_panel.size.x, "live panels meet at a connected seam")
	_check(view.speaker_plate.position.y < view.dialogue_panel.position.y, "speaker plate sits on top of the text panel")
	_check(view.speaker_plate.position.x >= view.dialogue_panel.position.x, "speaker plate is anchored to the text panel rather than the portrait")
	_check(view.dialogue_text.text_direction == Control.TEXT_DIRECTION_AUTO, "dialogue text retains normal left-to-right auto direction")
	view.configure("Hood", true, "Portrait sample.", HOOD_PORTRAIT)
	_check(view.portrait_texture.visible and not view.empty_portrait.visible, "supplied hood portrait replaces the empty state")
	view.configure("Hood", false, "Unknown speaker.")
	_check(view.speaker_label.text == "???", "unidentified speaker displays question marks")
	view.configure("", true, "Off-screen speaker.", null, PackedStringArray(["▶ Listen", "  Leave"]))
	_check(view.speaker_label.text == "???", "empty speaker name safely falls back to question marks")
	_check(view.choice_label.visible and not view.continue_indicator.visible, "choice state replaces the continue indicator")
	view.queue_free()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
