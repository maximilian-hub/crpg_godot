extends Node2D

## Developer-only preview for character hand art, anchors, scale, and motion.
## It is intentionally absent from startup scenes and the shipping game flow.

const HAND_SCENE := preload("res://scenes/player_hand_rig.tscn")
const PIECE_SCENE := preload("res://scenes/piece.tscn")

var hand: ChessHandRig
var sample_piece: PieceView
var target_piece: PieceView
var styles: Array[ChessHandStyle] = []
var style_paths: Array[String] = []
var style_select: OptionButton
var seat_select: OptionButton
var pose_select: OptionButton
var action_select: OptionButton
var grip_x: SpinBox
var grip_y: SpinBox
var connection_x: SpinBox
var connection_y: SpinBox
var art_scale: SpinBox
var motion_fields: Dictionary = {}
var status: Label
var depth_status: Label
var grip_marker: Node2D
var connection_marker: Node2D
var stage_center := Vector2(780, 450)


func _ready() -> void:
	_build_stage()
	_build_ui()
	_discover_styles("res://assets/arms")
	_populate_styles()
	if not styles.is_empty():
		_load_style(0)


func _build_stage() -> void:
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(320, 120), Vector2(1240, 120), Vector2(1240, 780), Vector2(320, 780)])
	backdrop.color = Color("594b46")
	backdrop.z_index = -10
	add_child(backdrop)
	hand = HAND_SCENE.instantiate() as ChessHandRig
	add_child(hand)
	hand.depth_state_changed.connect(_on_depth_state_changed)
	hand.position = stage_center
	hand.visible = true
	sample_piece = _make_piece(Pawn.new("white", Vector2i.ZERO), stage_center + Vector2(-90, 100))
	target_piece = _make_piece(Queen.new("black", Vector2i.ZERO), stage_center + Vector2(150, 100))
	sample_piece.z_index = 40
	target_piece.z_index = 50
	grip_marker = _make_cross(Color.CYAN)
	connection_marker = _make_cross(Color.MAGENTA)
	add_child(grip_marker)
	add_child(connection_marker)


func _make_piece(model: ModelPiece, at: Vector2) -> PieceView:
	var piece := PIECE_SCENE.instantiate() as PieceView
	add_child(piece)
	piece.set_model(model)
	piece.position = at
	piece.scale = Vector2.ONE * 2.0
	return piece


func _make_cross(color: Color) -> Node2D:
	var marker := Node2D.new()
	for points in [PackedVector2Array([Vector2(-8, 0), Vector2(8, 0)]), PackedVector2Array([Vector2(0, -8), Vector2(0, 8)])]:
		var line := Line2D.new()
		line.points = points
		line.width = 2.0
		line.default_color = color
		marker.add_child(line)
	marker.z_index = 100
	return marker


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(290, 0)
	add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.text = "Chess Hand Lab"
	title.add_theme_font_size_override("font_size", 22)
	rows.add_child(title)
	style_select = _option_row(rows, "Style")
	style_select.item_selected.connect(_load_style)
	seat_select = _option_row(rows, "Seat")
	seat_select.add_item("Near")
	seat_select.add_item("Far")
	seat_select.item_selected.connect(_on_seat_changed)
	pose_select = _option_row(rows, "Pose")
	pose_select.add_item("Open")
	pose_select.add_item("Closed")
	pose_select.item_selected.connect(func(index: int): hand._apply_pose(index == 1); hand.visible = true)
	action_select = _option_row(rows, "Preview")
	for label in ["Approach + Slide", "Jump", "Capture", "Ranged Slam"]:
		action_select.add_item(label)
	var preview := Button.new()
	preview.text = "Play Preview"
	preview.pressed.connect(_play_preview)
	rows.add_child(preview)
	depth_status = Label.new()
	depth_status.text = "Depth: Elevated"
	rows.add_child(depth_status)
	grip_x = _number_row(rows, "Grip X", -512, 512, 1)
	grip_y = _number_row(rows, "Grip Y", -512, 512, 1)
	connection_x = _number_row(rows, "Connection X", -512, 512, 1)
	connection_y = _number_row(rows, "Connection Y", -512, 512, 1)
	art_scale = _number_row(rows, "Art Scale", 0.25, 8.0, 0.05)
	for control in [grip_x, grip_y, connection_x, connection_y, art_scale]:
		control.value_changed.connect(_on_geometry_changed)
	var motion_title := Label.new()
	motion_title.text = "Motion Profile"
	rows.add_child(motion_title)
	for property_name in ["approach_duration", "grasp_hold_duration", "carry_duration", "jump_arc_height", "jump_carry_duration", "capture_swipe_distance", "capture_swipe_duration", "attack_slam_duration", "attack_rebound_duration", "release_hold_duration", "retreat_duration"]:
		var maximum := 256.0 if property_name.ends_with("height") or property_name.ends_with("distance") else 5.0
		var step := 1.0 if maximum > 5.0 else 0.01
		var field := _number_row(rows, property_name.capitalize(), 0.0, maximum, step)
		field.value_changed.connect(_on_motion_changed.bind(property_name))
		motion_fields[property_name] = field
	var save := Button.new()
	save.text = "Save Style + Motion"
	save.pressed.connect(_save_current)
	rows.add_child(save)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(status)


func _option_row(parent: VBoxContainer, label_text: String) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	parent.add_child(option)
	return option


func _number_row(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.allow_greater = true
	number.allow_lesser = true
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(number)
	return number


func _discover_styles(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := directory.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			_discover_styles(path)
		elif entry.ends_with("_hand_style.tres"):
			var resource := load(path) as ChessHandStyle
			if resource != null:
				styles.append(resource)
				style_paths.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _populate_styles() -> void:
	style_select.clear()
	for path in style_paths:
		style_select.add_item(path.get_file().trim_suffix("_hand_style.tres").capitalize())


func _load_style(index: int) -> void:
	if index < 0 or index >= styles.size():
		return
	style_select.select(index)
	var style := styles[index]
	hand.set_hand_style(style)
	hand.scale = Vector2.ONE * style.art_scale_multiplier
	hand.position = stage_center
	hand.visible = true
	grip_x.set_value_no_signal(style.grip_anchor_pixels.x)
	grip_y.set_value_no_signal(style.grip_anchor_pixels.y)
	connection_x.set_value_no_signal(style.connection_anchor_pixels.x)
	connection_y.set_value_no_signal(style.connection_anchor_pixels.y)
	art_scale.set_value_no_signal(style.art_scale_multiplier)
	for property_name in motion_fields:
		motion_fields[property_name].set_value_no_signal(style.motion_profile.get(property_name))
	_update_markers()
	status.text = style.texture_size_warning()


func _on_geometry_changed(_value: float) -> void:
	if hand.hand_style == null:
		return
	hand.hand_style.grip_anchor_pixels = Vector2(grip_x.value, grip_y.value)
	hand.hand_style.connection_anchor_pixels = Vector2(connection_x.value, connection_y.value)
	hand.hand_style.art_scale_multiplier = art_scale.value
	hand.scale = Vector2.ONE * art_scale.value
	hand._apply_pose(pose_select.selected == 1)
	_update_markers()


func _on_seat_changed(index: int) -> void:
	hand.seat = ChessHandRig.Seat.FAR if index == 1 else ChessHandRig.Seat.NEAR
	hand.position = stage_center
	hand.visible = true


func _on_motion_changed(value: float, property_name: String) -> void:
	if hand.hand_style != null and hand.hand_style.motion_profile != null:
		hand.hand_style.motion_profile.set(property_name, value)
		hand.motion_override = null


func _on_depth_state_changed(state: ChessHandRig.DepthState, base_depth: int) -> void:
	if depth_status == null:
		return
	depth_status.text = "Depth: Elevated" if state == ChessHandRig.DepthState.ELEVATED else "Depth: Grounded (row %d)" % base_depth


func _update_markers() -> void:
	grip_marker.position = hand.position
	connection_marker.position = hand.position + hand.get_connection_anchor_position() * hand.scale


func _reset_samples() -> void:
	for piece in [sample_piece, target_piece]:
		if piece.get_parent() != self:
			piece.reparent(self, true)
	sample_piece.position = stage_center + Vector2(-90, 100)
	target_piece.position = stage_center + Vector2(150, 100)
	sample_piece.z_index = 40
	target_piece.z_index = 50
	sample_piece.visible = true
	target_piece.visible = true
	hand.visible = false
	hand.position = hand._offscreen_rest_position(hand.hand_style.art_scale_multiplier)


func _play_preview() -> void:
	if hand.is_animating or not hand.can_animate():
		return
	_reset_samples()
	match action_select.selected:
		0:
			await hand.play_piece_move(sample_piece, stage_center + Vector2(120, 100), 1.0)
		1:
			await hand.play_piece_move(sample_piece, stage_center + Vector2(120, 100), 1.0, ChessHandRig.CARRY_PATH_JUMP)
		2:
			await hand.play_piece_capture(sample_piece, target_piece, stage_center + Vector2(150, 100), 1.0)
		3:
			await hand.play_piece_attack(sample_piece, target_piece.position, 1.0)
	_reset_samples()
	_update_markers()


func _save_current() -> void:
	var index := style_select.selected
	if index < 0 or index >= styles.size():
		return
	var style := styles[index]
	var motion_error := OK
	if style.motion_profile != null and not style.motion_profile.resource_path.is_empty():
		motion_error = ResourceSaver.save(style.motion_profile, style.motion_profile.resource_path)
	var style_error := ResourceSaver.save(style, style_paths[index])
	status.text = "Saved %s" % style_paths[index] if style_error == OK and motion_error == OK else "Save failed: style=%s motion=%s" % [style_error, motion_error]
