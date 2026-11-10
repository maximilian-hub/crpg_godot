extends PanelContainer
class_name ChessMatchInsightsPanel

const PANEL_WIDTH := 260.0
const MINIMUM_SIDE_SPACE := 190.0
const EDGE_MARGIN := 22.0
const BOARD_GAP := 18.0

@export var model: ChessBoardModel
@export var board_view: ChessBoardView
@export var show_on_android := true
@export var show_on_desktop := true

var tracker: ChessMatchInsights
var value_labels: Dictionary = {}
var content: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 55
	_build_style()
	_build_content()
	tracker = ChessMatchInsights.new()
	tracker.name = "Tracker"
	add_child(tracker)
	tracker.changed.connect(_on_insights_changed)
	tracker.configure(model)
	if not get_viewport().size_changed.is_connected(_layout_panel):
		get_viewport().size_changed.connect(_layout_panel)
	call_deferred(&"_layout_panel")


func _build_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.047, 0.07, 0.94)
	panel_style.border_color = Color(0.67, 0.53, 0.28, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.62)
	panel_style.shadow_size = 10
	add_theme_stylebox_override("panel", panel_style)


func _build_content() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var title := Label.new()
	title.text = "MATCH INSIGHTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.81, 0.43))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	content.add_child(title)
	_add_separator()

	_add_metric("material", "MATERIAL ADVANTAGE")
	_add_metric("center", "CENTER CONTROL")
	_add_metric("abilities", "KING ABILITY USES")
	_add_metric("danger", "CHECK / CHECKMATES")
	_add_metric("unused", "READY TURNS UNUSED", false)


func _add_metric(key: String, heading: String, separator := true) -> void:
	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_label.add_theme_font_size_override("font_size", 12)
	heading_label.add_theme_color_override("font_color", Color(0.78, 0.65, 0.40))
	content.add_child(heading_label)

	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", Color(0.94, 0.91, 0.84))
	value.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	value.add_theme_constant_override("shadow_offset_x", 1)
	value.add_theme_constant_override("shadow_offset_y", 1)
	content.add_child(value)
	value_labels[key] = value
	if separator:
		_add_separator()


func _add_separator() -> void:
	var separator := HSeparator.new()
	separator.modulate = Color(0.72, 0.58, 0.31, 0.45)
	content.add_child(separator)


func _on_insights_changed(snapshot: Dictionary) -> void:
	var material: Dictionary = snapshot.get("material", {})
	var material_leader := ChessMatchInsights.leading_color(material)
	if material_leader.is_empty():
		value_labels.material.text = "Even · %d each" % int(material.get("white", 0))
	else:
		var other := "black" if material_leader == "white" else "white"
		var advantage := int(material.get(material_leader, 0)) - int(material.get(other, 0))
		value_labels.material.text = "+%d %s leading" % [advantage, material_leader.capitalize()]

	var center: Dictionary = snapshot.get("center", {})
	var center_owner := String(snapshot.get("center_controller", ""))
	var center_line := "Contested"
	if not center_owner.is_empty():
		var streak := int(snapshot.get("center_control_streak", 0))
		center_line = "%s controls · %d turn%s" % [center_owner.capitalize(), streak, "" if streak == 1 else "s"]
	value_labels.center.text = "%s\nWhite %d · Black %d" % [center_line, int(center.get("white", 0)), int(center.get("black", 0))]

	var uses: Dictionary = snapshot.get("ability_uses", {})
	value_labels.abilities.text = "White %d  ·  Black %d" % [int(uses.get("white", 0)), int(uses.get("black", 0))]

	var checks: Dictionary = snapshot.get("checks_received", {})
	var mates: Dictionary = snapshot.get("mate_threats_received", {})
	var current_check: Dictionary = snapshot.get("in_check", {})
	var current_mate: Dictionary = snapshot.get("in_checkmate", {})
	var current_status := _current_danger_status(current_check, current_mate)
	value_labels.danger.text = "White %d / %d  ·  Black %d / %d%s" % [
		int(checks.get("white", 0)), int(mates.get("white", 0)),
		int(checks.get("black", 0)), int(mates.get("black", 0)),
		current_status,
	]

	var unused: Dictionary = snapshot.get("ready_turns_unused", {})
	value_labels.unused.text = "White %d  ·  Black %d" % [int(unused.get("white", 0)), int(unused.get("black", 0))]
	call_deferred(&"_layout_panel")


func _current_danger_status(in_check: Dictionary, in_mate: Dictionary) -> String:
	for color in ["white", "black"]:
		if bool(in_mate.get(color, false)):
			return "\n%s: CHECKMATE" % color.capitalize()
		if bool(in_check.get(color, false)):
			return "\n%s: CHECK" % color.capitalize()
	return ""


func _layout_panel() -> void:
	if not is_enabled_for_platform(OS.has_feature("android")):
		visible = false
		return
	if board_view == null or board_view.projection.corners.is_empty():
		visible = false
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var outline := board_view.projection.get_board_outline()
	var minimum := outline[0]
	for point in outline:
		minimum = minimum.min(point)
	var available_width := minimum.x - EDGE_MARGIN - BOARD_GAP
	var is_android := OS.has_feature("android")
	visible = is_android or available_width >= MINIMUM_SIDE_SPACE
	var panel_width := minf(PANEL_WIDTH, viewport_size.x - EDGE_MARGIN * 2.0)
	if not is_android:
		panel_width = minf(panel_width, available_width)
	custom_minimum_size = Vector2(panel_width, 0.0)
	reset_size()
	position = Vector2(
		EDGE_MARGIN,
		floorf(viewport_size.y - size.y - EDGE_MARGIN)
	)


func is_enabled_for_platform(is_android: bool) -> bool:
	return show_on_android if is_android else show_on_desktop
