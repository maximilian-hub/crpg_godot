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
var king_select_button: Button
var king_picker: PanelContainer
var king_picker_scroll: ScrollContainer
var king_type_ids: Array[StringName] = []
var palette_enabled := true
var mobile_layout := false
var last_drag_pointer_index := -1
var last_drag_viewport_position := Vector2.ZERO
var mobile_scroll: ScrollContainer
var mobile_row: HBoxContainer
var mobile_pressed_item = null
var mobile_pointer_index := -1
var mobile_press_position := Vector2.ZERO
var mobile_drag_started := false
var king_picker_buttons: Dictionary = {}
var mobile_picker_pointer := -1
var mobile_pressed_king_button: Button
var mobile_picker_last_position := Vector2.ZERO
var mobile_picker_scrolling := false

func configure_mobile_layout() -> void:
	mobile_layout = true

func _ready() -> void:
	custom_minimum_size = Vector2(156.0, 0.0) if not mobile_layout else Vector2(0.0, 92.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("3a383f")
	panel_style.border_color = Color("66616d")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", panel_style)
	if mobile_layout:
		_build_mobile()
	else:
		_build()

func _build_mobile() -> void:
	mobile_scroll = ScrollContainer.new()
	mobile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	mobile_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mobile_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(mobile_scroll)
	mobile_row = HBoxContainer.new()
	mobile_row.add_theme_constant_override("separation", 6)
	mobile_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mobile_scroll.add_child(mobile_row)
	mobile_scroll.resized.connect(_sync_mobile_row_width)
	cursor_item = _new_item()
	cursor_item.configure_cursor()
	mobile_row.add_child(cursor_item)
	delete_item = _new_item()
	delete_item.configure_delete()
	mobile_row.add_child(delete_item)
	for type_id in ChessPieceCatalog.get_palette_type_ids(&"ordinary"):
		for color in ["white", "black"]:
			var item: Variant = _new_item()
			item.configure_piece(type_id, color)
			mobile_row.add_child(item)
			piece_items[_key(type_id, color)] = item
	king_selector = OptionButton.new()
	king_type_ids = ChessPieceCatalog.get_palette_type_ids(&"king")
	for type_id in king_type_ids:
		king_selector.add_item(ChessPieceCatalog.get_definition(type_id).get("name", String(type_id)))
	king_selector.item_selected.connect(_on_king_selected)
	king_selector.visible = false
	add_child(king_selector)
	for color in ["white", "black"]:
		var item: Variant = _new_item()
		mobile_row.add_child(item)
		king_items[color] = item
	king_select_button = Button.new()
	king_select_button.custom_minimum_size.x = 176.0
	king_select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	king_select_button.pressed.connect(_show_king_picker)
	_enable_touch_activation(king_select_button)
	mobile_row.add_child(king_select_button)
	_build_king_picker()
	_rebuild_king_items()
	_update_mobile_king_button()
	call_deferred(&"_sync_mobile_row_width")

func _sync_mobile_row_width() -> void:
	if mobile_scroll != null and mobile_row != null:
		mobile_row.custom_minimum_size.x = mobile_scroll.size.x
	_layout_king_picker()

func _build_king_picker() -> void:
	king_picker = PanelContainer.new()
	king_picker.name = "KingPicker"
	king_picker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	king_picker.offset_left = -340.0
	king_picker.offset_right = 0.0
	king_picker.visible = false
	add_child(king_picker)
	king_picker_scroll = ScrollContainer.new()
	king_picker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	king_picker_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	king_picker.add_child(king_picker_scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 300.0
	column.add_theme_constant_override("separation", 6)
	king_picker_scroll.add_child(column)
	for index in range(king_type_ids.size()):
		var type_id := king_type_ids[index]
		var button := Button.new()
		button.text = ChessPieceCatalog.get_definition(type_id).get("name", String(type_id))
		button.custom_minimum_size.y = 52.0
		button.pressed.connect(_select_mobile_king.bind(index))
		_enable_touch_activation(button)
		column.add_child(button)
		king_picker_buttons[button] = index

func _layout_king_picker() -> void:
	if king_picker == null:
		return
	var total_height := maxf(160.0, king_type_ids.size() * 58.0 + 12.0)
	var available_height := maxf(180.0, global_position.y - 78.0)
	var picker_height := minf(total_height, available_height)
	king_picker.offset_top = -picker_height - 8.0
	king_picker.offset_bottom = -8.0

func _show_king_picker() -> void:
	king_picker.visible = not king_picker.visible

func _select_mobile_king(index: int) -> void:
	king_selector.select(index)
	_on_king_selected(index)
	king_picker.visible = false

func mobile_overlay_contains(position: Vector2) -> bool:
	return king_picker != null and king_picker.visible and king_picker.get_global_rect().has_point(position)

func mobile_contains(position: Vector2) -> bool:
	if visible and get_global_rect().has_point(position):
		return true
	if mobile_overlay_contains(position):
		return true
	if king_select_button != null and king_select_button.is_visible_in_tree() and king_select_button.get_global_rect().has_point(position):
		return true
	for item in _mobile_palette_items():
		if item.is_visible_in_tree() and item.get_global_rect().has_point(position):
			return true
	return false

func handle_mobile_touch_pressed(position: Vector2, pointer_index: int) -> bool:
	if king_picker != null and king_picker.visible:
		for button: Button in king_picker_buttons:
			if button.get_global_rect().has_point(position):
				mobile_picker_pointer = pointer_index
				mobile_pressed_king_button = button
				mobile_press_position = position
				mobile_picker_last_position = position
				mobile_picker_scrolling = false
				return true
		if king_picker.get_global_rect().has_point(position):
			mobile_picker_pointer = pointer_index
			mobile_pressed_king_button = null
			mobile_press_position = position
			mobile_picker_last_position = position
			mobile_picker_scrolling = false
			return true
		king_picker.visible = false
		return false
	if king_select_button != null and king_select_button.get_global_rect().has_point(position):
		_show_king_picker()
		return true
	for item in _mobile_palette_items():
		if item.get_global_rect().has_point(position):
			_on_item_selected(item)
			mobile_pressed_item = item
			mobile_pointer_index = pointer_index
			mobile_press_position = position
			mobile_drag_started = false
			return true
	return false

func handle_mobile_touch_drag(position: Vector2, pointer_index: int) -> bool:
	if pointer_index == mobile_picker_pointer:
		var delta := position - mobile_picker_last_position
		if position.distance_to(mobile_press_position) >= PaletteItem.DRAG_THRESHOLD or mobile_picker_scrolling:
			mobile_picker_scrolling = true
			king_picker_scroll.scroll_vertical -= int(delta.y)
		mobile_picker_last_position = position
		return true
	if pointer_index != mobile_pointer_index or mobile_pressed_item == null:
		return false
	if not mobile_drag_started and not mobile_pressed_item.is_cursor_tool and not mobile_pressed_item.is_delete_tool and position.distance_to(mobile_press_position) >= PaletteItem.DRAG_THRESHOLD:
		mobile_drag_started = true
		last_drag_pointer_index = pointer_index
		last_drag_viewport_position = position
		piece_drag_requested.emit(mobile_pressed_item.type_id, mobile_pressed_item.color)
	return true

func handle_mobile_touch_released(pointer_index: int, position := Vector2.INF) -> bool:
	if pointer_index == mobile_picker_pointer:
		if not mobile_picker_scrolling and mobile_pressed_king_button != null and mobile_pressed_king_button.get_global_rect().has_point(position):
			_select_mobile_king(int(king_picker_buttons[mobile_pressed_king_button]))
		mobile_picker_pointer = -1
		mobile_pressed_king_button = null
		mobile_picker_scrolling = false
		return true
	if pointer_index != mobile_pointer_index:
		return false
	mobile_pressed_item = null
	mobile_pointer_index = -1
	mobile_drag_started = false
	return true

func _mobile_palette_items() -> Array:
	var items: Array = [cursor_item, delete_item]
	items.append_array(piece_items.values())
	items.append_array(king_items.values())
	return items

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
	if mobile_layout:
		item.configure_mobile_layout()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		last_drag_pointer_index = item.active_pointer_index
		last_drag_viewport_position = item.drag_viewport_position
		piece_drag_requested.emit(item.type_id, item.color)

func _on_king_selected(_index: int) -> void:
	var prior_selected_color := ""
	for color in king_items:
		if king_items[color].selected_state:
			prior_selected_color = color
	_rebuild_king_items()
	_update_mobile_king_button()
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

func _update_mobile_king_button() -> void:
	if king_select_button == null:
		return
	var selected_id := get_selected_king_type_id()
	var selected_name: String = ChessPieceCatalog.get_definition(selected_id).get("name", String(selected_id))
	king_select_button.text = "Select King\n%s" % selected_name

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

func _enable_touch_activation(button: Button) -> void:
	button.gui_input.connect(func(event: InputEvent):
		if not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			button.set_meta(&"mobile_touch_index", touch.index)
			button.accept_event()
			return
		if int(button.get_meta(&"mobile_touch_index", -1)) != touch.index:
			return
		button.set_meta(&"mobile_touch_index", -1)
		button.accept_event()
		if not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(touch.position):
			button.pressed.emit()
	)
