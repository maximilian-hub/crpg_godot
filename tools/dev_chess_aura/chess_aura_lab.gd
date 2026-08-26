# DEV PRESENTATION COMPARISON TOOL
# Compares three reusable Chess Energy treatments without entering the game flow.

extends Node2D

const PIECE_SCENE := preload("res://scenes/piece.tscn")
const HAND_STYLE := preload("res://assets/arms/player/skeleton_hand_style.tres")
const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const LabPreset := preload("res://tools/dev_chess_aura/chess_aura_lab_preset.gd")
const PRESET_DIRECTORY := "res://.cache/chess_aura_presets"
## Match the fluid standalone ChessBoard settings in scenes/chess_game.tscn.
const CHESS_VIEWPORT_HEIGHT_WIDTH_RATIO := 1.0
const CHESS_VIEWPORT_WIDTH_CAP_RATIO := 0.72
const HAND_PREVIEW_GRIP_POSITION := Vector2(1250, 1350)
const HAND_GRIP_OFFSET_MIN := -900.0
const HAND_GRIP_OFFSET_MAX := 900.0

var aura_profile: ChessAuraProfile
var king_aura: ChessAura2D
var hand_aura: ChessAura2D
var target_selector: OptionButton
var mode_selector: OptionButton
var power_slider: HSlider
var silhouette_power_slider: HSlider
var particle_power_slider: HSlider
var hand_grip_slider: HSlider
var king_selector: OptionButton
var army_selector: OptionButton
var preset_selector: OptionButton
var preset_name_edit: LineEdit
var preset_status: Label
var overwrite_confirmation: ConfirmationDialog
var profile_controls: Dictionary = {}
var color_controls: Dictionary = {}
var preview_king: PieceView
var preview_hand: Node2D
var pending_preset: Resource
var pending_preset_path := ""


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	aura_profile = AuraProfile.new()
	_build_stage()
	_build_controls()
	_refresh_preset_selector()
	get_viewport().size_changed.connect(_layout_preview_scale)
	_layout_preview_scale()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("11131d"))
	for row in range(4):
		for column in range(8):
			var color := Color("292d3c") if (row + column) % 2 == 0 else Color("1d2130")
			draw_rect(Rect2(Vector2(300 + column * 120, 520 + row * 62), Vector2(120, 62)), color)


func _build_stage() -> void:
	preview_king = PIECE_SCENE.instantiate() as PieceView
	preview_king.name = "AuraKing"
	preview_king.position = Vector2(570, 700)
	preview_king.set_model(MinotaurKing.new("white", Vector2i.ZERO))
	add_child(preview_king)

	preview_hand = Node2D.new()
	preview_hand.name = "AuraHand"
	# This is the grip position, not the artwork center. Keeping it near the
	# viewport bottom mirrors an actual board visit and leaves the aura-bearing
	# fingers visible while the long arm naturally continues offscreen.
	preview_hand.position = HAND_PREVIEW_GRIP_POSITION
	add_child(preview_hand)
	var hand_sprites: Array[Sprite2D] = []
	for entry in [
		{"name": "RearFingers", "texture": HAND_STYLE.open_rear_fingers, "z": 1},
		{"name": "Thumb", "texture": HAND_STYLE.open_thumb, "z": 3},
		{"name": "Arm", "texture": HAND_STYLE.open_arm, "z": 4},
	]:
		var sprite := Sprite2D.new()
		sprite.name = entry["name"]
		sprite.texture = entry["texture"]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(sprite.texture.get_size()) * 0.5 - Vector2(48, 118)
		sprite.z_index = entry["z"]
		preview_hand.add_child(sprite)
		hand_sprites.append(sprite)

	king_aura = Aura.new() as ChessAura2D
	king_aura.name = "KingAura"
	king_aura.profile = aura_profile
	add_child(king_aura)
	king_aura.bind_targets([preview_king.sprite])
	hand_aura = Aura.new() as ChessAura2D
	hand_aura.name = "HandAura"
	hand_aura.profile = aura_profile
	add_child(hand_aura)
	hand_aura.bind_targets(hand_sprites)


func _layout_preview_scale() -> void:
	if not is_instance_valid(preview_king) or not is_instance_valid(preview_hand):
		return
	var viewport_size := get_viewport_rect().size
	var near_edge_width := minf(
		viewport_size.y * CHESS_VIEWPORT_HEIGHT_WIDTH_RATIO,
		viewport_size.x * CHESS_VIEWPORT_WIDTH_CAP_RATIO
	)
	var board_world_scale := ChessBoardView.calculate_world_scale(near_edge_width)
	preview_king.scale = Vector2.ONE * board_world_scale
	# PlayerHandRig applies this additional art multiplier to the same board
	# world scale for every real move animation.
	var hand_defaults := PlayerHandRig.new()
	preview_hand.scale = Vector2.ONE * board_world_scale * hand_defaults.art_scale_multiplier
	hand_defaults.free()


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(310, 0)
	add_child(panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	panel.add_child(controls)
	var title := Label.new()
	title.text = "Chess Aura Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)

	mode_selector = _add_option(controls, "Treatment", ["Silhouette Resonance", "Chess-Square Flame", "Hybrid Soulfire"])
	mode_selector.select(Aura.AuraMode.HYBRID)
	mode_selector.item_selected.connect(_set_mode)
	target_selector = _add_option(controls, "Target", ["Both", "King", "Hand"])
	target_selector.item_selected.connect(func(_selected: int): _sync_power_control())
	king_selector = _add_option(controls, "King", [])
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"king"):
		var definition := ChessPieceCatalog.get_definition(type_id)
		king_selector.add_item(definition.get("name", str(type_id)))
		king_selector.set_item_metadata(king_selector.item_count - 1, type_id)
		if type_id == &"minotaur_king":
			king_selector.select(king_selector.item_count - 1)
	king_selector.item_selected.connect(func(_selected: int): _update_preview_king())
	army_selector = _add_option(controls, "Army", ["White", "Black"])
	army_selector.item_selected.connect(func(_selected: int): _update_preview_king())

	var color_row := HBoxContainer.new()
	controls.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "Core / Accent"
	color_label.custom_minimum_size.x = 120
	color_row.add_child(color_label)
	for property_name in [&"core_color", &"accent_color"]:
		var picker := ColorPickerButton.new()
		picker.color = aura_profile.get(property_name)
		picker.custom_minimum_size = Vector2(72, 28)
		picker.color_changed.connect(func(color: Color): aura_profile.set(property_name, color))
		color_row.add_child(picker)
		color_controls[property_name] = picker

	power_slider = _add_slider(controls, "Power", 0.0, 1.0, 0.01, aura_profile.idle_power, func(value: float):
		for aura in _selected_auras(): aura.set_power(value)
		silhouette_power_slider.set_value_no_signal(value)
		particle_power_slider.set_value_no_signal(value)
	)
	silhouette_power_slider = _add_slider(controls, "Silhouette", 0.0, 1.0, 0.01, aura_profile.idle_power, func(value: float):
		for aura in _selected_auras(): aura.set_silhouette_power(value)
		_sync_master_power_control()
	)
	particle_power_slider = _add_slider(controls, "Particles", 0.0, 1.0, 0.01, aura_profile.idle_power, func(value: float):
		for aura in _selected_auras(): aura.set_particle_power(value)
		_sync_master_power_control()
	)
	hand_grip_slider = _add_editable_slider(
		controls,
		"Hand grip Y",
		HAND_GRIP_OFFSET_MIN,
		HAND_GRIP_OFFSET_MAX,
		1.0,
		0.0,
		func(value: float): preview_hand.position.y = HAND_PREVIEW_GRIP_POSITION.y + value
	)
	profile_controls[&"rise_speed"] = _add_slider(controls, "Rise speed", 0.0, 120.0, 1.0, aura_profile.rise_speed, func(value: float): aura_profile.rise_speed = value)
	profile_controls[&"horizontal_spread"] = _add_slider(controls, "Spread", 0.0, 100.0, 1.0, aura_profile.horizontal_spread, func(value: float): aura_profile.horizontal_spread = value)
	profile_controls[&"square_density"] = _add_slider(controls, "Density", 0.0, 120.0, 1.0, aura_profile.square_density, func(value: float): aura_profile.square_density = value)
	profile_controls[&"square_size"] = _add_slider(controls, "Square size", 1.0, 6.0, 0.5, aura_profile.square_size, func(value: float): aura_profile.square_size = value)

	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	for entry in [
		{"label": "Power Up", "callable": _power_up},
		{"label": "Sustain", "callable": _sustain},
		{"label": "Power Down", "callable": _power_down},
		{"label": "Reset", "callable": _reset},
	]:
		var button := Button.new()
		button.text = entry["label"]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry["callable"])
		buttons.add_child(button)

	var preset_separator := HSeparator.new()
	controls.add_child(preset_separator)
	preset_selector = _add_option(controls, "Load Settings", [])
	preset_selector.item_selected.connect(_on_preset_selected)
	var save_row := HBoxContainer.new()
	controls.add_child(save_row)
	var save_label := Label.new()
	save_label.text = "Save Settings"
	save_label.custom_minimum_size.x = 88
	save_row.add_child(save_label)
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "Profile name"
	preset_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(preset_name_edit)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_request_save_preset)
	save_row.add_child(save_button)
	preset_status = Label.new()
	preset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_status.custom_minimum_size.x = 290
	controls.add_child(preset_status)
	overwrite_confirmation = ConfirmationDialog.new()
	overwrite_confirmation.title = "Overwrite Aura Settings?"
	overwrite_confirmation.confirmed.connect(_write_pending_preset)
	add_child(overwrite_confirmation)


func _add_option(parent: Control, label_text: String, options: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in options:
		option.add_item(text)
	row.add_child(option)
	return option


func _add_slider(parent: Control, label_text: String, minimum: float, maximum: float, step: float, initial: float, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 88
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = str(initial)
	value_label.custom_minimum_size.x = 48
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		callback.call(value)
	)
	return slider


func _add_editable_slider(parent: Control, label_text: String, minimum: float, maximum: float, step: float, initial: float, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 88
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var exact_value := SpinBox.new()
	exact_value.min_value = minimum
	exact_value.max_value = maximum
	exact_value.step = step
	exact_value.value = initial
	exact_value.allow_greater = false
	exact_value.allow_lesser = false
	exact_value.custom_minimum_size.x = 76
	row.add_child(exact_value)
	var syncing := false
	slider.value_changed.connect(func(value: float):
		if syncing:
			return
		syncing = true
		exact_value.set_value_no_signal(value)
		callback.call(value)
		syncing = false
	)
	exact_value.value_changed.connect(func(value: float):
		if syncing:
			return
		syncing = true
		slider.set_value_no_signal(value)
		callback.call(value)
		syncing = false
	)
	return slider


func _selected_auras() -> Array[ChessAura2D]:
	match target_selector.selected:
		1:
			return [king_aura]
		2:
			return [hand_aura]
		_:
			return [king_aura, hand_aura]


func _set_mode(selected: int) -> void:
	king_aura.set_mode(selected)
	hand_aura.set_mode(selected)


func _power_up() -> void:
	for aura in _selected_auras():
		aura.power_up()
	power_slider.set_value_no_signal(1.0)
	silhouette_power_slider.set_value_no_signal(1.0)
	particle_power_slider.set_value_no_signal(1.0)


func _sustain() -> void:
	for aura in _selected_auras():
		aura.set_power(1.0)
	power_slider.set_value_no_signal(1.0)
	silhouette_power_slider.set_value_no_signal(1.0)
	particle_power_slider.set_value_no_signal(1.0)


func _power_down() -> void:
	for aura in _selected_auras():
		aura.power_down()
	power_slider.set_value_no_signal(0.0)
	silhouette_power_slider.set_value_no_signal(0.0)
	particle_power_slider.set_value_no_signal(0.0)


func _reset() -> void:
	for aura in [king_aura, hand_aura]:
		aura.reset_effect()
	power_slider.set_value_no_signal(aura_profile.idle_power)
	silhouette_power_slider.set_value_no_signal(aura_profile.idle_power)
	particle_power_slider.set_value_no_signal(aura_profile.idle_power)


func _update_preview_king() -> void:
	if not is_instance_valid(preview_king) or king_selector.item_count == 0:
		return
	var type_id: StringName = king_selector.get_item_metadata(king_selector.selected)
	var color := "black" if army_selector.selected == 1 else "white"
	var piece := ChessPieceCatalog.create_piece(type_id, color, Vector2i.ZERO)
	if piece == null:
		_set_preset_status("Could not create %s %s." % [color, type_id], true)
		return
	preview_king.set_model(piece)


func _request_save_preset() -> void:
	var display_name := preset_name_edit.text.strip_edges()
	var file_stem := LabPreset.safe_file_stem(display_name)
	if display_name.is_empty() or file_stem.is_empty():
		_set_preset_status("Enter a valid profile name before saving.", true)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIRECTORY))
	if directory_error != OK:
		_set_preset_status("Could not create preset directory (error %d)." % directory_error, true)
		return
	pending_preset = _capture_preset(display_name)
	pending_preset_path = "%s/%s.tres" % [PRESET_DIRECTORY, file_stem]
	if FileAccess.file_exists(pending_preset_path):
		overwrite_confirmation.dialog_text = "Replace the existing preset '%s'?" % display_name
		overwrite_confirmation.popup_centered()
		return
	_write_pending_preset()


func _capture_preset(display_name: String) -> Resource:
	var preset: Resource = LabPreset.new()
	preset.display_name = display_name
	preset.aura_profile = aura_profile.duplicate(true) as ChessAuraProfile
	preset.aura_mode = mode_selector.selected
	preset.target_mode = target_selector.selected
	preset.king_power = king_aura.power
	preset.hand_power = hand_aura.power
	preset.component_powers_saved = true
	preset.king_silhouette_power = king_aura.silhouette_power
	preset.king_particle_power = king_aura.particle_power
	preset.hand_silhouette_power = hand_aura.silhouette_power
	preset.hand_particle_power = hand_aura.particle_power
	preset.hand_grip_y_offset = hand_grip_slider.value
	preset.king_type_id = king_selector.get_item_metadata(king_selector.selected)
	preset.army_color = "black" if army_selector.selected == 1 else "white"
	return preset


func _write_pending_preset() -> void:
	if pending_preset == null or pending_preset_path.is_empty():
		return
	var save_error := ResourceSaver.save(pending_preset, pending_preset_path)
	if save_error != OK:
		_set_preset_status("Could not save preset (error %d)." % save_error, true)
		return
	var saved_name: String = pending_preset.display_name
	var saved_path := pending_preset_path
	pending_preset = null
	pending_preset_path = ""
	_refresh_preset_selector(saved_path)
	_set_preset_status("Saved '%s' to %s" % [saved_name, ProjectSettings.globalize_path(saved_path)])


func _refresh_preset_selector(selected_path := "") -> void:
	if not is_instance_valid(preset_selector):
		return
	preset_selector.clear()
	preset_selector.add_item("Choose saved settings...")
	preset_selector.set_item_disabled(0, true)
	var discovered: Array[Dictionary] = []
	var directory := DirAccess.open(PRESET_DIRECTORY)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir() and file_name.get_extension().to_lower() == "tres":
				var path := "%s/%s" % [PRESET_DIRECTORY, file_name]
				var resource := ResourceLoader.load(path, "ChessAuraLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
				if _is_supported_preset(resource):
					discovered.append({"name": resource.display_name, "path": path})
			file_name = directory.get_next()
		directory.list_dir_end()
	discovered.sort_custom(func(a: Dictionary, b: Dictionary): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	for entry in discovered:
		preset_selector.add_item(entry["name"])
		var index := preset_selector.item_count - 1
		preset_selector.set_item_metadata(index, entry["path"])
		if entry["path"] == selected_path:
			preset_selector.select(index)


func _on_preset_selected(index: int) -> void:
	if index <= 0:
		return
	var path: String = preset_selector.get_item_metadata(index)
	var loaded := ResourceLoader.load(path, "ChessAuraLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	if not _is_supported_preset(loaded):
		_set_preset_status("Could not load a supported aura preset from %s." % path, true)
		return
	_apply_preset(loaded)
	_set_preset_status("Loaded '%s'." % loaded.display_name)


func _apply_preset(preset: Resource) -> void:
	king_aura.reset_effect()
	hand_aura.reset_effect()
	_copy_stored_properties(preset.aura_profile, aura_profile)
	mode_selector.select(clampi(preset.aura_mode, 0, Aura.AuraMode.size() - 1))
	target_selector.select(clampi(preset.target_mode, 0, target_selector.item_count - 1))
	_select_king_type(preset.king_type_id)
	army_selector.select(1 if preset.army_color == "black" else 0)
	_update_preview_king()
	king_aura.set_mode(mode_selector.selected)
	hand_aura.set_mode(mode_selector.selected)
	if preset.component_powers_saved:
		king_aura.set_silhouette_power(preset.king_silhouette_power)
		king_aura.set_particle_power(preset.king_particle_power)
		hand_aura.set_silhouette_power(preset.hand_silhouette_power)
		hand_aura.set_particle_power(preset.hand_particle_power)
	else:
		# Profiles saved before component powers existed retain their original
		# shared-power behavior.
		king_aura.set_power(preset.king_power)
		hand_aura.set_power(preset.hand_power)
	hand_grip_slider.set_value_no_signal(clampf(preset.hand_grip_y_offset, hand_grip_slider.min_value, hand_grip_slider.max_value))
	preview_hand.position.y = HAND_PREVIEW_GRIP_POSITION.y + hand_grip_slider.value
	_sync_profile_controls()
	_sync_power_control()
	preset_name_edit.text = preset.display_name


func _copy_stored_properties(source: Resource, destination: Resource) -> void:
	for property in source.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			destination.set(property["name"], source.get(property["name"]))


func _sync_profile_controls() -> void:
	for property_name in profile_controls:
		(profile_controls[property_name] as Range).set_value_no_signal(float(aura_profile.get(property_name)))
	for property_name in color_controls:
		(color_controls[property_name] as ColorPickerButton).color = aura_profile.get(property_name)


func _sync_power_control() -> void:
	if not is_instance_valid(power_slider):
		return
	var displayed_power := king_aura.power
	var displayed_silhouette := king_aura.silhouette_power
	var displayed_particles := king_aura.particle_power
	if target_selector.selected == 2:
		displayed_power = hand_aura.power
		displayed_silhouette = hand_aura.silhouette_power
		displayed_particles = hand_aura.particle_power
	elif target_selector.selected == 0:
		displayed_power = (king_aura.power + hand_aura.power) * 0.5
		displayed_silhouette = (king_aura.silhouette_power + hand_aura.silhouette_power) * 0.5
		displayed_particles = (king_aura.particle_power + hand_aura.particle_power) * 0.5
	power_slider.set_value_no_signal(displayed_power)
	silhouette_power_slider.set_value_no_signal(displayed_silhouette)
	particle_power_slider.set_value_no_signal(displayed_particles)


func _sync_master_power_control() -> void:
	var selected := _selected_auras()
	if selected.is_empty():
		return
	var total := 0.0
	for aura in selected:
		total += aura.power
	power_slider.set_value_no_signal(total / selected.size())


func _select_king_type(type_id: StringName) -> void:
	for index in range(king_selector.item_count):
		if king_selector.get_item_metadata(index) == type_id:
			king_selector.select(index)
			return


func _set_preset_status(message: String, is_error := false) -> void:
	preset_status.text = message
	preset_status.add_theme_color_override("font_color", Color("ff7777") if is_error else Color("8ee6a2"))


func _is_supported_preset(resource: Resource) -> bool:
	return resource != null and resource.get_script() == LabPreset and resource.is_supported()
