extends Node
class_name BoardEditorInteraction

@export var model: ChessBoardModel
@export var editor: BoardEditorController
@export var board_view: ChessBoardView

enum DragSource { NONE, BOARD_PIECE, PALETTE_PIECE }

var dragging_from := Vector2i(-1, -1)
var hovered := Vector2i(-1, -1)
var requested_cursor_shape := Input.CURSOR_ARROW
var drag_ghost: PieceView = null
var drag_source := DragSource.NONE
var dragged_type_id: StringName = &""
var dragged_color := ""
var active_touch_index := -1
var latest_touch_position := Vector2.ZERO
var pending_touch_index := -1

func _ready() -> void:
	if board_view == null or editor == null or model == null:
		return
	_connect_board()

func configure(new_model: ChessBoardModel, new_editor: BoardEditorController, new_board_view: ChessBoardView) -> void:
	model = new_model
	editor = new_editor
	board_view = new_board_view
	_connect_board()

func _connect_board() -> void:
	if not board_view.editor_square_pressed.is_connected(_on_square_pressed):
		board_view.editor_square_pressed.connect(_on_square_pressed)
		board_view.editor_square_entered.connect(_on_square_entered)
		board_view.editor_square_exited.connect(_on_square_exited)
	if not editor.editor_enabled_changed.is_connected(_on_editor_enabled_changed):
		editor.editor_enabled_changed.connect(_on_editor_enabled_changed)
	if not model.board_rebuilt.is_connected(_on_board_rebuilt):
		model.board_rebuilt.connect(_on_board_rebuilt)
	set_process_input(true)

func _on_square_pressed(coord: Vector2i) -> void:
	if not editor.editor_enabled or not model.is_settled():
		return
	hovered = coord
	if editor.has_selected_piece_tool():
		editor.place_selected(coord)
	elif editor.selected_tool == BoardEditorController.Tool.DELETE:
		if model.board[coord.x][coord.y] != null:
			editor.remove_piece(coord)
	elif model.board[coord.x][coord.y] != null:
		drag_source = DragSource.BOARD_PIECE
		dragging_from = coord
		drag_ghost = board_view.create_piece_drag_ghost(model.board[coord.x][coord.y])
		active_touch_index = pending_touch_index
		pending_touch_index = -1
		_update_drag_ghost(latest_touch_position if active_touch_index >= 0 else Vector2.INF)
		_update_drag_cursor()

func begin_palette_drag(type_id: StringName, color: String, pointer_index := -1, initial_position := Vector2.INF) -> bool:
	if not editor.editor_enabled or not model.is_settled():
		return false
	var piece := ChessPieceCatalog.create_piece(type_id, color, Vector2i.ZERO)
	if piece == null:
		return false
	_cancel_drag()
	drag_source = DragSource.PALETTE_PIECE
	dragged_type_id = ChessPieceCatalog.normalize_type_id(type_id)
	dragged_color = color
	active_touch_index = pointer_index
	hovered = Vector2i(-1, -1)
	drag_ghost = board_view.create_piece_drag_ghost(piece)
	_update_drag_ghost(initial_position)
	_set_cursor_shape(Input.CURSOR_DRAG)
	return true

func _on_square_entered(coord: Vector2i) -> void:
	hovered = coord
	_update_drag_cursor()

func _on_square_exited(coord: Vector2i) -> void:
	if hovered == coord:
		hovered = Vector2i(-1, -1)
	_update_drag_cursor()

func _on_editor_enabled_changed(enabled: bool) -> void:
	if not enabled:
		_cancel_drag()

func _on_board_rebuilt(_board: Array) -> void:
	_cancel_drag()

func _update_drag_ghost(position := Vector2.INF) -> void:
	if is_instance_valid(drag_ghost):
		var target := board_view.get_global_mouse_position() if position == Vector2.INF else position
		board_view.position_piece_drag_ghost(drag_ghost, target)

func _remove_drag_ghost() -> void:
	if is_instance_valid(drag_ghost):
		drag_ghost.free()
	drag_ghost = null

func _update_drag_cursor() -> void:
	if drag_source == DragSource.NONE:
		return
	if hovered.x < 0:
		_set_cursor_shape(Input.CURSOR_FORBIDDEN)
	elif drag_source == DragSource.BOARD_PIECE and hovered == dragging_from:
		_set_cursor_shape(Input.CURSOR_DRAG)
	else:
		_set_cursor_shape(Input.CURSOR_CAN_DROP)

func _set_cursor_shape(shape: Input.CursorShape) -> void:
	requested_cursor_shape = shape
	Input.set_default_cursor_shape(shape)

func _cancel_drag() -> void:
	_remove_drag_ghost()
	drag_source = DragSource.NONE
	dragging_from = Vector2i(-1, -1)
	dragged_type_id = &""
	dragged_color = ""
	active_touch_index = -1
	pending_touch_index = -1
	_set_cursor_shape(Input.CURSOR_ARROW)

func cancel_drag() -> void:
	_cancel_drag()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		latest_touch_position = event.position
		pending_touch_index = event.index
	elif event is InputEventScreenTouch and not event.pressed and drag_source == DragSource.NONE:
		pending_touch_index = -1
	if drag_source == DragSource.NONE or not editor.editor_enabled:
		return
	if event is InputEventMouseMotion:
		_update_drag_ghost()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var source_kind := drag_source
		var source := dragging_from
		var type_id := dragged_type_id
		var color := dragged_color
		_remove_drag_ghost()
		if source_kind == DragSource.BOARD_PIECE:
			if hovered.x < 0:
				editor.remove_piece(source)
			elif hovered != source:
				editor.move_piece(source, hovered)
		elif source_kind == DragSource.PALETTE_PIECE and hovered.x >= 0:
			editor.place_piece(type_id, color, hovered)
		_cancel_drag()
	elif event is InputEventScreenDrag and (active_touch_index < 0 or event.index == active_touch_index):
		active_touch_index = event.index
		latest_touch_position = event.position
		hovered = board_view.coordinate_at_viewport_position(event.position)
		_update_drag_ghost(event.position)
	elif event is InputEventScreenTouch and not event.pressed and (active_touch_index < 0 or event.index == active_touch_index):
		var source_kind := drag_source
		var source := dragging_from
		var type_id := dragged_type_id
		var color := dragged_color
		hovered = board_view.coordinate_at_viewport_position(event.position)
		_remove_drag_ghost()
		if source_kind == DragSource.BOARD_PIECE and hovered.x >= 0 and hovered != source:
			editor.move_piece(source, hovered)
		elif source_kind == DragSource.PALETTE_PIECE and hovered.x >= 0:
			editor.place_piece(type_id, color, hovered)
		_cancel_drag()

func _exit_tree() -> void:
	_set_cursor_shape(Input.CURSOR_ARROW)
