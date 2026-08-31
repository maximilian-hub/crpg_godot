# DEV PRESENTATION SEQUENCING TOOL
# Tunes the King Piece awakening ritual without entering the shipping game flow.

extends Node2D

const PIECE_SCENE := preload("res://scenes/piece.tscn")
const HAND_RIG_SCENE := preload("res://scenes/player_hand_rig.tscn")
const HAND_STYLE := preload("res://assets/arms/player/skeleton_hand_style.tres")
const PreviewContext := preload("res://tools/dev_chess_shared/chess_lab_preview_context.gd")
const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const ActivationProfile := preload("res://scripts/view/chess_king_activation_profile.gd")
const ActivationSequence := preload("res://scripts/view/chess_king_activation_sequence.gd")
const Lightning := preload("res://scripts/view/chess_lightning_2d.gd")
const AuraLabPreset := preload("res://tools/dev_chess_aura/chess_aura_lab_preset.gd")
const ActivationPreset := preload("res://tools/dev_chess_activation/chess_activation_lab_preset.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")
const AURA_PRESET_DIRECTORY := "res://.cache/chess_aura_presets"
const ACTIVATION_PRESET_DIRECTORY := "res://.cache/chess_activation_presets"

@export var activation_sounds: Resource

var aura_profile: ChessAuraProfile
var activation_profile: Resource
var preview_king: PieceView
var preview_hand: ChessHandRig
var hand_sprites: Array[Sprite2D] = []
var hand_connection_anchor: Marker2D
var stone_sprite: Sprite2D
var hand_aura: ChessAura2D
var king_aura: ChessAura2D
var lightning: Node2D
var sequence: Node
var selected_aura_path := ""
var selected_aura_name := "Default Aura"
var selected_aura_mode := Aura.AuraMode.HYBRID
var aura_selector: OptionButton
var activation_selector: OptionButton
var king_selector: OptionButton
var army_selector: OptionButton
var phase_label: Label
var time_label: Label
var pause_button: Button
var hand_offset: SpinBox
var hand_offset_x: SpinBox
var crackle_selector: OptionButton
var crackle_time: SpinBox
var crackle_remove: Button
var crackle_warning: Label
var syncing_crackle_editor := false
var preset_name: LineEdit
var status_label: Label
var overwrite_confirmation: ConfirmationDialog
var publish_confirmation: ConfirmationDialog
var publish_aura_checkbox: CheckBox
var pending_preset: Resource
var pending_path := ""
var profile_controls: Dictionary = {}
var motion_vector_controls: Dictionary = {}
var approach_path_debug: Line2D
var retreat_path_debug: Line2D
var preview_context := PreviewContext.new()
var seat_selector: OptionButton
var loadout_selector: OptionButton


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	aura_profile = AuraProfile.new()
	activation_profile = ActivationProfile.new()
	_build_stage()
	_build_controls()
	_build_sequence()
	_sync_profile_controls()
	_refresh_aura_presets()
	_refresh_activation_presets()
	get_viewport().size_changed.connect(_layout_scale)
	_layout_scale()
	_refresh_playback_labels()
	_refresh_hand_paths()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("10121b"))
	for row in range(4):
		for column in range(8):
			var color := Color("292d3c") if (row + column) % 2 == 0 else Color("1d2130")
			draw_rect(Rect2(Vector2(390 + column * 120, 520 + row * 62), Vector2(120, 62)), color)


func _build_stage() -> void:
	preview_king = PIECE_SCENE.instantiate() as PieceView
	preview_king.position = Vector2(670, 700)
	preview_king.set_model(MinotaurKing.new("white", Vector2i.ZERO))
	add_child(preview_king)
	preview_hand = HAND_RIG_SCENE.instantiate() as ChessHandRig
	add_child(preview_hand)
	preview_context.apply_to_hand(preview_hand)
	preview_hand.position = _hover_position()
	hand_sprites.assign(preview_hand.get_aura_sprites())
	hand_connection_anchor = Marker2D.new()
	hand_connection_anchor.position = preview_hand.get_connection_anchor_position()
	preview_hand.add_child(hand_connection_anchor)

	stone_sprite = Sprite2D.new()
	stone_sprite.name = "GeneratedStoneOverlay"
	stone_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var stone_material := ShaderMaterial.new()
	stone_material.shader = STONE_SHADER
	stone_sprite.material = stone_material
	preview_king.sprite.add_child(stone_sprite)
	_sync_stone_sprite()

	king_aura = Aura.new() as ChessAura2D
	king_aura.profile = aura_profile
	add_child(king_aura)
	king_aura.bind_targets([preview_king.sprite])
	hand_aura = Aura.new() as ChessAura2D
	hand_aura.profile = aura_profile
	add_child(hand_aura)
	hand_aura.bind_targets(hand_sprites)
	lightning = Lightning.new()
	# Back grip < lightning < front grip < arm/palm, so the
	# energy appears to emerge from inside the hand instead of sitting atop it.
	lightning.z_index = ChessHandRig.HAND_OVERLAY_Z
	add_child(lightning)
	approach_path_debug = _make_hand_path_line(Color("3ac8d5"))
	retreat_path_debug = _make_hand_path_line(Color("d58f3a"))


func _layout_scale() -> void:
	var viewport_size := get_viewport_rect().size
	var near_edge := minf(viewport_size.y, viewport_size.x * 0.72)
	var board_scale := ChessBoardView.calculate_world_scale(near_edge)
	preview_king.scale = Vector2.ONE * board_scale
	preview_hand.scale = Vector2.ONE * board_scale * preview_hand.art_scale_multiplier
	_refresh_hand_paths()


func _build_sequence() -> void:
	var players := {}
	for cue in [&"hand_hum", &"king_hum", &"crackle", &"beam", &"resolve"]:
		var player := AudioStreamPlayer.new()
		player.name = String(cue).to_pascal_case()
		player.bus = &"SFX"
		if activation_sounds != null:
			player.stream = activation_sounds.get(cue)
			player.volume_db = float(activation_sounds.get(&"volume_db"))
		add_child(player)
		players[cue] = player
	sequence = ActivationSequence.new()
	add_child(sequence)
	sequence.configure(
		activation_profile,
		preview_hand,
		hand_connection_anchor,
		preview_king.sprite,
		stone_sprite,
		hand_aura,
		king_aura,
		lightning,
		players,
		_activation_rest_position(),
		1.0,
		false
	)
	sequence.phase_changed.connect(func(_phase: int): _refresh_playback_labels())
	sequence.elapsed_changed.connect(func(_seconds: float): _refresh_playback_labels())
	sequence.activation_completed.connect(func():
		pause_button.text = "Pause"
		pause_button.disabled = true
	)
	_refresh_hand_paths()


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(350, 0)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 1010)
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 330
	controls.add_theme_constant_override("separation", 5)
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "King Activation Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	seat_selector = _add_option(controls, "Seat")
	for name in ["Near", "Far"]: seat_selector.add_item(name)
	seat_selector.item_selected.connect(func(index: int):
		preview_context.seat = ChessHandRig.Seat.FAR if index == 1 else ChessHandRig.Seat.NEAR
		_apply_preview_context())
	loadout_selector = _add_option(controls, "Loadout")
	for name in ["Player / Skeleton", "Opponent / Hood"]: loadout_selector.add_item(name)
	loadout_selector.item_selected.connect(func(index: int):
		preview_context.loadout = PreviewContext.Loadout.OPPONENT if index == 1 else PreviewContext.Loadout.PLAYER
		_apply_preview_context())
	aura_selector = _add_option(controls, "Aura Profile")
	aura_selector.item_selected.connect(_load_selected_aura)
	activation_selector = _add_option(controls, "Ritual Profile")
	activation_selector.item_selected.connect(_load_selected_activation)
	king_selector = _add_option(controls, "King")
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"king"):
		var definition := ChessPieceCatalog.get_definition(type_id)
		king_selector.add_item(definition.get("name", str(type_id)))
		king_selector.set_item_metadata(king_selector.item_count - 1, type_id)
		if type_id == &"minotaur_king": king_selector.select(king_selector.item_count - 1)
	king_selector.item_selected.connect(func(_index: int): _update_king())
	army_selector = _add_option(controls, "Army")
	for name in ["White", "Black"]: army_selector.add_item(name)
	army_selector.item_selected.connect(func(_index: int): _update_king())
	hand_offset_x = _add_spin(controls, "Hand hover X", -900.0, 900.0, 1.0, activation_profile.hand_hover_offset.x, func(value: float):
		activation_profile.hand_hover_offset.x = value
		if sequence != null:
			sequence.base_hand_position = _hover_position()
			sequence.restart(false)
		_refresh_hand_paths()
	)
	hand_offset = _add_spin(controls, "Hand hover Y", -900.0, 900.0, 1.0, activation_profile.hand_hover_offset.y, func(value: float):
		activation_profile.hand_hover_offset.y = value
		if sequence != null:
			sequence.base_hand_position = _hover_position()
			sequence.restart(false)
		_refresh_hand_paths()
	)

	var playback := HBoxContainer.new()
	controls.add_child(playback)
	for entry in [
		{"name": "Play", "call": _play_sequence},
		{"name": "Restart", "call": _restart_sequence},
		{"name": "Next Phase", "call": func(): sequence.advance_to_next_phase()},
	]:
		var button := Button.new()
		button.text = entry["name"]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry["call"])
		playback.add_child(button)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.disabled = true
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_toggle_pause)
	playback.add_child(pause_button)
	var speed := _add_option(controls, "Playback Speed")
	for entry in [{"name": "Ultra Slow", "value": 0.125}, {"name": "Slow", "value": 0.5}, {"name": "Normal", "value": 1.0}, {"name": "Fast", "value": 2.0}]:
		speed.add_item(entry["name"])
		speed.set_item_metadata(speed.item_count - 1, entry["value"])
	speed.select(2)
	speed.item_selected.connect(func(index: int): sequence.set_playback_speed(float(speed.get_item_metadata(index))))
	phase_label = Label.new()
	time_label = Label.new()
	controls.add_child(phase_label)
	controls.add_child(time_label)
	controls.add_child(HSeparator.new())
	_add_profile_spin(controls, &"approach_duration", "Approach time", 0.01, 4.0, 0.01)
	_add_profile_spin(controls, &"approach_settle_duration", "Approach settle", 0.0, 2.0, 0.01)
	_add_profile_vector(controls, &"approach_departure_handle", "Approach departure")
	_add_profile_vector(controls, &"approach_arrival_handle", "Approach arrival")
	var path_toggle := CheckButton.new()
	path_toggle.text = "Show hand entrance/exit paths"
	path_toggle.toggled.connect(func(value: bool):
		approach_path_debug.visible = value
		retreat_path_debug.visible = value
		_refresh_hand_paths()
	)
	controls.add_child(path_toggle)

	_add_profile_spin(controls, &"invocation_duration", "Invocation", 0.05, 3.0, 0.01)
	_add_profile_spin(controls, &"response_duration", "Response", 0.05, 2.0, 0.01)
	_add_profile_spin(controls, &"buildup_duration", "Buildup", 0.1, 5.0, 0.01)
	_add_profile_spin(controls, &"climax_duration", "Climax", 0.05, 2.0, 0.01)
	_add_profile_spin(controls, &"afterimage_duration", "Afterimage", 0.05, 4.0, 0.01)
	_add_profile_spin(controls, &"aura_release_duration", "Aura release", 0.05, 8.0, 0.01)
	_build_crackle_timeline_controls(controls)
	_add_profile_spin(controls, &"crackle_width", "Crackle width", 1, 20, 0.5)
	_add_profile_spin(controls, &"crackle_hand_shift_distance", "Crackle hand shift", 0, 240, 1)
	_add_profile_spin(controls, &"crackle_hand_hold_duration", "Crackle hand hold", 0, 0.5, 0.01)
	_add_profile_spin(controls, &"crackle_hand_return_duration", "Hand return time", 0.01, 1, 0.01)
	_add_profile_spin(controls, &"beam_width", "Beam width", 1, 40, 0.5)
	_add_profile_spin(controls, &"climax_beam_count", "Climax beams", 1, 12, 1)
	_add_profile_spin(controls, &"climax_hand_shift_distance", "Climax hand shift", 0, 240, 1)
	_add_profile_spin(controls, &"climax_hand_return_duration", "Climax hand return", 0.01, 2, 0.01)
	_add_profile_spin(controls, &"post_climax_retreat_delay", "Retreat delay", 0.0, 4.0, 0.01)
	_add_profile_spin(controls, &"retreat_duration", "Retreat time", 0.01, 4.0, 0.01)
	_add_profile_vector(controls, &"retreat_departure_handle", "Retreat departure")
	_add_profile_vector(controls, &"retreat_arrival_handle", "Retreat arrival")
	_add_profile_spin(controls, &"lightning_displacement", "Lightning bend", 0, 80, 1)
	_add_profile_spin(controls, &"lightning_curve_max", "Base curve", 0, 160, 1)
	_add_profile_spin(controls, &"lightning_checker_size", "Checker size", 1, 32, 1)
	_add_profile_spin(controls, &"rift_edge_roughness", "Rift edge roughness", 0, 24, 0.5)
	_add_profile_spin(controls, &"beam_branch_count", "Beam branches", 0, 8, 1)
	_add_profile_spin(controls, &"impact_bolt_count", "Hit bolts", 0, 24, 1)
	_add_profile_spin(controls, &"impact_radius_min", "Hit radius min", 0, 160, 1)
	_add_profile_spin(controls, &"impact_radius_max", "Hit radius max", 0, 240, 1)
	_add_profile_spin(controls, &"impact_bolt_width", "Hit bolt width", 1, 16, 0.5)
	_add_profile_spin(controls, &"tremor_interval", "Tremor rate", 0.02, 0.5, 0.01)
	_add_profile_spin(controls, &"tremor_max_pixels", "Tremor pixels", 0, 8, 1)
	_add_profile_spin(controls, &"tremor_ramp_exponent", "Tremor ramp curve", 0.2, 3, 0.05)
	_add_profile_spin(controls, &"final_density_multiplier", "Density ramp", 0, 4, 0.05)
	_add_profile_spin(controls, &"final_speed_multiplier", "Speed ramp", 0, 4, 0.05)
	_add_profile_spin(controls, &"burst_multiplier", "Final burst", 0, 8, 0.1)
	_add_profile_spin(controls, &"resting_aura_power", "Resting silhouette", 0, 1, 0.01)
	_add_profile_spin(controls, &"resting_particle_power", "Resting particles", 0, 1, 0.01)
	_add_profile_spin(controls, &"resting_density_multiplier", "Resting density", 0, 4, 0.01)
	_add_profile_spin(controls, &"resting_speed_multiplier", "Resting speed", 0, 2, 0.01)
	_add_profile_spin(controls, &"random_seed", "Random seed", 0, 999999, 1)
	controls.add_child(HSeparator.new())
	publish_aura_checkbox = CheckBox.new()
	publish_aura_checkbox.text = "Also publish selected King's Aura"
	publish_aura_checkbox.tooltip_text = "When enabled, also replaces the selected King type's universal Aura for both armies."
	controls.add_child(publish_aura_checkbox)
	var save_row := HBoxContainer.new()
	controls.add_child(save_row)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "Ritual profile name"
	preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(preset_name)
	var save := Button.new()
	save.text = "Save Ritual"
	save.pressed.connect(_request_save_activation)
	save_row.add_child(save)
	var publish := Button.new()
	publish.text = "Publish to Game"
	publish.tooltip_text = "Updates the shared ritual. Optionally publishes the selected King type's Aura."
	publish.pressed.connect(_request_publish_activation)
	save_row.add_child(publish)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)
	overwrite_confirmation = ConfirmationDialog.new()
	overwrite_confirmation.confirmed.connect(_write_pending_activation)
	add_child(overwrite_confirmation)
	publish_confirmation = ConfirmationDialog.new()
	publish_confirmation.confirmed.connect(_publish_activation)
	add_child(publish_confirmation)


func _add_option(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func _add_spin(parent: Control, label_text: String, minimum: float, maximum: float, step: float, value: float, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(callback)
	row.add_child(spin)
	return spin


func _add_profile_spin(parent: Control, property_name: StringName, label: String, minimum: float, maximum: float, step: float) -> void:
	profile_controls[property_name] = _add_spin(parent, label, minimum, maximum, step, float(activation_profile.get(property_name)), func(value: float):
		activation_profile.set(property_name, int(value) if step >= 1.0 else value)
		if property_name == &"buildup_duration" and is_instance_valid(crackle_selector):
			_refresh_crackle_editor(crackle_selector.selected)
		if sequence != null: sequence.restart(false)
		_refresh_hand_paths()
	)


func _add_profile_vector(parent: Control, property_name: StringName, label: String) -> void:
	for component in ["x", "y"]:
		var key := StringName("%s:%s" % [property_name, component])
		motion_vector_controls[key] = _add_spin(parent, "%s %s" % [label, component.to_upper()], -800.0, 800.0, 1.0, 0.0, func(value: float):
			var vector: Vector2 = activation_profile.get(property_name)
			if component == "x": vector.x = value
			else: vector.y = value
			activation_profile.set(property_name, vector)
			if sequence != null: sequence.restart(false)
			_refresh_hand_paths()
		)


func _build_crackle_timeline_controls(parent: Control) -> void:
	crackle_selector = _add_option(parent, "Buildup Crackle")
	crackle_selector.item_selected.connect(func(index: int): _select_crackle(index))
	crackle_time = _add_spin(parent, "Time from buildup", 0.0, 30.0, 0.01, 0.0, func(value: float): _edit_crackle_time(value))
	crackle_time.allow_greater = true
	var buttons := HBoxContainer.new()
	parent.add_child(buttons)
	var add_button := Button.new()
	add_button.text = "Add Crackle"
	add_button.focus_mode = Control.FOCUS_NONE
	add_button.pressed.connect(_add_buildup_crackle)
	buttons.add_child(add_button)
	crackle_remove = Button.new()
	crackle_remove.text = "Remove Selected"
	crackle_remove.focus_mode = Control.FOCUS_NONE
	crackle_remove.pressed.connect(_remove_selected_crackle)
	buttons.add_child(crackle_remove)
	crackle_warning = Label.new()
	crackle_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(crackle_warning)
	_refresh_crackle_editor(0)


func _refresh_crackle_editor(preferred_index := 0) -> void:
	if not is_instance_valid(crackle_selector):
		return
	syncing_crackle_editor = true
	var times := _sorted_crackle_times()
	activation_profile.buildup_crackle_times = times
	crackle_selector.clear()
	if times.is_empty():
		crackle_selector.add_item("No buildup crackles")
		crackle_selector.set_item_disabled(0, true)
		crackle_selector.disabled = true
		crackle_time.editable = false
		crackle_time.set_value_no_signal(0.0)
		crackle_remove.disabled = true
	else:
		crackle_selector.disabled = false
		crackle_time.editable = true
		crackle_remove.disabled = false
		for index in range(times.size()):
			var suffix := " [outside buildup]" if times[index] >= activation_profile.buildup_duration else ""
			crackle_selector.add_item("Crackle %d — %.2fs%s" % [index + 1, times[index], suffix])
		var selected_index := clampi(preferred_index, 0, times.size() - 1)
		crackle_selector.select(selected_index)
		crackle_time.set_value_no_signal(times[selected_index])
	_update_crackle_warning(times)
	syncing_crackle_editor = false


func _select_crackle(index: int) -> void:
	if syncing_crackle_editor:
		return
	var times: PackedFloat32Array = activation_profile.buildup_crackle_times
	if index >= 0 and index < times.size():
		crackle_time.set_value_no_signal(times[index])
	_update_crackle_warning(times)


func _edit_crackle_time(value: float) -> void:
	if syncing_crackle_editor or crackle_selector.disabled:
		return
	var times: PackedFloat32Array = activation_profile.buildup_crackle_times.duplicate()
	var index := crackle_selector.selected
	if index < 0 or index >= times.size():
		return
	var edited_time := maxf(value, 0.0)
	times[index] = edited_time
	times.sort()
	activation_profile.buildup_crackle_times = times
	var new_index := 0
	for candidate in range(times.size()):
		if is_equal_approx(times[candidate], edited_time):
			new_index = candidate
			break
	_refresh_crackle_editor(new_index)
	sequence.restart(false)


func _add_buildup_crackle() -> void:
	var times := _sorted_crackle_times()
	var new_time := 0.30 if times.is_empty() else times[times.size() - 1] + 0.12
	times.append(new_time)
	times.sort()
	activation_profile.buildup_crackle_times = times
	_refresh_crackle_editor(times.size() - 1)
	sequence.restart(false)


func _remove_selected_crackle() -> void:
	var times: PackedFloat32Array = activation_profile.buildup_crackle_times.duplicate()
	var index := crackle_selector.selected
	if index < 0 or index >= times.size():
		return
	times.remove_at(index)
	activation_profile.buildup_crackle_times = times
	_refresh_crackle_editor(mini(index, times.size() - 1))
	sequence.restart(false)


func _sorted_crackle_times() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for authored_time in activation_profile.buildup_crackle_times:
		if authored_time >= 0.0:
			result.append(authored_time)
	result.sort()
	return result


func _update_crackle_warning(times: PackedFloat32Array) -> void:
	var overflow_count := 0
	for authored_time in times:
		if authored_time >= activation_profile.buildup_duration:
			overflow_count += 1
	if overflow_count > 0:
		crackle_warning.text = "%d crackle(s) fall outside the %.2fs buildup. They remain saved but will not fire." % [overflow_count, activation_profile.buildup_duration]
		crackle_warning.add_theme_color_override("font_color", Color("ffb36b"))
	else:
		crackle_warning.text = "Times are measured from the beginning of buildup."
		crackle_warning.add_theme_color_override("font_color", Color("aeb8d0"))


func _play_sequence() -> void:
	sequence.play()
	pause_button.disabled = false
	pause_button.text = "Pause"


func _restart_sequence() -> void:
	sequence.restart(true)
	pause_button.disabled = false
	pause_button.text = "Pause"


func _toggle_pause() -> void:
	if sequence.running:
		sequence.pause()
		pause_button.text = "Resume"
	else:
		sequence.resume()
		pause_button.text = "Pause"


func _refresh_playback_labels() -> void:
	phase_label.text = "Phase: %s" % sequence.phase_name()
	time_label.text = "Time: %.2f / %.2f" % [sequence.elapsed, activation_profile.total_duration()]


func _update_king() -> void:
	var type_id: StringName = king_selector.get_item_metadata(king_selector.selected)
	var color := "black" if army_selector.selected == 1 else "white"
	preview_king.set_model(ChessPieceCatalog.create_piece(type_id, color, Vector2i.ZERO))
	_sync_stone_sprite()
	sequence.restart(false)


func _sync_stone_sprite() -> void:
	stone_sprite.texture = preview_king.sprite.texture
	stone_sprite.centered = preview_king.sprite.centered
	stone_sprite.offset = preview_king.sprite.offset


func _refresh_aura_presets() -> void:
	aura_selector.clear()
	aura_selector.add_item("Default Aura")
	aura_selector.set_item_metadata(0, "")
	for entry in _discover_presets(AURA_PRESET_DIRECTORY, AuraLabPreset):
		aura_selector.add_item(entry["name"])
		aura_selector.set_item_metadata(aura_selector.item_count - 1, entry["path"])


func _load_selected_aura(index: int) -> void:
	var path: String = aura_selector.get_item_metadata(index)
	if path.is_empty():
		selected_aura_path = ""
		selected_aura_name = "Default Aura"
		selected_aura_mode = Aura.AuraMode.HYBRID
		_apply_aura_profile(AuraProfile.new(), selected_aura_mode)
		return
	var resource := ResourceLoader.load(path, "ChessAuraLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or resource.get_script() != AuraLabPreset or not resource.is_supported():
		_set_status("Could not load Aura preset.", true)
		return
	selected_aura_path = path
	selected_aura_name = resource.display_name
	selected_aura_mode = resource.aura_mode
	_apply_aura_profile(resource.aura_profile, selected_aura_mode)


func _apply_aura_profile(source: Resource, mode: int) -> void:
	_copy_properties(source, aura_profile)
	hand_aura.set_mode(mode)
	king_aura.set_mode(mode)
	sequence.restart(false)


func _request_save_activation() -> void:
	var display_name := preset_name.text.strip_edges()
	var stem := AuraLabPreset.safe_file_stem(display_name)
	if stem.is_empty():
		_set_status("Enter a valid ritual profile name.", true)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ACTIVATION_PRESET_DIRECTORY))
	pending_preset = _capture_activation(display_name)
	pending_path = "%s/%s.tres" % [ACTIVATION_PRESET_DIRECTORY, stem]
	if FileAccess.file_exists(pending_path):
		overwrite_confirmation.dialog_text = "Replace '%s'?" % display_name
		overwrite_confirmation.popup_centered()
	else:
		_write_pending_activation()


func _capture_activation(display_name: String) -> Resource:
	var result: Resource = ActivationPreset.new()
	result.display_name = display_name
	result.activation_profile = activation_profile.duplicate(true)
	result.aura_preset_path = selected_aura_path
	result.aura_preset_name = selected_aura_name
	result.aura_snapshot = aura_profile.duplicate(true)
	result.aura_mode = selected_aura_mode
	result.king_type_id = king_selector.get_item_metadata(king_selector.selected)
	result.army_color = "black" if army_selector.selected == 1 else "white"
	return result


func _write_pending_activation() -> void:
	if pending_preset == null: return
	var error := ResourceSaver.save(pending_preset, pending_path)
	if error != OK:
		_set_status("Save failed with error %d." % error, true)
		return
	var saved_path := pending_path
	pending_preset = null
	pending_path = ""
	_refresh_activation_presets(saved_path)
	_set_status("Saved to %s" % ProjectSettings.globalize_path(saved_path))


func _request_publish_activation() -> void:
	var type_id: StringName = king_selector.get_item_metadata(king_selector.selected)
	var aura_note := ""
	if publish_aura_checkbox.button_pressed:
		aura_note = "\n\nThe current Aura will also replace the universal %s Aura for both armies." % ChessPieceCatalog.get_definition(type_id).get("name", str(type_id))
	publish_confirmation.dialog_text = "Publish the current activation ritual to the shared game profile?\n\nThe magical movement profile will be preserved.%s" % aura_note
	publish_confirmation.popup_centered()


func _publish_activation(target_path := RuntimePublisher.KING_RUNTIME_PATH, aura_target_path := RuntimePublisher.AURA_RUNTIME_PATH) -> Dictionary:
	if publish_aura_checkbox.button_pressed:
		var type_id: StringName = king_selector.get_item_metadata(king_selector.selected)
		var validation_error := RuntimePublisher.validate_aura_profile(type_id, aura_profile)
		if not validation_error.is_empty():
			var invalid_result := {"ok": false, "message": validation_error}
			_set_status(invalid_result.message, true)
			return invalid_result
	var result: Dictionary = RuntimePublisher.publish_activation_profile(activation_profile, target_path)
	if result.ok and publish_aura_checkbox.button_pressed:
		var type_id: StringName = king_selector.get_item_metadata(king_selector.selected)
		var aura_result: Dictionary = RuntimePublisher.publish_aura_profile(type_id, aura_profile, selected_aura_mode, aura_target_path)
		if aura_result.ok:
			result.message = "%s\n%s" % [result.message, aura_result.message]
		else:
			result = aura_result
	_set_status(result.message, not result.ok)
	return result


func _refresh_activation_presets(selected_path := "") -> void:
	activation_selector.clear()
	activation_selector.add_item("Unsaved defaults")
	activation_selector.set_item_metadata(0, "")
	var selected_index := 0
	for entry in _discover_presets(ACTIVATION_PRESET_DIRECTORY, ActivationPreset):
		activation_selector.add_item(entry["name"])
		var index := activation_selector.item_count - 1
		activation_selector.set_item_metadata(index, entry["path"])
		if entry["path"] == selected_path:
			selected_index = index
	activation_selector.select(selected_index)


func _load_selected_activation(index: int) -> void:
	if index <= 0: return
	var path: String = activation_selector.get_item_metadata(index)
	var resource := ResourceLoader.load(path, "ChessActivationLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or resource.get_script() != ActivationPreset or not resource.is_supported():
		_set_status("Could not load ritual profile.", true)
		return
	_copy_properties(resource.activation_profile, activation_profile)
	selected_aura_path = resource.aura_preset_path
	selected_aura_name = resource.aura_preset_name
	selected_aura_mode = resource.aura_mode
	var aura_source: Resource = resource.aura_snapshot
	if not resource.aura_preset_path.is_empty() and FileAccess.file_exists(resource.aura_preset_path):
		var current := ResourceLoader.load(resource.aura_preset_path, "ChessAuraLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
		if current != null and current.get_script() == AuraLabPreset and current.is_supported():
			aura_source = current.aura_profile
			selected_aura_mode = current.aura_mode
			selected_aura_name = current.display_name
			selected_aura_path = resource.aura_preset_path
	_apply_aura_profile(aura_source, selected_aura_mode)
	_select_aura_preset(selected_aura_path)
	_select_king(resource.king_type_id)
	army_selector.select(1 if resource.army_color == "black" else 0)
	_update_king()
	_sync_profile_controls()
	preset_name.text = resource.display_name
	_set_status("Loaded '%s'." % resource.display_name)


func _discover_presets(directory_path: String, expected_script: Script) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(directory_path)
	if directory == null: return result
	directory.list_dir_begin()
	var file := directory.get_next()
	while not file.is_empty():
		if not directory.current_is_dir() and file.get_extension().to_lower() == "tres":
			var path := "%s/%s" % [directory_path, file]
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource != null and resource.get_script() == expected_script and resource.is_supported():
				result.append({"name": resource.display_name, "path": path})
		file = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return result


func _copy_properties(source: Resource, destination: Resource) -> void:
	for property in source.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			destination.set(property["name"], source.get(property["name"]))


func _sync_profile_controls() -> void:
	for property_name in profile_controls:
		(profile_controls[property_name] as SpinBox).set_value_no_signal(float(activation_profile.get(property_name)))
	for key in motion_vector_controls:
		var component := String(key).get_slice(":", 1)
		var property_name := StringName(String(key).get_slice(":", 0))
		var vector: Vector2 = activation_profile.get(property_name)
		(motion_vector_controls[key] as SpinBox).set_value_no_signal(vector.x if component == "x" else vector.y)
	hand_offset_x.set_value_no_signal(activation_profile.hand_hover_offset.x)
	hand_offset.set_value_no_signal(activation_profile.hand_hover_offset.y)
	if sequence != null:
		sequence.base_hand_position = _hover_position()
	_refresh_crackle_editor(0)
	_refresh_hand_paths()


func _activation_rest_position() -> Vector2:
	return preview_hand._offscreen_rest_position(maxf(absf(preview_hand.scale.x), 0.01))


func _hover_position() -> Vector2:
	return preview_king.position + preview_context.hover_offset(activation_profile.hand_hover_offset)


func _apply_preview_context() -> void:
	var hand_silhouette := hand_aura.silhouette_power
	var hand_particles := hand_aura.particle_power
	hand_aura.clear_targets()
	preview_context.apply_to_hand(preview_hand)
	hand_connection_anchor.position = preview_hand.get_connection_anchor_position()
	hand_aura.bind_targets(preview_hand.get_aura_sprites())
	hand_aura.set_mode(selected_aura_mode)
	hand_aura.set_silhouette_power(hand_silhouette)
	hand_aura.set_particle_power(hand_particles)
	_layout_scale()
	if sequence != null:
		sequence.base_hand_position = _hover_position()
		sequence.hand_rest_position = _activation_rest_position()
		sequence.mirror_hand_motion = preview_context.seat == ChessHandRig.Seat.FAR
		sequence.restart(false)
	_refresh_hand_paths()


func _make_hand_path_line(color: Color) -> Line2D:
	var line := Line2D.new()
	line.visible = false
	line.width = 2.0
	line.default_color = color
	line.z_index = 20
	add_child(line)
	return line


func _refresh_hand_paths() -> void:
	if not is_instance_valid(approach_path_debug) or not is_instance_valid(retreat_path_debug): return
	if sequence != null:
		sequence.hand_rest_position = _activation_rest_position()
		sequence.mirror_hand_motion = preview_context.seat == ChessHandRig.Seat.FAR
	var rest := _activation_rest_position()
	var hover := _hover_position()
	if sequence != null:
		sequence.base_hand_position = hover
		if sequence.current_phase == sequence.Phase.RESET:
			preview_hand.position = rest
			preview_hand.visible = false
	approach_path_debug.points = _sample_hand_path(rest, hover, activation_profile.approach_departure_handle, activation_profile.approach_arrival_handle)
	retreat_path_debug.points = _sample_hand_path(hover, rest, activation_profile.retreat_departure_handle, activation_profile.retreat_arrival_handle)


func _sample_hand_path(start: Vector2, finish: Vector2, departure: Vector2, arrival: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var mirror := -1.0 if preview_context.seat == ChessHandRig.Seat.FAR else 1.0
	var control_a := start + Vector2(departure.x * mirror, departure.y)
	var control_b := finish + Vector2(arrival.x * mirror, arrival.y)
	for index in range(33):
		points.append(start.bezier_interpolate(control_a, control_b, finish, index / 32.0))
	return points


func _select_king(type_id: StringName) -> void:
	for index in range(king_selector.item_count):
		if king_selector.get_item_metadata(index) == type_id:
			king_selector.select(index)
			return


func _select_aura_preset(path: String) -> void:
	for index in range(aura_selector.item_count):
		if String(aura_selector.get_item_metadata(index)) == path:
			aura_selector.select(index)
			return
	aura_selector.select(0)


func _set_status(message: String, error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("ff7777") if error else Color("8ee6a2"))
