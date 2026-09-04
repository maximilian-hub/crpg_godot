extends Node2D

const PIECE_SCENE := preload("res://scenes/piece.tscn")
const GAME_SCENE := preload("res://scenes/chess_game.tscn")
const DeathEffect := preload("res://scripts/view/chess_king_death_effect.gd")
const DeathProfile := preload("res://scripts/view/chess_king_death_profile.gd")
const DeathPreset := preload("res://tools/dev_chess_king_death/chess_king_death_lab_preset.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const PRESET_DIRECTORY := "res://.cache/chess_king_death_presets"

var profile: Resource
var preview_piece: PieceView
var active_effect: Node
var king_selector: OptionButton
var army_selector: OptionButton
var preset_selector: OptionButton
var preset_name: LineEdit
var sound_label: Label
var status_label: Label
var file_dialog: FileDialog


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	profile = _runtime_profile()
	_build_controls()
	_refresh_presets()
	_rebuild_piece()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("15131a"))
	var size := 32
	for row in range(int(ceil(get_viewport_rect().size.y / size))):
		for column in range(int(ceil(get_viewport_rect().size.x / size))):
			var color := Color("312936") if (row + column) % 2 == 0 else Color("211d29")
			draw_rect(Rect2(Vector2(column, row) * size, Vector2.ONE * size), color)


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(390, 0)
	panel.z_index = 200
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 700)
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 365
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "King Death Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	preset_selector = _option(controls, "Preset", [])
	preset_selector.item_selected.connect(_load_preset)
	king_selector = _option(controls, "King", [])
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"king"):
		king_selector.add_item(ChessPieceCatalog.get_definition(type_id).get("name", str(type_id)))
		king_selector.set_item_metadata(king_selector.item_count - 1, type_id)
	king_selector.item_selected.connect(func(_index): _rebuild_piece())
	army_selector = _option(controls, "Army", ["White", "Black"])
	army_selector.item_selected.connect(func(_index): _rebuild_piece())
	_spin(controls, &"red_blink_count", "Red blinks", 1, 8, 1)
	_spin(controls, &"blink_on_duration", "Blink on", 0.01, 1.0, 0.01)
	_spin(controls, &"blink_off_duration", "Blink off", 0.01, 1.0, 0.01)
	_spin(controls, &"pre_death_hold_duration", "Red tremor hold", 0.0, 4.0, 0.01)
	_spin(controls, &"stone_fade_duration", "Red-to-stone fade", 0.05, 3.0, 0.01)
	_spin(controls, &"tremor_interval", "Tremor interval", 0.01, 0.5, 0.01)
	_spin(controls, &"tremor_max_pixels", "Tremor pixels", 0, 16, 1)
	_spin(controls, &"tremor_slowdown_duration", "Tremor slowdown", 0.01, 3.0, 0.01)
	_spin(controls, &"result_delay", "Results delay", 0.0, 10.0, 0.05)
	_spin(controls, &"rift_circle_count", "Rift circles", 1, 16, 1)
	_spin(controls, &"rift_radius", "Circle radius", 1, 48, 1)
	_spin(controls, &"rift_speed", "Circle speed", 10, 1000, 1)
	_spin(controls, &"rift_frame_duration", "Circle frame time", 0.02, 0.5, 0.01)
	_spin(controls, &"rift_frame_growth", "Circle frame growth", 0.0, 0.5, 0.01)
	_spin(controls, &"discharge_marker_size", "Discharge marker size", 2, 160, 1)
	_spin(controls, &"discharge_marker_width", "Discharge marker width", 0.5, 32, 0.5)
	_spin(controls, &"discharge_frequency", "Discharge frequency", 1, 60, 1)
	_spin(controls, &"discharge_duration", "Discharge duration", 0.05, 4.0, 0.05)
	_spin(controls, &"discharge_marker_lifetime", "Marker lifetime", 0.02, 1.0, 0.01)
	_spin(controls, &"discharge_falloff_exponent", "Discharge falloff", 0.1, 8.0, 0.1)
	_spin(controls, &"checker_size", "Checker size", 1, 64, 1)
	_spin(controls, &"sound_volume_db", "Sound volume", -40, 6, 0.5)
	sound_label = Label.new()
	sound_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(sound_label)
	var sound_button := Button.new()
	sound_button.text = "Choose Death Sound"
	sound_button.pressed.connect(func(): file_dialog.popup_centered_ratio(0.75))
	controls.add_child(sound_button)
	var playback := HBoxContainer.new()
	controls.add_child(playback)
	_button(playback, "Play", _play)
	_button(playback, "Reset", _rebuild_piece)
	var save_row := HBoxContainer.new()
	controls.add_child(save_row)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "Death profile name"
	preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(preset_name)
	_button(save_row, "Save", _save_preset)
	_button(controls, "Publish Universal Death", _publish)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.wav, *.ogg, *.mp3 ; Audio"])
	file_dialog.file_selected.connect(_select_sound)
	add_child(file_dialog)
	_sync_sound_label()


func _play() -> void:
	_rebuild_piece()
	active_effect = DeathEffect.new()
	active_effect.position = preview_piece.position
	add_child(active_effect)
	active_effect.configure(preview_piece, profile, _in_game_world_scale())
	active_effect.play()
	status_label.text = "Playing death preview…"
	await active_effect.completed
	status_label.text = "Preview complete."


func _rebuild_piece() -> void:
	if is_instance_valid(active_effect): active_effect.queue_free()
	if is_instance_valid(preview_piece): preview_piece.queue_free()
	preview_piece = PIECE_SCENE.instantiate() as PieceView
	var type_id: StringName = king_selector.get_item_metadata(king_selector.selected) if king_selector != null and king_selector.item_count > 0 else &"minotaur_king"
	var color := "black" if army_selector != null and army_selector.selected == 1 else "white"
	preview_piece.set_model(ChessPieceCatalog.create_piece(type_id, color, Vector2i.ZERO))
	preview_piece.position = get_viewport_rect().size * Vector2(0.64, 0.55)
	preview_piece.scale = Vector2.ONE * _in_game_world_scale()
	preview_piece.z_index = 20
	add_child(preview_piece)


func _in_game_world_scale() -> float:
	# Read the shipping scene's authored layout values rather than maintaining a
	# second approximation of its projection in this lab.
	var game := GAME_SCENE.instantiate()
	var reference_board := game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	var projection := ChessBoardProjection.new()
	projection.configure(
		get_viewport_rect().size,
		8,
		8,
		"white",
		reference_board.viewport_height_width_ratio,
		reference_board.viewport_width_cap_ratio,
		reference_board.projected_depth_ratio,
		reference_board.far_edge_width_ratio,
		reference_board.vertical_center_ratio
	)
	game.free()
	return ChessBoardView.calculate_world_scale(projection.get_near_edge_width())


func _select_sound(path: String) -> void:
	var stream := ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	if stream == null:
		status_label.text = "Could not load audio from %s" % path
		return
	profile.death_sound = stream
	_sync_sound_label()


func _sync_sound_label() -> void:
	var path: String = profile.death_sound.resource_path if profile.death_sound != null else "None"
	sound_label.text = "Death sound: %s" % path


func _save_preset() -> void:
	var name := preset_name.text.strip_edges()
	var stem := name.to_snake_case().validate_filename()
	if stem.is_empty():
		status_label.text = "Enter a profile name first."
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIRECTORY))
	var preset := DeathPreset.new()
	preset.display_name = name
	preset.death_profile = profile.duplicate(true)
	var path := "%s/%s.tres" % [PRESET_DIRECTORY, stem]
	var error := ResourceSaver.save(preset, path)
	status_label.text = "Saved %s" % ProjectSettings.globalize_path(path) if error == OK else "Save failed (%d)." % error
	if error == OK: _refresh_presets(path)


func _refresh_presets(selected_path := "") -> void:
	preset_selector.clear()
	preset_selector.add_item("Published Universal Death")
	preset_selector.set_item_metadata(0, RuntimePublisher.KING_DEATH_RUNTIME_PATH)
	if selected_path == RuntimePublisher.KING_DEATH_RUNTIME_PATH:
		preset_selector.select(0)
	var directory := DirAccess.open(PRESET_DIRECTORY)
	if directory == null: return
	for file in directory.get_files():
		if file.get_extension().to_lower() != "tres": continue
		var path := "%s/%s" % [PRESET_DIRECTORY, file]
		var preset := ResourceLoader.load(path, "ChessKingDeathLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
		if preset != null and preset.get_script() == DeathPreset and preset.is_supported():
			preset_selector.add_item(preset.display_name)
			preset_selector.set_item_metadata(preset_selector.item_count - 1, path)
			if path == selected_path: preset_selector.select(preset_selector.item_count - 1)


func _load_preset(index: int) -> void:
	var selected_path: String = preset_selector.get_item_metadata(index)
	if selected_path == RuntimePublisher.KING_DEATH_RUNTIME_PATH:
		profile = _runtime_profile()
	else:
		var preset := ResourceLoader.load(selected_path, "ChessKingDeathLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
		if preset == null: return
		profile = preset.death_profile.duplicate(true)
	preset_name.text = "" if selected_path == RuntimePublisher.KING_DEATH_RUNTIME_PATH else preset_selector.get_item_text(index)
	_sync_controls()
	_rebuild_piece()


func _publish() -> void:
	var result: Dictionary = RuntimePublisher.publish_death_profile(profile)
	status_label.text = result.message


func _runtime_profile() -> Resource:
	var runtime := ResourceLoader.load(RuntimePublisher.KING_DEATH_RUNTIME_PATH, "ChessKingDeathProfile", ResourceLoader.CACHE_MODE_IGNORE)
	if runtime != null:
		return runtime.duplicate(true)
	return DeathProfile.new()


func _spin(parent: Control, property: StringName, label_text: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 170
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = String(property)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = float(profile.get(property))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(value): profile.set(property, int(value) if step >= 1.0 and property in [&"red_blink_count", &"tremor_max_pixels", &"rift_circle_count"] else value))
	row.add_child(spin)


func _sync_controls() -> void:
	for node in find_children("*", "SpinBox", true, false):
		if profile.get(node.name) != null: node.set_value_no_signal(float(profile.get(node.name)))
	_sync_sound_label()


func _option(parent: Control, label_text: String, entries: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in entries: option.add_item(entry)
	row.add_child(option)
	return option


func _button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
