extends Node2D

const GAME_SCENE := preload("res://scenes/chess_game.tscn")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const PresentationPolicy := preload("res://scripts/view/chess_presentation_policy.gd")
const CENTER := Vector2i(4, 4)

var game: ChessGame
var model: ChessBoardModel
var board: ChessBoardView
var adapter: ChessPresentationAdapter
var profile: ChessMagicalMoveProfile
var selected_destination := Vector2i(4, 5)
var capture_mode := false
var playing := false
var status_label: Label
var destination_label: Label
var play_button: Button
var playback_speed_selector: OptionButton
var path_preview_toggle: CheckButton
var knockoff_path_preview_toggle: CheckButton
var property_controls: Dictionary = {}
var approach_path: Line2D
var swipe_path: Line2D
var retreat_path: Line2D
var knockoff_path: Line2D


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	profile = _load_runtime_profile()
	_build_game_stage()
	_build_controls()
	await get_tree().process_frame
	_rebuild_fixture()


func _build_game_stage() -> void:
	game = GAME_SCENE.instantiate() as ChessGame
	game.play_opening_presentation = false
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	add_child(game)
	model = game.model
	board = game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	adapter = game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	game.get_node("UI").visible = false
	game.get_node("CanvasLayer/ResultOverlay").visible = false
	game.controller.is_input_locked = true
	board.square_selected.connect(_on_square_selected)
	approach_path = _make_path_line(Color("48c6d9"))
	swipe_path = _make_path_line(Color("f4d35e"))
	retreat_path = _make_path_line(Color("e9894a"))
	knockoff_path = _make_path_line(Color("e75aa7"))
	get_viewport().size_changed.connect(_refresh_hand_path)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 500
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 700)
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 355
	controls.add_theme_constant_override("separation", 5)
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "King Movement Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	var instructions := Label.new()
	instructions.text = "Click any square adjacent to the King to choose a direction. The selection remains after playback."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(instructions)
	var king_selector := _option(controls, "King", [])
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"king"):
		king_selector.add_item(ChessPieceCatalog.get_definition(type_id).get("name", str(type_id)))
		king_selector.set_item_metadata(king_selector.item_count - 1, type_id)
	king_selector.item_selected.connect(func(_index): _rebuild_fixture())
	king_selector.name = "KingSelector"
	var mode := _option(controls, "Preview", ["Move", "Capture"])
	mode.item_selected.connect(func(index: int):
		capture_mode = index == 1
		_rebuild_fixture())
	playback_speed_selector = _option(controls, "Playback speed", ["Normal", "Slow", "Ultra Slow"])
	playback_speed_selector.item_selected.connect(_set_playback_speed)
	path_preview_toggle = CheckButton.new()
	path_preview_toggle.text = "Show hand path preview"
	path_preview_toggle.button_pressed = true
	path_preview_toggle.toggled.connect(_set_path_preview_visible)
	controls.add_child(path_preview_toggle)
	knockoff_path_preview_toggle = CheckButton.new()
	knockoff_path_preview_toggle.text = "Show knockoff path preview"
	knockoff_path_preview_toggle.button_pressed = true
	knockoff_path_preview_toggle.toggled.connect(_set_knockoff_path_preview_visible)
	controls.add_child(knockoff_path_preview_toggle)
	_add_vector_controls(controls, &"hand_hover_offset", "Hover offset")
	_spin(controls, &"gesture_sweep_distance", "Straight swipe length", 0, 300, 1)
	_spin(controls, &"gesture_lock_duration", "Lock pause", 0, 1, 0.01)
	_spin(controls, &"hand_approach_duration", "Hand approach", 0.01, 2, 0.01)
	_spin(controls, &"gesture_duration", "Gesture duration", 0.02, 3, 0.01)
	_spin(controls, &"king_move_delay", "King move delay", 0, 3, 0.01)
	_spin(controls, &"gesture_launch_speed", "Launch speed weight", 0.05, 8, 0.05)
	_spin(controls, &"gesture_turn_speed", "Turn speed weight", 0.05, 8, 0.05)
	_spin(controls, &"gesture_exit_speed", "Exit speed weight", 0.05, 8, 0.05)
	_spin(controls, &"gesture_minimum_turn_radius", "Minimum turn radius", 1, 600, 1)
	var speed_hint := Label.new()
	speed_hint.text = "Speed weights are relative; Turn is always clamped to the slowest point."
	speed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(speed_hint)
	_spin(controls, &"settle_duration", "Settle time", 0, 1, 0.01)
	_spin(controls, &"travel_duration", "King travel time", 0.01, 2, 0.01)
	_spin(controls, &"lift_height", "King lift", 0, 160, 1)
	_spin(controls, &"capture_impact_fraction", "Capture impact point", 0.1, 0.95, 0.01)
	_spin(controls, &"knockoff_horizontal_speed", "Knockoff horizontal speed", 1, 2000, 1)
	_spin(controls, &"knockoff_upward_speed", "Knockoff upward speed", 0, 2000, 1)
	_spin(controls, &"knockoff_gravity", "Knockoff gravity", 1, 5000, 1)
	_spin(controls, &"knockoff_angular_speed", "Knockoff angular speed", 0, 3600, 1)
	destination_label = Label.new()
	controls.add_child(destination_label)
	play_button = _button(controls, "Play Selected Direction", _play)
	_button(controls, "Reset Preview", _rebuild_fixture)
	_button(controls, "Publish Universal Movement", _publish)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)
	_refresh_destination_label()


func _rebuild_fixture() -> void:
	if model == null or playing:
		return
	var position := ChessPosition.new()
	var king_selector := get_node_or_null("CanvasLayer/PanelContainer/ScrollContainer/VBoxContainer/KingSelector") as OptionButton
	# The controls live in a generated CanvasLayer, so resolve the selector by type/name.
	if king_selector == null:
		king_selector = find_child("KingSelector", true, false) as OptionButton
	var king_type: StringName = king_selector.get_item_metadata(king_selector.selected) if king_selector != null else &"minotaur_king"
	var king := ChessPieceCatalog.create_piece(king_type, "white", CENTER)
	position.pieces.append(king.capture_piece_state())
	if capture_mode:
		var defender := ChessPieceCatalog.create_piece(&"pawn", "black", selected_destination)
		position.pieces.append(defender.capture_piece_state())
	model.load_position(position)
	_bind_live_profile()
	_highlight_selection()
	_refresh_hand_path()


func _bind_live_profile() -> void:
	var magic := adapter.get_king_magic_controller("white")
	if magic != null:
		magic.profile.movement_profile = profile
		magic.rng.seed = _knockoff_preview_seed()


func _on_square_selected(coordinate: Vector2i) -> void:
	if playing or coordinate == CENTER:
		return
	var delta := coordinate - CENTER
	if absi(delta.x) > 1 or absi(delta.y) > 1:
		return
	selected_destination = coordinate
	_rebuild_fixture()
	_refresh_destination_label()


func _highlight_selection() -> void:
	board.clear_highlights()
	board.highlight_squares([selected_destination])


func _make_path_line(color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.antialiased = true
	line.z_index = ChessBoardView.BOARD_EFFECT_Z + 1
	board.add_child(line)
	return line


func _set_playback_speed(index: int) -> void:
	var speeds := [
		PresentationPolicy.Speed.NORMAL,
		PresentationPolicy.Speed.SLOW,
		PresentationPolicy.Speed.ULTRA_SLOW,
	]
	adapter.set_presentation_speed(speeds[clampi(index, 0, speeds.size() - 1)])


func _set_path_preview_visible(enabled: bool) -> void:
	for line in [approach_path, swipe_path, retreat_path]:
		if is_instance_valid(line):
			line.visible = enabled


func _set_knockoff_path_preview_visible(enabled: bool) -> void:
	if is_instance_valid(knockoff_path):
		knockoff_path.visible = enabled and capture_mode


func _knockoff_preview_seed() -> int:
	return 4400 + selected_destination.x * 17 + selected_destination.y * 31


func _refresh_hand_path() -> void:
	if board == null or board.board.is_empty() or approach_path == null:
		return
	var hand := board.get_hand_rig_for_color("white")
	if hand == null:
		return
	var world_scale := board.get_world_scale()
	var effective_scale := world_scale * hand.art_scale_multiplier
	var king_position := board.grid_to_screen(CENTER.x, CENTER.y)
	var base_hover := king_position + ChessPresentationTransform.king_hover_offset(profile.hand_hover_offset, hand.seat)
	var gesture := ChessKingMagicController.gesture_points(
		king_position,
		board.grid_to_screen(selected_destination.x, selected_destination.y),
		base_hover,
		profile.gesture_corridor_clearance * world_scale,
		profile.gesture_sweep_distance * world_scale
	)
	var rest := hand._offscreen_rest_position(effective_scale)
	approach_path.points = PackedVector2Array([rest, gesture[0]])
	swipe_path.points = PackedVector2Array([gesture[0], gesture[1]])
	var path := ChessKingMagicController.build_gesture_path(
		gesture[0], gesture[1], rest, profile.gesture_minimum_turn_radius * world_scale)
	var all_points: PackedVector2Array = path.points
	var retreat_points := PackedVector2Array()
	for index in range(int(path.join_index), all_points.size()):
		retreat_points.append(all_points[index])
	retreat_path.points = retreat_points
	_refresh_knockoff_path()


func _refresh_knockoff_path() -> void:
	if knockoff_path == null:
		return
	knockoff_path.visible = capture_mode and knockoff_path_preview_toggle != null and knockoff_path_preview_toggle.button_pressed
	if not capture_mode:
		knockoff_path.clear_points()
		return
	var king_origin := board.grid_to_screen(CENTER.x, CENTER.y)
	var destination := board.grid_to_screen(selected_destination.x, selected_destination.y)
	var random := RandomNumberGenerator.new()
	random.seed = _knockoff_preview_seed()
	var defender := adapter.get_piece_view(model.board[selected_destination.x][selected_destination.y]) as PieceView
	var trajectory := ChessKingMagicController.build_ballistic_knockoff(
		king_origin,
		destination,
		destination,
		board.get_viewport_rect().size,
		ChessKingMagicController.piece_visual_radius(defender),
		profile.knockoff_horizontal_speed * board.get_world_scale(),
		profile.knockoff_upward_speed * board.get_world_scale(),
		profile.knockoff_gravity * board.get_world_scale(),
		random
	)
	knockoff_path.points = trajectory.points


func _play() -> void:
	if playing:
		return
	_rebuild_fixture()
	playing = true
	play_button.disabled = true
	status_label.text = "Playing %s…" % ("capture" if capture_mode else "move")
	var king := model.get_king("white")
	var magic := adapter.get_king_magic_controller("white")
	if king == null or magic == null:
		status_label.text = "Could not construct the King movement preview."
		playing = false
		play_button.disabled = false
		return
	var defender: PieceView = adapter.get_piece_view(model.board[selected_destination.x][selected_destination.y]) as PieceView if capture_mode else null
	if capture_mode:
		await magic.play_capture(CENTER, selected_destination, defender)
	else:
		await magic.play_move(CENTER, selected_destination)
	status_label.text = "Preview complete. Press Play to repeat the same direction."
	playing = false
	play_button.disabled = false


func _publish() -> void:
	var result := RuntimePublisher.publish_universal_movement_profile(profile)
	status_label.text = result.message


func _load_runtime_profile() -> ChessMagicalMoveProfile:
	var king_profile := ResourceLoader.load(RuntimePublisher.PLAYER_KING_RUNTIME_PATH, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	if king_profile != null:
		king_profile.ensure_defaults()
		return king_profile.movement_profile.duplicate(true) as ChessMagicalMoveProfile
	return ChessMagicalMoveProfile.new()


func _refresh_destination_label() -> void:
	if destination_label == null:
		return
	var delta := selected_destination - CENTER
	destination_label.text = "Selected: %s  (%+d, %+d)" % [_direction_name(delta), delta.x, delta.y]


static func _direction_name(delta: Vector2i) -> String:
	var vertical := "North" if delta.x < 0 else ("South" if delta.x > 0 else "")
	var horizontal := "West" if delta.y < 0 else ("East" if delta.y > 0 else "")
	return vertical + horizontal


func _add_vector_controls(parent: Control, property: StringName, label_text: String) -> void:
	var value: Vector2 = profile.get(property)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 155
	row.add_child(label)
	for component_index in range(2):
		var spin := SpinBox.new()
		spin.min_value = -500
		spin.max_value = 500
		spin.step = 1
		spin.value = value[component_index]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_set_vector_component.bind(property, component_index))
		row.add_child(spin)


func _set_vector_component(new_value: float, property: StringName, component_index: int) -> void:
	var current: Vector2 = profile.get(property)
	current[component_index] = new_value
	profile.set(property, current)
	_refresh_hand_path()


func _spin(parent: Control, property: StringName, label_text: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 195
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = String(property)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = float(profile.get(property))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(value: float):
		profile.set(property, value)
		_refresh_hand_path())
	row.add_child(spin)
	property_controls[property] = spin


func _option(parent: Control, label_text: String, entries: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in entries:
		option.add_item(entry)
	row.add_child(option)
	return option


func _button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
