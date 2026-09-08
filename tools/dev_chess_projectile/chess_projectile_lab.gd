extends Node2D

const Profile := preload("res://scripts/view/chess_special_move_presentation_profile.gd")
const Director := preload("res://scripts/view/chess_special_move_director.gd")
const Publisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const RUNTIME_CATALOG := "res://assets/chess_ability_presentations.tres"
const CENTER := Vector2i(4, 4)

@onready var board: ChessBoardView = $ChessBoard
var profile: Resource = Profile.new()
var source: PieceView
var target: PieceView
var selected := Vector2i(3, 4)
var playback_scale := 1.0
var running := false
var path_line: Line2D
var side_path_lines: Array[Line2D] = []
var knockoff_line: Line2D
var status: Label
var active_director: ChessSpecialMoveDirector
var spin_bindings: Array[Dictionary] = []
var audio_bindings: Array[Dictionary] = []

func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_load_published_profile()
	_build_controls()
	board.editor_square_pressed.connect(_select_square)
	_rebuild()

func _load_published_profile() -> void:
	var catalog: Resource = ResourceLoader.load(RUNTIME_CATALOG, "", ResourceLoader.CACHE_MODE_IGNORE)
	if catalog == null:
		return
	var published: Resource = catalog.find_profile(&"arakne_king", &"spike_burst")
	if published != null:
		var loaded := _coerce_profile(published)
		if spin_bindings.is_empty():
			profile = loaded
		else:
			_apply_profile(loaded)

func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(370, 0)
	panel.z_index = 300
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370, 900)
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 350
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "Spike Burst Special Move Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	_section(controls, "Invocation")
	_add_audio_path(controls, "Cry sound", profile, &"cry_sound")
	_add_spin(controls, "Cry duration", profile, &"cry_duration", 0, 5, 0.01)
	_add_spin(controls, "Cry volume dB", profile, &"cry_volume_db", -60, 6, 0.5)
	_add_spin(controls, "Wiggle blinks", profile, &"wiggle_blink_count", 0, 8, 1)
	_add_spin(controls, "Lines per blink", profile, &"wiggle_line_count", 1, 12, 1)
	_add_spin(controls, "Wiggle radius", profile, &"wiggle_radius", 1, 128, 1)
	_add_spin(controls, "Wiggle length", profile, &"wiggle_length", 1, 64, 1)
	_add_spin(controls, "Wiggle width", profile, &"wiggle_width", 1, 16, 1)
	_add_spin(controls, "Wiggle on time", profile, &"wiggle_on_time", 0.01, 1, 0.01)
	_add_spin(controls, "Wiggle off time", profile, &"wiggle_off_time", 0, 1, 0.01)
	_add_audio_path(controls, "Wiggle sound", profile, &"wiggle_sound")
	_add_spin(controls, "Wiggle volume dB", profile, &"wiggle_volume_db", -60, 6, 0.5)
	_section(controls, "Volley")
	_add_spin(controls, "Spike count", profile, &"projectile_count", 1, 8, 1)
	_add_spin(controls, "Shot interval", profile, &"shot_interval", 0, 2, 0.01)
	_add_spin(controls, "Volley tangent offset", profile, &"volley_tangent_offset", 0, 128, 1)
	var projectile: ChessProjectilePresentationProfile = profile.resolved_projectile_profile()
	_add_audio_path(controls, "Spike launch sound", projectile, &"projectile_sound")
	_add_spin(controls, "Launch volume dB", projectile, &"projectile_volume_db", -60, 6, 0.5)
	_add_spin(controls, "Pitch variation", projectile, &"pitch_variation", 0, 0.5, 0.01)
	_add_spin(controls, "Travel speed", projectile, &"travel_speed", 1, 3000, 1)
	_add_spin(controls, "Projectile scale", projectile, &"projectile_scale", 0.1, 8, 0.05)
	_add_spin(controls, "Rotation offset", projectile, &"rotation_offset_degrees", -180, 180, 1)
	_add_spin(controls, "Launch offset X", projectile, &"launch_offset:x", -128, 128, 1)
	_add_spin(controls, "Launch offset Y", projectile, &"launch_offset:y", -128, 128, 1)
	_add_audio_path(controls, "Spike hit sound", projectile, &"impact_sound")
	_add_spin(controls, "Hit volume dB", projectile, &"impact_volume_db", -60, 6, 0.5)
	_add_spin(controls, "Impact scale", projectile, &"impact_scale", 0.1, 8, 0.05)
	_section(controls, "Knockoff")
	_add_spin(controls, "Knockoff X speed", projectile, &"knockoff_horizontal_speed", 1, 2000, 1)
	_add_spin(controls, "Knockoff up speed", projectile, &"knockoff_upward_speed", 0, 2000, 1)
	_add_spin(controls, "Knockoff gravity", projectile, &"knockoff_gravity", 1, 5000, 1)
	_add_spin(controls, "Knockoff spin", projectile, &"knockoff_angular_speed", 0, 3600, 1)
	var timeline := Label.new()
	timeline.text = "Timeline: Cry / Cue → Spike 1 → Spike 2 → Spike 3 [DAMAGE] → Knockoff"
	timeline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(timeline)
	var speed := _option(controls, "Playback", ["Normal", "Slow", "Ultra Slow"])
	for i in range(3):
		speed.set_item_metadata(i, [1.0, 4.0, 8.0][i])
	speed.item_selected.connect(func(i): playback_scale = float(speed.get_item_metadata(i)))
	var paths := CheckButton.new()
	paths.text = "Show path previews"
	paths.button_pressed = true
	paths.toggled.connect(func(value: bool):
		path_line.visible = value
		for side_path in side_path_lines:
			side_path.visible = value
		knockoff_line.visible = value
	)
	controls.add_child(paths)
	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	_button(buttons, "Play", _play)
	_button(buttons, "Reset Preview", _reset_preview)
	var publishing := HBoxContainer.new()
	controls.add_child(publishing)
	_button(publishing, "Reload Published", _reload_published)
	_button(publishing, "Publish Spike Burst", _publish)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status)
	path_line = _line(Color("40d6f0"))
	side_path_lines.append(_line(Color("40d6f0", 0.72)))
	side_path_lines.append(_line(Color("40d6f0", 0.72)))
	knockoff_line = _line(Color("ed6ac4"))

func _rebuild() -> void:
	var fixture: Array = []
	for r in range(8):
		var row: Array = []
		row.resize(8)
		row.fill(null)
		fixture.append(row)
	fixture[CENTER.x][CENTER.y] = ChessPieceCatalog.create_piece(&"arakne_king", "white", CENTER)
	fixture[selected.x][selected.y] = ChessPieceCatalog.create_piece(&"pawn", "black", selected)
	var rendered := board.draw_board(fixture) if board.board == null or board.board.is_empty() else board.rebuild_board(fixture)
	source = rendered[fixture[CENTER.x][CENTER.y]]
	target = rendered[fixture[selected.x][selected.y]]
	board.clear_highlights()
	board.highlight_squares([selected])
	_refresh_paths()
	status.text = "Ready — select an adjacent target square"

func _reset_preview() -> void:
	# Reset is also an escape hatch during slow-motion playback.
	if is_instance_valid(active_director):
		active_director.cancel()
	active_director = null
	running = false
	_rebuild()

func _select_square(coordinate: Vector2i) -> void:
	var delta := coordinate - CENTER
	if maxi(absi(delta.x), absi(delta.y)) != 1: return
	selected = coordinate
	_rebuild()

func _play() -> void:
	if running or not is_instance_valid(source) or not is_instance_valid(target): return
	running = true
	active_director = Director.new()
	board.add_child(active_director)
	active_director.configure(board, source, target, profile, playback_scale, selected.x * 101 + selected.y * 997)
	await active_director.play_until_gameplay_impact()
	if not running or not is_instance_valid(active_director):
		return
	status.text = "Third spike: gameplay damage"
	await active_director.play_aftermath(true, false)
	if not running or not is_instance_valid(active_director):
		return
	active_director.queue_free()
	active_director = null
	running = false
	status.text = "Preview complete — Reset or Play again"

func _refresh_paths() -> void:
	if not is_instance_valid(source) or not is_instance_valid(target): return
	var projectile: ChessProjectilePresentationProfile = profile.resolved_projectile_profile()
	var start: Vector2 = source.get_anchor_position_in(board, source.get_body_anchor()) + projectile.launch_offset * board.get_world_scale()
	var finish: Vector2 = target.get_anchor_position_in(board, target.get_body_anchor())
	path_line.points = PackedVector2Array([start, finish])
	var direction := (finish - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	for index in range(side_path_lines.size()):
		var shot_index := index
		var has_shot := shot_index < maxi(profile.projectile_count - 1, 0)
		side_path_lines[index].visible = path_line.visible and has_shot
		if has_shot:
			var offset := tangent * Director.shot_tangent_offset(shot_index, profile.projectile_count, profile.volley_tangent_offset) * board.get_world_scale()
			side_path_lines[index].points = PackedVector2Array([start + offset, finish + offset])
		else:
			side_path_lines[index].clear_points()
	var random := RandomNumberGenerator.new()
	random.seed = selected.x * 101 + selected.y * 997
	var trajectory := _build_knockoff(source.position, target.position, target, random)
	knockoff_line.points = trajectory.points

func _build_knockoff(king_origin: Vector2, destination: Vector2, piece: PieceView, random: RandomNumberGenerator) -> Dictionary:
	return ChessKingMagicController.build_ballistic_knockoff(
		king_origin,
		destination,
		piece.position,
		get_viewport_rect().size,
		ChessKingMagicController.piece_visual_radius(piece),
		profile.resolved_projectile_profile().knockoff_horizontal_speed * board.get_world_scale(),
		profile.resolved_projectile_profile().knockoff_upward_speed * board.get_world_scale(),
		profile.resolved_projectile_profile().knockoff_gravity * board.get_world_scale(),
		random
	)

func _publish() -> void:
	var result: Dictionary = Publisher.publish_special_move_profile(&"arakne_king", &"spike_burst", profile)
	status.text = result.message

func _reload_published() -> void:
	_reset_preview()
	_load_published_profile()
	_refresh_paths()
	status.text = "Reloaded the published Spike Burst settings."

func _coerce_profile(value: Resource) -> ChessSpecialMovePresentationProfile:
	if value is ChessSpecialMovePresentationProfile:
		return value.duplicate(true)
	var sequence := Profile.new()
	sequence.cry_duration = 0.0
	sequence.wiggle_blink_count = 0
	sequence.projectile_count = 1
	sequence.projectile_profile = value.duplicate(true)
	return sequence

func _apply_profile(source_profile: ChessSpecialMovePresentationProfile) -> void:
	for property in [
		&"cry_sound", &"cry_volume_db", &"cry_duration", &"wiggle_blink_count", &"wiggle_line_count",
		&"wiggle_radius", &"wiggle_length", &"wiggle_width", &"wiggle_on_time", &"wiggle_off_time",
		&"wiggle_sound", &"wiggle_volume_db", &"projectile_count", &"shot_interval", &"volley_tangent_offset"
	]:
		profile.set(property, source_profile.get(property))
	var destination_projectile: ChessProjectilePresentationProfile = profile.resolved_projectile_profile()
	var source_projectile: ChessProjectilePresentationProfile = source_profile.resolved_projectile_profile()
	for property in [
		&"projectile_frames", &"projectile_animation", &"projectile_scale", &"travel_speed",
		&"rotation_offset_degrees", &"launch_offset", &"projectile_sound", &"projectile_volume_db",
		&"impact_frames", &"impact_animation", &"impact_scale", &"impact_playback_speed", &"impact_offset",
		&"impact_sound", &"impact_volume_db", &"pitch_variation", &"knockoff_horizontal_speed",
		&"knockoff_upward_speed", &"knockoff_gravity", &"knockoff_angular_speed"
	]:
		destination_projectile.set(property, source_projectile.get(property))
	_sync_bound_controls()

func _add_spin(parent: Control, label: String, owner: Resource, property: StringName, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	var parts := String(property).split(":")
	if parts.size() == 1:
		spin.value = owner.get(parts[0])
	else:
		var initial_vector: Vector2 = owner.get(parts[0])
		spin.value = initial_vector.x if parts[1] == "x" else initial_vector.y
	spin.value_changed.connect(func(value: float):
		if parts.size() == 1:
			owner.set(parts[0], value)
		else:
			var vector: Vector2 = owner.get(parts[0])
			if parts[1] == "x":
				vector.x = value
			else:
				vector.y = value
			owner.set(parts[0], vector)
		_refresh_paths()
	)
	row.add_child(spin)
	spin_bindings.append({"spin": spin, "owner": owner, "parts": parts})

func _section(parent: Control, title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 17)
	parent.add_child(label)

func _add_audio_path(parent: Control, label: String, owner: Resource, property: StringName) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var path := LineEdit.new()
	path.custom_minimum_size.x = 170
	var current := owner.get(property) as AudioStream
	path.text = current.resource_path if current != null else ""
	path.placeholder_text = "res://assets/audio/..."
	path.text_submitted.connect(func(value: String):
		var cleaned := value.strip_edges()
		if cleaned.is_empty():
			owner.set(property, null)
			status.text = "%s cleared" % label
			return
		var loaded := ResourceLoader.load(cleaned) as AudioStream
		if loaded == null:
			status.text = "Could not load %s" % cleaned
			return
		owner.set(property, loaded)
		status.text = "%s loaded" % label
	)
	row.add_child(path)
	audio_bindings.append({"path": path, "owner": owner, "property": property})

func _sync_bound_controls() -> void:
	for binding in spin_bindings:
		var parts: PackedStringArray = binding.parts
		var owner: Resource = binding.owner
		var value: float
		if parts.size() == 1:
			value = float(owner.get(parts[0]))
		else:
			var vector: Vector2 = owner.get(parts[0])
			value = vector.x if parts[1] == "x" else vector.y
		(binding.spin as SpinBox).set_value_no_signal(value)
	for binding in audio_bindings:
		var stream := (binding.owner as Resource).get(binding.property) as AudioStream
		(binding.path as LineEdit).text = stream.resource_path if stream != null else ""

func _option(parent: Control, label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var option := OptionButton.new()
	for item in items:
		option.add_item(item)
	row.add_child(option)
	return option
func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _line(color: Color) -> Line2D:
	var line := Line2D.new()
	line.width = 2
	line.default_color = color
	line.z_index = 200
	add_child(line)
	return line
