# DEV PRESENTATION SEQUENCING TOOL
# Tunes the player's full-army board setup ceremony without entering game flow.

extends Node2D

const HAND_STYLE := preload("res://assets/arms/player/skeleton_hand_style.tres")
const ActivationPreset := preload("res://tools/dev_chess_activation/chess_activation_lab_preset.gd")
const SetupPreset := preload("res://tools/dev_chess_setup/chess_setup_lab_preset.gd")
const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const ActivationProfile := preload("res://scripts/view/chess_king_activation_profile.gd")
const ActivationSequence := preload("res://scripts/view/chess_king_activation_sequence.gd")
const Lightning := preload("res://scripts/view/chess_lightning_2d.gd")
const STONE_SHADER := preload("res://effects/chess_stone_piece.gdshader")
const SETUP_PRESET_DIRECTORY := "res://.cache/chess_setup_presets"
const ACTIVATION_PRESET_DIRECTORY := "res://.cache/chess_activation_presets"

enum PlaybackMode { SETUP_THEN_ACTIVATION, SETUP_ONLY, ACTIVATION_ONLY }

@onready var board: ChessBoardView = $ChessBoard
@onready var right_hand: PlayerHandRig = $ChessBoard/PlayerHandRig
@onready var left_hand: PlayerHandRig = $ChessBoard/LeftHandRig

var setup_profile := ChessArmySetupProfile.new()
var setup_sequence: ChessArmySetupSequence
var activation_preset: Resource
var selected_activation_path := ""
var piece_views: Dictionary = {}
var activation_sequence: ChessKingActivationSequence
var activation_nodes: Array[Node] = []
var stone_sprite: Sprite2D
var selected_cue := 0
var syncing_controls := false
var playback_mode := PlaybackMode.SETUP_THEN_ACTIVATION

var setup_selector: OptionButton
var activation_selector: OptionButton
var activating_hand_selector: OptionButton
var playback_mode_selector: OptionButton
var cue_selector: OptionButton
var cue_hand_selector: OptionButton
var cue_gap: SpinBox
var cue_override: CheckButton
var motion_side_selector: OptionButton
var motion_controls: Dictionary = {}
var preset_name: LineEdit
var status_label: Label
var pause_button: Button
var phase_label: Label
var path_debug: Line2D


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	left_hand.set_hand_style(HAND_STYLE)
	right_hand.set_hand_style(HAND_STYLE)
	left_hand.set_board_sound_set(board.visual_style.interaction_sounds)
	right_hand.set_board_sound_set(board.visual_style.interaction_sounds)
	left_hand.set_visual_mirrored(true)
	setup_profile.ensure_standard_cues()
	_build_controls()
	_refresh_activation_presets()
	_refresh_setup_presets()
	_rebuild_preview()
	get_viewport().size_changed.connect(func():
		_refresh_debug_path()
		_refresh_activation_hand_geometry.call_deferred()
	)


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(370, 0)
	panel.z_index = 300
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370, 1020)
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 350
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "Player Army Setup Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	setup_selector = _add_option(controls, "Setup Profile")
	setup_selector.item_selected.connect(_load_selected_setup)
	activation_selector = _add_option(controls, "Activation")
	activation_selector.item_selected.connect(_load_selected_activation)
	activating_hand_selector = _add_option(controls, "Activating Hand")
	activating_hand_selector.add_item("Left")
	activating_hand_selector.add_item("Right")
	activating_hand_selector.select(setup_profile.activating_hand)
	activating_hand_selector.item_selected.connect(func(index: int):
		setup_profile.activating_hand = index
		_rebuild_preview()
	)
	playback_mode_selector = _add_option(controls, "Preview Mode")
	for label in ["Setup → Activation", "Setup Only", "Activation Only"]:
		playback_mode_selector.add_item(label)
	playback_mode_selector.item_selected.connect(func(index: int):
		playback_mode = index
		_restart()
	)

	var playback := HBoxContainer.new()
	controls.add_child(playback)
	_add_button(playback, "Play", _play)
	pause_button = _add_button(playback, "Pause", _toggle_pause)
	pause_button.disabled = true
	_add_button(playback, "Restart", _restart)
	_add_button(playback, "Preview Cue", _preview_selected_cue)
	var speed := _add_option(controls, "Playback Speed")
	for entry in [{"name":"Ultra Slow", "value":0.125}, {"name":"Slow", "value":0.5}, {"name":"Normal", "value":1.0}, {"name":"Fast", "value":2.0}]:
		speed.add_item(entry.name)
		speed.set_item_metadata(speed.item_count - 1, entry.value)
	speed.select(2)
	speed.item_selected.connect(func(index: int):
		var value: float = speed.get_item_metadata(index)
		if setup_sequence != null: setup_sequence.set_playback_speed(value)
		if activation_sequence != null: activation_sequence.set_playback_speed(value)
	)
	phase_label = Label.new()
	phase_label.text = "Ready — empty board"
	controls.add_child(phase_label)
	controls.add_child(HSeparator.new())

	cue_selector = _add_option(controls, "Placement Cue")
	cue_selector.item_selected.connect(_select_cue)
	cue_hand_selector = _add_option(controls, "Cue Hand")
	cue_hand_selector.add_item("Left")
	cue_hand_selector.add_item("Right")
	cue_hand_selector.item_selected.connect(_edit_cue_hand)
	cue_gap = _add_spin(controls, "Gap before", 0.0, 10.0, 0.01, func(value: float):
		if not syncing_controls: setup_profile.cues[selected_cue].gap_before = value)
	cue_override = CheckButton.new()
	cue_override.text = "Override this cue's motion"
	cue_override.toggled.connect(_toggle_cue_override)
	controls.add_child(cue_override)
	var order_row := HBoxContainer.new()
	controls.add_child(order_row)
	_add_button(order_row, "Earlier", func(): _move_cue(-1))
	_add_button(order_row, "Later", func(): _move_cue(1))
	controls.add_child(HSeparator.new())

	motion_side_selector = _add_option(controls, "Edit Defaults")
	motion_side_selector.add_item("Left hand")
	motion_side_selector.add_item("Right hand")
	motion_side_selector.item_selected.connect(func(_index: int): _sync_motion_controls())
	for property in [
		[&"pickup_delay", "Pickup delay", 0.0, 2.0],
		[&"entry_duration", "Entry duration", 0.01, 4.0],
		[&"placement_hold", "Placement hold", 0.0, 2.0],
		[&"release_hold", "Release hold", 0.0, 2.0],
		[&"retreat_duration", "Retreat duration", 0.01, 4.0],
	]:
		var property_name: StringName = property[0]
		motion_controls[property_name] = _add_spin(controls, property[1], property[2], property[3], 0.01, func(value: float):
			if not syncing_controls: _edited_motion().set(property_name, value))
	for vector_property in [
		[&"entry_departure_handle", "Entry departure"],
		[&"entry_arrival_handle", "Entry arrival"],
		[&"retreat_departure_handle", "Retreat departure"],
		[&"retreat_arrival_handle", "Retreat arrival"],
	]:
		_add_vector_controls(controls, vector_property[0], vector_property[1])
	var debug_toggle := CheckButton.new()
	debug_toggle.text = "Show selected motion path"
	debug_toggle.toggled.connect(func(value: bool): path_debug.visible = value; _refresh_debug_path())
	controls.add_child(debug_toggle)

	controls.add_child(HSeparator.new())
	var save_row := HBoxContainer.new()
	controls.add_child(save_row)
	preset_name = LineEdit.new()
	preset_name.placeholder_text = "Setup profile name"
	preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(preset_name)
	_add_button(save_row, "Save", _save_setup)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)
	path_debug = Line2D.new()
	path_debug.visible = false
	path_debug.width = 2.0
	path_debug.default_color = Color("3ac8d5")
	path_debug.z_index = 290
	add_child(path_debug)
	_refresh_cue_controls()
	_sync_motion_controls()


func _rebuild_preview() -> void:
	_clear_activation()
	var color: String = activation_preset.army_color if activation_preset != null else "white"
	var king_type: StringName = activation_preset.king_type_id if activation_preset != null else &"classic_king"
	board.set_viewing_color(color)
	var fixture := _make_standard_fixture(color, king_type)
	var rendered: Dictionary
	if board.board == null or board.board.is_empty():
		rendered = board.draw_board(fixture)
	else:
		rendered = board.rebuild_board(fixture)
	piece_views.clear()
	for model in rendered:
		var view: PieceView = rendered[model]
		piece_views[model.coordinate] = view
		view.visible = false
	left_hand.set_visual_mirrored(true)
	right_hand.set_visual_mirrored(false)
	setup_sequence = ChessArmySetupSequence.new()
	add_child(setup_sequence)
	setup_sequence.configure(setup_profile, board, left_hand, right_hand, piece_views)
	setup_sequence.cue_started.connect(func(cue: ChessSetupCue): phase_label.text = "Placing %s" % cue.label())
	setup_sequence.setup_completed.connect(_on_setup_completed)
	_prepare_activation()
	_refresh_activation_hand_geometry.call_deferred()
	_refresh_cue_controls()
	_refresh_debug_path()
	_restart()


func _make_standard_fixture(color: String, king_type: StringName) -> Array:
	var result: Array = []
	for row in range(8):
		var cells: Array = []
		cells.resize(8)
		cells.fill(null)
		result.append(cells)
	var types := [&"rook", &"knight", &"bishop", &"queen", king_type, &"bishop", &"knight", &"rook"]
	for display_col in range(8):
		var back := _model_coordinate(Vector2i(7, display_col), color)
		var pawn := _model_coordinate(Vector2i(6, display_col), color)
		result[back.x][back.y] = ChessPieceCatalog.create_piece(types[display_col], color, back)
		result[pawn.x][pawn.y] = ChessPieceCatalog.create_piece(&"pawn", color, pawn)
	return result


func _model_coordinate(display: Vector2i, color: String) -> Vector2i:
	return Vector2i(7 - display.x, 7 - display.y) if color == "black" else display


func _prepare_activation() -> void:
	if activation_preset == null:
		activation_preset = _default_activation_preset()
	var king_coordinate := board.projection.get_model_coordinate(Vector2i(7, 4))
	var king_view: PieceView = piece_views.get(king_coordinate)
	if not is_instance_valid(king_view):
		return
	stone_sprite = Sprite2D.new()
	stone_sprite.texture = king_view.sprite.texture
	stone_sprite.centered = king_view.sprite.centered
	stone_sprite.offset = king_view.sprite.offset
	stone_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var stone_material := ShaderMaterial.new()
	stone_material.shader = STONE_SHADER
	stone_sprite.material = stone_material
	king_view.sprite.add_child(stone_sprite)
	activation_nodes.append(stone_sprite)
	var hand := left_hand if setup_profile.activating_hand == ChessArmySetupProfile.ActivatingHand.LEFT else right_hand
	var aura_profile: ChessAuraProfile = activation_preset.aura_snapshot.duplicate(true)
	var king_aura := Aura.new() as ChessAura2D
	king_aura.profile = aura_profile
	king_aura.mode = activation_preset.aura_mode
	board.add_child(king_aura)
	king_aura.bind_targets([king_view.sprite])
	var hand_aura := Aura.new() as ChessAura2D
	hand_aura.profile = aura_profile
	hand_aura.mode = activation_preset.aura_mode
	board.add_child(hand_aura)
	hand_aura.bind_targets(hand.get_aura_sprites())
	var lightning := Lightning.new()
	lightning.z_index = PlayerHandRig.ACTIVE_PIECE_Z
	board.add_child(lightning)
	var anchor := Marker2D.new()
	anchor.position = hand.get_connection_anchor_position()
	hand.add_child(anchor)
	activation_sequence = ActivationSequence.new()
	board.add_child(activation_sequence)
	activation_nodes.append_array([king_aura, hand_aura, lightning, anchor, activation_sequence])
	var direction := -1.0 if hand.visual_mirrored else 1.0
	var offset: Vector2 = activation_preset.activation_profile.hand_hover_offset
	offset.x *= direction
	var hover_position := king_view.position + offset
	hand.position = hover_position
	hand.scale = Vector2.ONE * board.get_world_scale() * hand.art_scale_multiplier
	var rest_position := hand._setup_rest_position(board.get_world_scale() * hand.art_scale_multiplier)
	activation_sequence.configure(
		activation_preset.activation_profile.duplicate(true),
		hand,
		anchor,
		king_view.sprite,
		stone_sprite,
		hand_aura,
		king_aura,
		lightning,
		{},
		rest_position,
		1.0,
		hand.visual_mirrored
	)
	activation_sequence.phase_changed.connect(func(_phase: int): phase_label.text = "Activation: %s" % activation_sequence.phase_name())
	activation_sequence.activation_completed.connect(func(): phase_label.text = "Ceremony complete")


func _on_setup_completed() -> void:
	if playback_mode == PlaybackMode.SETUP_ONLY:
		phase_label.text = "Setup complete"
		pause_button.disabled = true
		return
	phase_label.text = "Setup complete — activating king"
	_start_activation()


func _play() -> void:
	if playback_mode == PlaybackMode.ACTIVATION_ONLY:
		_start_activation()
	else:
		setup_sequence.play()
	pause_button.disabled = false
	pause_button.text = "Pause"


func _restart() -> void:
	if activation_sequence != null: activation_sequence.restart(false)
	setup_sequence.restart(false)
	if playback_mode == PlaybackMode.ACTIVATION_ONLY:
		for piece in piece_views.values():
			if is_instance_valid(piece): piece.visible = true
		phase_label.text = "Ready — activation only"
	else:
		phase_label.text = "Ready — empty board"
	pause_button.disabled = true


func _start_activation() -> void:
	if activation_sequence == null: return
	_refresh_activation_hand_geometry()
	activation_sequence.play()
	phase_label.text = "Activation: %s" % activation_sequence.phase_name()


## Activation endpoints depend on the board's final fullscreen projection. The
## board can relayout after this lab builds its preview, so never rely solely on
## the coordinates captured by _prepare_activation().
func _refresh_activation_hand_geometry() -> void:
	if activation_sequence == null or activation_sequence.running:
		return
	if setup_sequence != null and setup_sequence.running:
		return
	var hand := left_hand if setup_profile.activating_hand == ChessArmySetupProfile.ActivatingHand.LEFT else right_hand
	var king_coordinate := board.projection.get_model_coordinate(Vector2i(7, 4))
	var king_view: PieceView = piece_views.get(king_coordinate)
	if not is_instance_valid(hand) or not is_instance_valid(king_view):
		return
	var direction := -1.0 if hand.visual_mirrored else 1.0
	var offset: Vector2 = activation_sequence.profile.hand_hover_offset
	offset.x *= direction
	var world_scale := board.get_world_scale()
	var effective_hand_scale := world_scale * hand.art_scale_multiplier
	hand.scale = Vector2.ONE * effective_hand_scale
	activation_sequence.base_hand_position = king_view.position + offset
	activation_sequence.hand_rest_position = hand._setup_rest_position(effective_hand_scale)
	activation_sequence.hand_motion_scale = 1.0
	activation_sequence.mirror_hand_motion = hand.visual_mirrored
	if activation_sequence.current_phase == activation_sequence.Phase.RESET:
		hand.position = activation_sequence.hand_rest_position
		hand.visible = false


func _toggle_pause() -> void:
	if setup_sequence.running:
		if setup_sequence.paused:
			setup_sequence.resume(); pause_button.text = "Pause"
		else:
			setup_sequence.pause(); pause_button.text = "Resume"
	elif activation_sequence != null and activation_sequence.running:
		activation_sequence.pause(); pause_button.text = "Resume"
	elif activation_sequence != null:
		activation_sequence.resume(); pause_button.text = "Pause"


func _preview_selected_cue() -> void:
	_restart()
	var cue := setup_profile.cues[selected_cue]
	var coordinate := board.projection.get_model_coordinate(cue.display_coordinate)
	var piece: Node2D = piece_views.get(coordinate)
	var hand := left_hand if cue.hand_side == ChessSetupCue.HandSide.LEFT else right_hand
	await hand.play_setup_placement(piece, board.grid_to_screen(coordinate.x, coordinate.y), board.get_world_scale(), setup_profile.motion_for(cue), board.get_piece_depth(coordinate))
	phase_label.text = "Selected cue complete"


func _clear_activation() -> void:
	if setup_sequence != null:
		setup_sequence.queue_free()
	for node in activation_nodes:
		if is_instance_valid(node): node.queue_free()
	activation_nodes.clear()
	activation_sequence = null


func _refresh_activation_presets(selected_path := "") -> void:
	activation_selector.clear()
	activation_selector.add_item("Unsaved classic defaults")
	activation_selector.set_item_metadata(0, "")
	var selected := 0
	for entry in _discover(ACTIVATION_PRESET_DIRECTORY, ActivationPreset):
		activation_selector.add_item(entry.name)
		activation_selector.set_item_metadata(activation_selector.item_count - 1, entry.path)
		if entry.path == selected_path: selected = activation_selector.item_count - 1
	activation_selector.select(selected)


func _load_selected_activation(index: int) -> void:
	selected_activation_path = activation_selector.get_item_metadata(index)
	activation_preset = _load_activation(selected_activation_path)
	_rebuild_preview()


func _default_activation_preset() -> Resource:
	var result: Resource = ActivationPreset.new()
	result.display_name = "Unsaved classic defaults"
	result.activation_profile = ActivationProfile.new()
	result.aura_snapshot = AuraProfile.new()
	result.king_type_id = &"classic_king"
	result.army_color = "white"
	return result


func _load_activation(path: String) -> Resource:
	if path.is_empty(): return _default_activation_preset()
	var loaded := ResourceLoader.load(path, "ChessActivationLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	return loaded.duplicate(true) if loaded != null and loaded.is_supported() else _default_activation_preset()


func _refresh_setup_presets(selected_path := "") -> void:
	setup_selector.clear()
	setup_selector.add_item("Unsaved defaults")
	setup_selector.set_item_metadata(0, "")
	var selected := 0
	for entry in _discover(SETUP_PRESET_DIRECTORY, SetupPreset):
		setup_selector.add_item(entry.name)
		setup_selector.set_item_metadata(setup_selector.item_count - 1, entry.path)
		if entry.path == selected_path: selected = setup_selector.item_count - 1
	setup_selector.select(selected)


func _load_selected_setup(index: int) -> void:
	if index <= 0: return
	var path: String = setup_selector.get_item_metadata(index)
	var loaded := ResourceLoader.load(path, "ChessSetupLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded.is_supported(): return
	setup_profile = loaded.setup_profile.duplicate(true)
	selected_activation_path = loaded.activation_preset_path
	activation_preset = _load_activation(selected_activation_path)
	if selected_activation_path.is_empty() or activation_preset.display_name == "Unsaved classic defaults":
		if loaded.activation_snapshot != null: activation_preset = loaded.activation_snapshot.duplicate(true)
	_refresh_activation_presets(selected_activation_path)
	activating_hand_selector.select(setup_profile.activating_hand)
	preset_name.text = loaded.display_name
	selected_cue = 0
	_rebuild_preview()
	status_label.text = "Loaded '%s'." % loaded.display_name


func _save_setup() -> void:
	var name := preset_name.text.strip_edges()
	var stem := _safe_stem(name)
	if stem.is_empty():
		status_label.text = "Enter a profile name."
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SETUP_PRESET_DIRECTORY))
	var preset: Resource = SetupPreset.new()
	preset.display_name = name
	preset.setup_profile = setup_profile.duplicate(true)
	preset.activation_preset_path = selected_activation_path
	preset.activation_snapshot = activation_preset.duplicate(true)
	var path := "%s/%s.tres" % [SETUP_PRESET_DIRECTORY, stem]
	var error := ResourceSaver.save(preset, path)
	if error == OK:
		_refresh_setup_presets(path)
		status_label.text = "Saved to %s" % ProjectSettings.globalize_path(path)
	else:
		status_label.text = "Save failed with error %d." % error


func _discover(directory_path: String, expected_script: Script) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(directory_path)
	if directory == null: return result
	for file in directory.get_files():
		if file.get_extension().to_lower() != "tres": continue
		var path := "%s/%s" % [directory_path, file]
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource != null and resource.get_script() == expected_script and resource.is_supported():
			result.append({"name": resource.display_name, "path": path})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return result


func _select_cue(index: int) -> void:
	selected_cue = clampi(index, 0, setup_profile.cues.size() - 1)
	_refresh_cue_controls()
	_refresh_debug_path()


func _refresh_cue_controls() -> void:
	if cue_selector == null: return
	syncing_controls = true
	cue_selector.clear()
	for cue in setup_profile.cues:
		var model_coordinate := board.projection.get_model_coordinate(cue.display_coordinate) if board != null and not board.board.is_empty() else cue.display_coordinate
		var piece: PieceView = piece_views.get(model_coordinate)
		var piece_name := _setup_piece_name(piece) if is_instance_valid(piece) else str(cue.display_coordinate)
		cue_selector.add_item("%s — %s" % ["L" if cue.hand_side == 0 else "R", piece_name])
	if not setup_profile.cues.is_empty():
		selected_cue = clampi(selected_cue, 0, setup_profile.cues.size() - 1)
		cue_selector.select(selected_cue)
		var cue := setup_profile.cues[selected_cue]
		cue_hand_selector.select(cue.hand_side)
		cue_gap.set_value_no_signal(cue.gap_before)
		cue_override.set_pressed_no_signal(cue.motion_override != null)
	syncing_controls = false


func _setup_piece_name(piece: PieceView) -> String:
	if piece.model.type != "pawn":
		return piece.model.type
	var file_index := clampi(piece.model.coordinate.y, 0, 7)
	return "%s_pawn" % String.chr("a".unicode_at(0) + file_index)


func _edit_cue_hand(index: int) -> void:
	if syncing_controls: return
	setup_profile.cues[selected_cue].hand_side = index
	_refresh_cue_controls()


func _toggle_cue_override(enabled: bool) -> void:
	if syncing_controls: return
	var cue := setup_profile.cues[selected_cue]
	if enabled and cue.motion_override == null:
		cue.motion_override = setup_profile.motion_for(cue).duplicate(true)
	elif not enabled:
		cue.motion_override = null
	_sync_motion_controls()


func _move_cue(direction: int) -> void:
	var cue := setup_profile.cues[selected_cue]
	var same_side: Array[int] = []
	for index in range(setup_profile.cues.size()):
		if setup_profile.cues[index].hand_side == cue.hand_side: same_side.append(index)
	var position := same_side.find(selected_cue)
	var other_position := position + direction
	if other_position < 0 or other_position >= same_side.size(): return
	var other_index := same_side[other_position]
	var displaced := setup_profile.cues[other_index]
	setup_profile.cues[other_index] = cue
	setup_profile.cues[selected_cue] = displaced
	selected_cue = other_index
	_refresh_cue_controls()


func _edited_motion() -> ChessSetupMotionProfile:
	var cue := setup_profile.cues[selected_cue]
	if cue.motion_override != null: return cue.motion_override
	return setup_profile.left_motion if motion_side_selector.selected == 0 else setup_profile.right_motion


func _sync_motion_controls() -> void:
	if motion_controls.is_empty(): return
	syncing_controls = true
	var motion := _edited_motion()
	for property_name in motion_controls:
		var control: SpinBox = motion_controls[property_name]
		var component := String(property_name).get_slice(":", 1)
		var base_name := StringName(String(property_name).get_slice(":", 0))
		if component == "x" or component == "y":
			var vector: Vector2 = motion.get(base_name)
			control.set_value_no_signal(vector.x if component == "x" else vector.y)
		else:
			control.set_value_no_signal(motion.get(property_name))
	syncing_controls = false


func _add_vector_controls(parent: Control, property_name: StringName, label: String) -> void:
	for component in ["x", "y"]:
		var key := StringName("%s:%s" % [property_name, component])
		motion_controls[key] = _add_spin(parent, "%s %s" % [label, component.to_upper()], -600.0, 600.0, 1.0, func(value: float):
			if syncing_controls: return
			var motion := _edited_motion()
			var vector: Vector2 = motion.get(property_name)
			if component == "x": vector.x = value
			else: vector.y = value
			motion.set(property_name, vector)
			_refresh_debug_path())


func _refresh_debug_path() -> void:
	if path_debug == null or not path_debug.visible or piece_views.is_empty(): return
	var cue := setup_profile.cues[selected_cue]
	var coordinate := board.projection.get_model_coordinate(cue.display_coordinate)
	var piece: PieceView = piece_views.get(coordinate)
	if not is_instance_valid(piece): return
	var hand := left_hand if cue.hand_side == 0 else right_hand
	var motion := setup_profile.motion_for(cue)
	var scale := board.get_world_scale()
	var start := hand._setup_rest_position(scale * hand.art_scale_multiplier)
	var finish := board.to_local(piece.get_grip_anchor().global_position)
	var mirror := -1.0 if hand.visual_mirrored else 1.0
	var a := start + Vector2(motion.entry_departure_handle.x * mirror, motion.entry_departure_handle.y) * scale
	var b := finish + Vector2(motion.entry_arrival_handle.x * mirror, motion.entry_arrival_handle.y) * scale
	var points := PackedVector2Array()
	for index in range(33): points.append(PlayerHandRig.calculate_bezier_position(start, a, b, finish, index / 32.0))
	path_debug.points = points


func _add_option(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 130; row.add_child(label)
	var option := OptionButton.new(); option.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(option)
	return option


func _add_spin(parent: Control, label_text: String, minimum: float, maximum: float, step: float, callback: Callable) -> SpinBox:
	var row := HBoxContainer.new(); parent.add_child(row)
	var label := Label.new(); label.text = label_text; label.custom_minimum_size.x = 170; row.add_child(label)
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = step; spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; spin.value_changed.connect(callback); row.add_child(spin)
	return spin


func _add_button(parent: Control, text_value: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.focus_mode = Control.FOCUS_NONE; button.pressed.connect(callback); parent.add_child(button); return button


func _safe_stem(value: String) -> String:
	var result := ""
	for character in value.to_lower():
		if character.is_valid_identifier() or character >= "0" and character <= "9": result += character
		elif character in [" ", "-", "."] and not result.ends_with("_"): result += "_"
	return result.trim_prefix("_").trim_suffix("_")
