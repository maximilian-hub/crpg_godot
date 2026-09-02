extends Node2D

const BOARD_BODY_SCENE := preload("res://scenes/board_body.tscn")
const PIECE_SCENE := preload("res://scenes/piece.tscn")
const LAB_STYLE := preload("res://assets/chess_board_material_lab_style.tres")
const ENVIRONMENT_STYLE := preload("res://assets/chess_environment_lab_style.tres")
const BoardMaterialSurface := preload("res://scripts/view/chess_board_material_surface.gd")
const IVORY_V1 := preload("res://assets/boards/materials/ivory_marble_128_v1.png")
const BURGUNDY_V1 := preload("res://assets/boards/materials/burgundy_marble_128_v1.png")
const IVORY_V2 := preload("res://assets/boards/materials/ivory_marble_128_v2.png")
const BURGUNDY_V2 := preload("res://assets/boards/materials/burgundy_marble_128_v2.png")
const FRAME_WOOD_V1 := preload("res://assets/boards/materials/dark_wood_frame_128_v1.png")
const FRAME_WOOD_V2 := preload("res://assets/boards/materials/dark_wood_frame_128_v2.png")
const TABLE_WOOD_V1 := preload("res://assets/boards/environments/portable_walnut_table_256_v1.png")
const TABLE_WOOD_V2 := preload("res://assets/boards/environments/portable_walnut_table_256_v2.png")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")

var projection := ChessBoardProjection.new()
var visual_style: ChessBoardVisualStyle
var environment_style: ChessEnvironmentVisualStyle
var board_body: BoardBodyView
var pieces := Node2D.new()
var board_size := 8
var environment_surface: ChessEnvironmentSurface
var size_selector: OptionButton
var surface_toggle: CheckButton
var piece_mode_selector: OptionButton
var piece_mode := 0
var status_label: Label
var publish_confirmation: ConfirmationDialog


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Styles need an editable top-level clone, but imported textures and sound
	# resources must remain external references when this look is published.
	visual_style = LAB_STYLE.duplicate(false) as ChessBoardVisualStyle
	visual_style.changed.connect(_refresh_board)
	environment_style = ENVIRONMENT_STYLE.duplicate(false) as ChessEnvironmentVisualStyle
	environment_style.changed.connect(_refresh_background)
	environment_surface = ChessEnvironmentSurface.new()
	environment_surface.name = "EnvironmentSurface"
	add_child(environment_surface)
	board_body = BOARD_BODY_SCENE.instantiate() as BoardBodyView
	add_child(board_body)
	pieces.name = "Pieces"
	add_child(pieces)
	_build_controls()
	get_viewport().size_changed.connect(_refresh_board)
	_refresh_board()


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(370, 0)
	panel.z_index = 200
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, minf(680.0, get_viewport_rect().size.y - 36.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	controls.custom_minimum_size.x = 350
	scroll.add_child(controls)
	var title := Label.new()
	title.text = "Board Presentation Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Safe material-surface prototype"
	subtitle.modulate = Color("a9a4b8")
	controls.add_child(subtitle)
	size_selector = _add_option(controls, "Board", ["8 × 8", "6 × 6"])
	size_selector.item_selected.connect(func(index: int):
		board_size = 6 if index == 1 else 8
		_sync_piece_mode_availability()
		_refresh_board())
	piece_mode_selector = _add_option(controls, "Pieces", ["Samples", "Full armies"])
	piece_mode_selector.item_selected.connect(func(index: int):
		piece_mode = index
		_rebuild_pieces()
		_refresh_status())
	_add_slider(controls, "Piece forward", 0.0, 1.0, 0.01, visual_style.piece_forward_bias, func(value: float): visual_style.piece_forward_bias = value)
	var material_version := _add_option(controls, "Material", ["Original downscale", "Posterized RPG"])
	material_version.select(1)
	material_version.item_selected.connect(_set_material_version)
	var frame_material_version := _add_option(controls, "Frame material", ["Original downscale", "Posterized RPG"])
	frame_material_version.select(1)
	frame_material_version.item_selected.connect(_set_frame_material_version)
	surface_toggle = CheckButton.new()
	surface_toggle.text = "Material surface"
	surface_toggle.button_pressed = true
	surface_toggle.toggled.connect(func(enabled: bool): visual_style.material_surface_enabled = enabled)
	controls.add_child(surface_toggle)
	_add_slider(controls, "Texture scale", 0.25, 4.0, 0.05, visual_style.material_texture_scale, func(value: float): visual_style.material_texture_scale = value)
	_add_slider(controls, "Texture blend", 0.0, 1.0, 0.01, visual_style.material_texture_strength, func(value: float): visual_style.material_texture_strength = value)
	_add_slider(controls, "Light brightness", 0.4, 1.2, 0.01, visual_style.material_light_brightness, func(value: float): visual_style.material_light_brightness = value)
	_add_slider(controls, "Square variation", 0.0, 0.25, 0.005, visual_style.material_variation_strength, func(value: float): visual_style.material_variation_strength = value)
	_add_slider(controls, "Placeholder detail", 0.0, 1.0, 0.01, visual_style.material_procedural_detail, func(value: float): visual_style.material_procedural_detail = value)
	_add_slider(controls, "Seam width", 0.0, 0.08, 0.001, visual_style.material_seam_width, func(value: float): visual_style.material_seam_width = value)
	controls.add_child(HSeparator.new())
	var frame_toggle := CheckButton.new()
	frame_toggle.text = "Material frame"
	frame_toggle.button_pressed = visual_style.frame_material_enabled
	frame_toggle.toggled.connect(func(enabled: bool): visual_style.frame_material_enabled = enabled)
	controls.add_child(frame_toggle)
	_add_slider(controls, "Frame tex scale", 0.25, 4.0, 0.05, visual_style.frame_material_texture_scale, func(value: float): visual_style.frame_material_texture_scale = value)
	_add_slider(controls, "Grain tightness", 0.15, 2.0, 0.01, visual_style.frame_material_grain_tightness, func(value: float): visual_style.frame_material_grain_tightness = value)
	_add_slider(controls, "Frame brightness", 0.4, 1.4, 0.01, visual_style.frame_material_brightness, func(value: float): visual_style.frame_material_brightness = value)
	_add_slider(controls, "Edge brightness", 0.3, 1.0, 0.01, visual_style.frame_material_edge_brightness, func(value: float): visual_style.frame_material_edge_brightness = value)
	_add_slider(controls, "Frame detail", 0.0, 1.0, 0.01, visual_style.frame_material_procedural_detail, func(value: float): visual_style.frame_material_procedural_detail = value)
	_add_slider(controls, "Frame width", 0.0, 64.0, 1.0, visual_style.reference_frame_width, func(value: float): visual_style.reference_frame_width = value)
	_add_slider(controls, "Thickness", 0.0, 48.0, 1.0, visual_style.reference_thickness, func(value: float): visual_style.reference_thickness = value)
	controls.add_child(HSeparator.new())
	var shadow_toggle := CheckButton.new()
	shadow_toggle.text = "Board shadow"
	shadow_toggle.button_pressed = visual_style.board_shadow_enabled
	shadow_toggle.toggled.connect(func(enabled: bool): visual_style.board_shadow_enabled = enabled)
	controls.add_child(shadow_toggle)
	_add_slider(controls, "Shadow opacity", 0.0, 0.8, 0.01, visual_style.shadow_color.a, _set_shadow_opacity)
	_add_slider(controls, "Shadow offset X", -48.0, 48.0, 1.0, visual_style.reference_shadow_offset.x, _set_shadow_offset_x)
	_add_slider(controls, "Shadow offset Y", -16.0, 64.0, 1.0, visual_style.reference_shadow_offset.y, _set_shadow_offset_y)
	_add_slider(controls, "Shadow softness", 0.0, 64.0, 1.0, visual_style.reference_shadow_softness, func(value: float): visual_style.reference_shadow_softness = value)
	var background_selector := _add_option(controls, "Background", ["Dark neutral", "Warm table", "Cool stone"])
	background_selector.item_selected.connect(func(index: int):
		environment_style.flat_color = [Color("17131c"), Color("2a1b14"), Color("182027")][index]
		_refresh_background())
	var environment_version := _add_option(controls, "Environment", ["Original downscale", "Posterized RPG"])
	environment_version.select(1)
	environment_version.item_selected.connect(_set_environment_version)
	var environment_toggle := CheckButton.new()
	environment_toggle.text = "Environment texture"
	environment_toggle.button_pressed = environment_style.texture_enabled
	environment_toggle.toggled.connect(func(enabled: bool): environment_style.texture_enabled = enabled)
	controls.add_child(environment_toggle)
	_add_slider(controls, "Env tex scale", 0.25, 8.0, 0.05, environment_style.texture_scale, func(value: float): environment_style.texture_scale = value)
	_add_slider(controls, "Env tex blend", 0.0, 1.0, 0.01, environment_style.texture_strength, func(value: float): environment_style.texture_strength = value)
	_add_slider(controls, "Env brightness", 0.4, 1.4, 0.01, environment_style.brightness, func(value: float): environment_style.brightness = value)
	var tint_selector := _add_option(controls, "Environment tint", ["Neutral", "Warm", "Cool"])
	tint_selector.select(1)
	tint_selector.item_selected.connect(func(index: int):
		environment_style.tint = [Color.WHITE, Color("fff0df"), Color("e5efff")][index])
	controls.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "Texture slots live on ChessBoardVisualStyle.\nBrightness is nondestructive preview grading."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 325
	controls.add_child(note)
	var publish := Button.new()
	publish.text = "Publish to Game"
	publish.tooltip_text = "Updates the named board and environment styles used by the default battle presentation."
	publish.pressed.connect(_request_publish)
	controls.add_child(publish)
	status_label = Label.new()
	status_label.modulate = Color("8ee6a2")
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(status_label)
	publish_confirmation = ConfirmationDialog.new()
	publish_confirmation.dialog_text = "Publish the current board and environment to the default game presentation?\n\nThe legacy flat fallback will not be changed."
	publish_confirmation.confirmed.connect(_publish_to_game)
	add_child(publish_confirmation)


func _add_option(parent: Control, label_text: String, values: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in values:
		option.add_item(value)
	row.add_child(option)
	return option


func _add_slider(parent: Control, label_text: String, minimum: float, maximum: float, step: float, initial: float, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%.2f" % initial
	value_label.custom_minimum_size.x = 48
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		callback.call(value))
	return slider


func _refresh_board() -> void:
	if not is_instance_valid(board_body):
		return
	projection.configure(get_viewport_rect().size, board_size, board_size, "white", 0.90, 0.66, 0.70, 0.88, 0.54)
	_refresh_background()
	board_body.configure(projection.get_board_outline(), projection.get_presentation_scale(), visual_style)
	var surface := board_body.get_node("MaterialSurface") as MeshInstance2D
	surface.configure(projection, visual_style)
	_rebuild_pieces()
	_refresh_status()


func _sync_piece_mode_availability() -> void:
	var full_armies_available := board_size == 8
	piece_mode_selector.set_item_disabled(1, not full_armies_available)
	if not full_armies_available and piece_mode == 1:
		piece_mode = 0
		piece_mode_selector.select(0)


func _set_material_version(index: int) -> void:
	visual_style.light_square_texture = IVORY_V2 if index == 1 else IVORY_V1
	visual_style.dark_square_texture = BURGUNDY_V2 if index == 1 else BURGUNDY_V1


func _set_frame_material_version(index: int) -> void:
	var texture := FRAME_WOOD_V2 if index == 1 else FRAME_WOOD_V1
	visual_style.frame_top_texture = texture
	visual_style.frame_edge_texture = texture


func _set_environment_version(index: int) -> void:
	environment_style.surface_texture = TABLE_WOOD_V2 if index == 1 else TABLE_WOOD_V1


func _set_shadow_opacity(value: float) -> void:
	var color := visual_style.shadow_color
	color.a = value
	visual_style.shadow_color = color


func _set_shadow_offset_x(value: float) -> void:
	visual_style.reference_shadow_offset = Vector2(value, visual_style.reference_shadow_offset.y)


func _set_shadow_offset_y(value: float) -> void:
	visual_style.reference_shadow_offset = Vector2(visual_style.reference_shadow_offset.x, value)


func _request_publish() -> void:
	var validation_error := RuntimePublisher.validate_battle_presentation(visual_style, environment_style)
	if not validation_error.is_empty():
		status_label.text = validation_error
		status_label.modulate = Color("ff8f8f")
		return
	publish_confirmation.popup_centered()


func _publish_to_game(
		board_target_path := RuntimePublisher.BOARD_RUNTIME_PATH,
		environment_target_path := RuntimePublisher.ENVIRONMENT_RUNTIME_PATH
	) -> Dictionary:
	var result: Dictionary = RuntimePublisher.publish_battle_presentation(
		visual_style,
		environment_style,
		board_target_path,
		environment_target_path
	)
	status_label.text = result.message
	status_label.modulate = Color("8ee6a2") if result.ok else Color("ff8f8f")
	return result


func _refresh_status() -> void:
	var piece_label := "full starting armies" if piece_mode == 1 else "representative samples"
	status_label.text = "%d × %d · %d surface cells · %s" % [board_size, board_size, board_size * board_size, piece_label]


func _refresh_background() -> void:
	if is_instance_valid(environment_surface):
		environment_surface.configure(get_viewport_rect().size, environment_style)


func _rebuild_pieces() -> void:
	for child in pieces.get_children():
		child.free()
	var piece_data := _full_army_piece_data() if piece_mode == 1 and board_size == 8 else _sample_piece_data()
	var world_scale := ChessBoardView.calculate_world_scale(projection.get_near_edge_width())
	for model_piece in piece_data:
		var piece := PIECE_SCENE.instantiate() as PieceView
		piece.set_model(model_piece)
		piece.coordinate = model_piece.coordinate
		piece.position = projection.get_piece_ground_anchor(model_piece.coordinate, visual_style.piece_forward_bias)
		piece.scale = Vector2.ONE * world_scale
		piece.z_index = projection.get_display_coordinate(model_piece.coordinate).x * ChessBoardView.BOARD_DEPTH_STRIDE
		pieces.add_child(piece)


func _sample_piece_data() -> Array[ModelPiece]:
	var center_column := floori(board_size * 0.5)
	var result: Array[ModelPiece] = []
	result.append(ArakneKing.new("white", Vector2i(board_size - 1, center_column)))
	result.append(MinotaurKing.new("white", Vector2i(board_size - 2, maxi(center_column - 2, 0))))
	result.append(NecromancerKing.new("black", Vector2i(0, center_column)))
	result.append(Pawn.new("black", Vector2i(1, maxi(center_column - 1, 0))))
	return result


func _full_army_piece_data() -> Array[ModelPiece]:
	var result: Array[ModelPiece] = []
	var black_back: Array[StringName] = [&"rook", &"knight", &"bishop", &"queen", &"necromancer_king", &"bishop", &"knight", &"rook"]
	var white_back: Array[StringName] = [&"rook", &"knight", &"bishop", &"queen", &"arakne_king", &"bishop", &"knight", &"rook"]
	for column in range(8):
		result.append(ChessPieceCatalog.create_piece(black_back[column], "black", Vector2i(0, column)))
		result.append(ChessPieceCatalog.create_piece(&"pawn", "black", Vector2i(1, column)))
		result.append(ChessPieceCatalog.create_piece(&"pawn", "white", Vector2i(6, column)))
		result.append(ChessPieceCatalog.create_piece(white_back[column], "white", Vector2i(7, column)))
	return result
