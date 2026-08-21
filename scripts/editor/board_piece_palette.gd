extends PanelContainer
class_name BoardPiecePalette

signal cursor_selected()
signal delete_selected()
signal piece_selected(type_id: StringName, color: String)
signal piece_drag_requested(type_id: StringName, color: String)

const PaletteItem = preload("res://scripts/editor/board_piece_palette_item.gd")

var cursor_item
var delete_item
var piece_items: Dictionary = {}
var king_items: Dictionary = {}
var king_selector: OptionButton
var king_type_ids: Array[StringName] = []
var palette_enabled := true

func _ready() -> void:
	custom_minimum_size.x = 156.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("3a383f")
	panel_style.border_color = Color("66616d")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", panel_style)
	_build()

func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	var tool_row := HBoxContainer.new()
	tool_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tool_row.add_theme_constant_override("separation", 5)
	column.add_child(tool_row)
	cursor_item = _new_item()
	cursor_item.custom_minimum_size = Vector2(62, 48)
	cursor_item.configure_cursor()
	tool_row.add_child(cursor_item)
	delete_item = _new_item()
	delete_item.custom_minimum_size = Vector2(62, 48)
	delete_item.configure_delete()
	tool_row.add_child(delete_item)

	var pieces_grid := GridContainer.new()
	pieces_grid.columns = 2
	pieces_grid.add_theme_constant_override("h_separation", 5)
	pieces_grid.add_theme_constant_override("v_separation", 4)
	column.add_child(pieces_grid)
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"ordinary"):
		for color in ["white", "black"]:
			var item: Variant = _new_item()
			item.configure_piece(type_id, color)
			pieces_grid.add_child(item)
			piece_items[_key(type_id, color)] = item

	var king_label := Label.new()
	king_label.text = "King Selector:"
	column.add_child(king_label)
	king_selector = OptionButton.new()
	king_type_ids = ChessPieceCatalog.get_palette_type_ids(&"king")
	for type_id in king_type_ids:
		king_selector.add_item(ChessPieceCatalog.get_definition(type_id).get("name", String(type_id)))
	king_selector.item_selected.connect(_on_king_selected)
	column.add_child(king_selector)

	var king_grid := GridContainer.new()
	king_grid.columns = 2
	king_grid.add_theme_constant_override("h_separation", 5)
	column.add_child(king_grid)
	for color in ["white", "black"]:
		var item: Variant = _new_item()
		king_grid.add_child(item)
		king_items[color] = item
	_rebuild_king_items()

func _new_item() -> Variant:
	var item: Variant = PaletteItem.new()
	item.selected.connect(_on_item_selected)
	item.drag_requested.connect(_on_item_drag_requested)
	return item

func _on_item_selected(item) -> void:
	if not palette_enabled:
		return
	if item.is_cursor_tool:
		cursor_selected.emit()
	elif item.is_delete_tool:
		delete_selected.emit()
	else:
		piece_selected.emit(item.type_id, item.color)

func _on_item_drag_requested(item) -> void:
	if palette_enabled and not item.is_cursor_tool:
		piece_drag_requested.emit(item.type_id, item.color)

func _on_king_selected(_index: int) -> void:
	var prior_selected_color := ""
	for color in king_items:
		if king_items[color].selected_state:
			prior_selected_color = color
	_rebuild_king_items()
	if not prior_selected_color.is_empty():
		piece_selected.emit(get_selected_king_type_id(), prior_selected_color)

func _rebuild_king_items() -> void:
	var selected_type := get_selected_king_type_id()
	for color in ["white", "black"]:
		var old_item: Variant = king_items[color]
		var parent: Node = old_item.get_parent()
		var index: int = old_item.get_index()
		parent.remove_child(old_item)
		old_item.queue_free()
		var item: Variant = _new_item()
		item.configure_piece(selected_type, color)
		parent.add_child(item)
		parent.move_child(item, index)
		king_items[color] = item
		item.set_interaction_enabled(palette_enabled)

func get_selected_king_type_id() -> StringName:
	if king_type_ids.is_empty():
		return &"classic_king"
	return king_type_ids[king_selector.selected]

func sync_selection(tool: BoardEditorController.Tool, type_id: StringName, color: String) -> void:
	cursor_item.set_selected_state(tool == BoardEditorController.Tool.CURSOR)
	delete_item.set_selected_state(tool == BoardEditorController.Tool.DELETE)
	for item in piece_items.values():
		item.set_selected_state(tool == BoardEditorController.Tool.PIECE and item.type_id == type_id and item.color == color)
	for item in king_items.values():
		item.set_selected_state(tool == BoardEditorController.Tool.PIECE and item.type_id == type_id and item.color == color)

func set_palette_enabled(enabled: bool) -> void:
	palette_enabled = enabled
	king_selector.disabled = not enabled
	cursor_item.set_interaction_enabled(enabled)
	delete_item.set_interaction_enabled(enabled)
	for item in piece_items.values():
		item.set_interaction_enabled(enabled)
	for item in king_items.values():
		item.set_interaction_enabled(enabled)

func _key(type_id: StringName, color: String) -> String:
	return "%s:%s" % [type_id, color]
