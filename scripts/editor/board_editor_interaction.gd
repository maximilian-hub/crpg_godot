extends Node
class_name BoardEditorInteraction

@export var model: ChessBoardModel
@export var editor: BoardEditorController
@export var board_view: ChessBoardView

var dragging_from := Vector2i(-1, -1)
var hovered := Vector2i(-1, -1)

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
	if board_view.editor_square_pressed.is_connected(_on_square_pressed):
		return
	board_view.editor_square_pressed.connect(_on_square_pressed)
	board_view.editor_square_entered.connect(func(coord: Vector2i): hovered = coord)
	board_view.editor_square_exited.connect(func(coord: Vector2i):
		if hovered == coord: hovered = Vector2i(-1, -1))
	set_process_input(true)

func _on_square_pressed(coord: Vector2i) -> void:
	if not editor.editor_enabled or not model.is_settled():
		return
	hovered = coord
	if model.board[coord.x][coord.y] == null:
		editor.place_selected(coord)
	else:
		dragging_from = coord

func _input(event: InputEvent) -> void:
	if dragging_from.x < 0 or not editor.editor_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if hovered.x < 0:
			editor.remove_piece(dragging_from)
		elif hovered != dragging_from:
			editor.move_piece(dragging_from, hovered)
		dragging_from = Vector2i(-1, -1)
