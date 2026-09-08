extends Node2D

const GAME_SCENE := preload("res://scenes/chess_game.tscn")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const PresentationPolicy := preload("res://scripts/view/chess_presentation_policy.gd")
const CENTER := Vector2i(4, 4)

var game: ChessGame
var model: ChessBoardModel
var board: ChessBoardView
var adapter: ChessPresentationAdapter
var profile: ChessKingCooldownPresentationProfile
var king_type := &"arakne_king"
var cooldown := 5
var awakened := true
var selected := false
var status: Label
var count_label: Label
var property_controls: Dictionary = {}


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	profile = _load_profile()
	_build_stage()
	_build_controls()
	await get_tree().process_frame
	_rebuild_fixture()


func _build_stage() -> void:
	game = GAME_SCENE.instantiate() as ChessGame
	game.play_opening_presentation = false
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	add_child(game)
	model = game.model
	board = game.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	adapter = game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	adapter.cooldown_presentation_profile = profile
	game.get_node("UI").visible = false
	game.controller.is_input_locked = true


func _build_controls() -> void:
	var layer := CanvasLayer.new(); layer.layer = 500; add_child(layer)
	var panel := PanelContainer.new(); panel.position = Vector2(12, 12); panel.custom_minimum_size = Vector2(390, 0); layer.add_child(panel)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(390, 760); panel.add_child(scroll)
	var controls := VBoxContainer.new(); controls.custom_minimum_size.x = 365; controls.add_theme_constant_override("separation", 4); scroll.add_child(controls)
	var title := Label.new(); title.text = "King Cooldown Lab"; title.add_theme_font_size_override("font_size", 22); controls.add_child(title)
	var help := Label.new(); help.text = "Tune the universal diegetic cooldown, then exercise authoritative-looking state changes and movement trailing."; help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(help)
	var king_selector := _option(controls, "King", [])
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"king"):
		king_selector.add_item(ChessPieceCatalog.get_definition(type_id).get("name", str(type_id)))
		king_selector.set_item_metadata(king_selector.item_count - 1, type_id)
		if type_id == king_type: king_selector.select(king_selector.item_count - 1)
	king_selector.item_selected.connect(func(index: int): king_type = king_selector.get_item_metadata(index); _rebuild_fixture())
	count_label = Label.new(); controls.add_child(count_label); _refresh_count_label()
	var count_row := HBoxContainer.new(); controls.add_child(count_row)
	_button(count_row, "− Tick", func(): _set_cooldown(maxi(cooldown - 1, 0)))
	_button(count_row, "+ Add", func(): _set_cooldown(cooldown + 1))
	_button(count_row, "Ready", func(): _set_cooldown(0))
	_button(controls, "Rapid 5 → 2 → 4", _rapid_reconcile)
	_button(controls, "Move King / Trail Motes", _move_king)
	var awake_toggle := CheckButton.new(); awake_toggle.text = "King awakened"; awake_toggle.button_pressed = true; awake_toggle.toggled.connect(func(value): awakened = value; _presentation().set_awakened(value)); controls.add_child(awake_toggle)
	var selected_toggle := CheckButton.new(); selected_toggle.text = "King selected"; selected_toggle.toggled.connect(func(value): selected = value; _presentation().set_selected(value)); controls.add_child(selected_toggle)
	var targeting_toggle := CheckButton.new(); targeting_toggle.text = "Ability targeting"; targeting_toggle.toggled.connect(func(value): _presentation().set_targeting(value)); controls.add_child(targeting_toggle)
	var speed := _option(controls, "Playback speed", ["Normal", "Slow", "Ultra Slow"]); speed.item_selected.connect(_set_speed)
	_add_heading(controls, "Motes and orbit")
	_spin(controls, &"mote_size", "Mote size", 1, 16, 0.5); _spin(controls, &"mote_opacity", "Mote opacity", 0, 1, 0.01)
	_vector(controls, &"anchor_offset", "Anchor offset", -150, 150); _vector(controls, &"orbit_radius", "Orbit radius", 0, 180)
	_spin(controls, &"orbit_speed", "Orbit speed", -3, 3, 0.01); _spin(controls, &"hover_amplitude", "Hover amplitude", 0, 20, 0.25); _spin(controls, &"hover_frequency", "Hover frequency", 0, 8, 0.05)
	_spin(controls, &"hover_variation", "Hover variation", 0, 1, 0.01); _spin(controls, &"motes_per_ring", "Motes per ring", 1, 24, 1); _spin(controls, &"ring_spacing", "Ring spacing", 0, 80, 1)
	_add_heading(controls, "Following and formation")
	_spin(controls, &"follow_base_speed", "Base speed", 0, 500, 1); _spin(controls, &"follow_distance_gain", "Distance gain", 0, 20, 0.05); _spin(controls, &"follow_max_speed", "Maximum speed", 1, 1200, 1); _spin(controls, &"follow_acceleration", "Acceleration", 1, 2400, 1)
	_spin(controls, &"arrival_smoothing", "Arrival smoothing", 0, 40, 0.1); _spin(controls, &"formation_angular_smoothing", "Formation smoothing", 0, 20, 0.1)
	_add_heading(controls, "Absorption")
	_spin(controls, &"release_duration", "Release duration", 0.01, 3, 0.01); _spin(controls, &"absorption_duration", "Absorb duration", 0.01, 3, 0.01); _spin(controls, &"absorption_stagger", "Absorb stagger", 0, 1, 0.01); _spin(controls, &"absorption_curve_strength", "Absorb curve strength", 0, 2, 0.01); _spin(controls, &"absorption_outward_distance", "Absorb outward reach", 0, 200, 1); _spin(controls, &"pulse_scale", "King pulse scale", 1, 1.5, 0.005); _spin(controls, &"pulse_duration", "King pulse duration", 0.01, 1.5, 0.01)
	_add_heading(controls, "Ready aura and orb")
	_spin(controls, &"ready_silhouette_power", "Ready silhouette", 0, 1, 0.01); _spin(controls, &"ready_particle_power", "Ready particles", 0, 1, 0.01); _spin(controls, &"ready_density_multiplier", "Ready density", 0, 4, 0.05); _spin(controls, &"ready_speed_multiplier", "Ready speed", 0, 4, 0.05); _spin(controls, &"ready_brightening_intensity", "Brightening", 0, 0.5, 0.01); _spin(controls, &"ready_brightening_period", "Brightening period", 0.1, 12, 0.1)
	_spin(controls, &"ready_brightening_fraction", "Brightening fraction", 0.05, 1, 0.01)
	_vector(controls, &"selection_orb_offset", "Orb offset", -150, 150); _spin(controls, &"selection_orb_size", "Orb size", 2, 64, 0.5); _spin(controls, &"selection_orb_opacity", "Orb opacity", 0, 1, 0.01); _spin(controls, &"selection_orb_speed", "Orb speed", 0, 8, 0.05)
	_add_heading(controls, "Audio levels")
	_spin(controls, &"charge_volume_db", "Charge volume dB", -60, 6, 0.5); _spin(controls, &"absorption_volume_db", "Absorb volume dB", -60, 6, 0.5); _spin(controls, &"completion_volume_db", "Completion volume dB", -60, 6, 0.5); _spin(controls, &"selection_volume_db", "Selection volume dB", -60, 6, 0.5)
	_button(controls, "Reset Runtime Values", _reset_profile)
	_button(controls, "Publish Universal Cooldown", _publish)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.add_child(status)


func _rebuild_fixture() -> void:
	var position := ChessPosition.new()
	var king := ChessPieceCatalog.create_piece(king_type, "white", CENTER) as KingPiece
	king.set_cooldown(cooldown)
	position.pieces.append(king.capture_piece_state())
	model.load_position(position)
	var presentation := _presentation()
	if presentation != null:
		presentation.set_awakened(awakened)
		presentation.set_selected(selected)
	_refresh_count_label()


func _set_cooldown(value: int) -> void:
	cooldown = maxi(value, 0)
	var king := model.get_king("white")
	if king != null: king.set_cooldown(cooldown)
	_refresh_count_label()


func _rapid_reconcile() -> void:
	_set_cooldown(5); await get_tree().create_timer(0.12).timeout
	_set_cooldown(2); await get_tree().create_timer(0.12).timeout
	_set_cooldown(4)


func _move_king() -> void:
	var king := model.get_king("white")
	var piece := adapter.get_piece_view(king) as PieceView
	if not is_instance_valid(piece): return
	var target := board.grid_to_screen(2, 6) if piece.position.distance_to(board.grid_to_screen(2, 6)) > 2.0 else board.grid_to_screen(CENTER.x, CENTER.y)
	var tween := create_tween(); tween.tween_property(piece, "position", target, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _presentation() -> ChessKingCooldownPresentation:
	var magic := adapter.get_king_magic_controller("white")
	return magic.cooldown_presentation if magic != null else null


func _refresh_live() -> void:
	var presentation := _presentation()
	if presentation != null: presentation.refresh_profile()


func _set_speed(index: int) -> void:
	adapter.set_presentation_speed([PresentationPolicy.Speed.NORMAL, PresentationPolicy.Speed.SLOW, PresentationPolicy.Speed.ULTRA_SLOW][clampi(index, 0, 2)])


func _reset_profile() -> void:
	profile = _load_profile(); adapter.cooldown_presentation_profile = profile; _sync_controls(); _rebuild_fixture(); status.text = "Reloaded published runtime values."


func _publish() -> void:
	var result := RuntimePublisher.publish_cooldown_presentation(profile); status.text = result.message


func _load_profile() -> ChessKingCooldownPresentationProfile:
	var loaded := ResourceLoader.load(RuntimePublisher.COOLDOWN_PRESENTATION_RUNTIME_PATH, "ChessKingCooldownPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingCooldownPresentationProfile
	return loaded.duplicate(true) as ChessKingCooldownPresentationProfile if loaded != null else ChessKingCooldownPresentationProfile.new()


func _refresh_count_label() -> void:
	if count_label != null: count_label.text = "Cooldown: %d%s" % [cooldown, " (READY)" if cooldown == 0 else ""]


func _spin(parent: Control, property: StringName, label_text: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 190; row.add_child(label)
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.value = float(profile.get(property)); spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spin)
	spin.value_changed.connect(func(value: float): profile.set(property, int(round(value)) if typeof(profile.get(property)) == TYPE_INT else value); _refresh_live())
	property_controls[property] = spin


func _vector(parent: Control, property: StringName, label_text: String, minimum: float, maximum: float) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 150; row.add_child(label)
	for component in range(2):
		var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = 1; spin.value = Vector2(profile.get(property))[component]; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(spin)
		spin.value_changed.connect(func(value: float): var current: Vector2 = profile.get(property); current[component] = value; profile.set(property, current); _refresh_live())
	property_controls[property] = row


func _sync_controls() -> void:
	for property in property_controls:
		var control: Control = property_controls[property]
		if control is SpinBox: (control as SpinBox).set_value_no_signal(float(profile.get(property)))
		elif control is HBoxContainer:
			var value: Vector2 = profile.get(property); var spins := control.find_children("", "SpinBox", false, false)
			for index in range(mini(2, spins.size())): (spins[index] as SpinBox).set_value_no_signal(value[index])


func _option(parent: Control, label_text: String, entries: Array) -> OptionButton:
	var row := HBoxContainer.new(); parent.add_child(row); var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 150; row.add_child(label); var option := OptionButton.new(); option.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(option)
	for entry in entries: option.add_item(entry)
	return option


func _button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.pressed.connect(callback); parent.add_child(button); return button


func _add_heading(parent: Control, value: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 7.0
	parent.add_child(spacer)
	var separator := HSeparator.new()
	separator.modulate = Color(0.72, 0.58, 0.34, 0.8)
	parent.add_child(separator)
	var label := Label.new()
	label.text = value.to_upper()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.96, 0.79, 0.45))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
