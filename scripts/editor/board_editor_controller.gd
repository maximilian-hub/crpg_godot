extends Node
class_name BoardEditorController

enum Tool { CURSOR, DELETE, PIECE }

signal editor_enabled_changed(enabled: bool)
signal tool_selection_changed(tool: Tool, type_id: StringName, color: String)
signal edit_committed(before: ChessPosition, after: ChessPosition, label: String)
signal edit_rejected(errors: Array)
signal validation_changed(report: ChessPositionValidation)

@export var model: ChessBoardModel

var editor_enabled := false
var selected_tool := Tool.CURSOR
var selected_type_id: StringName = &"pawn"
var selected_color := "white"

func set_enabled(enabled: bool) -> bool:
	if model == null or not model.is_settled():
		return false
	editor_enabled = enabled
	editor_enabled_changed.emit(enabled)
	return true

func select_palette_piece(type_id: StringName, color: String) -> bool:
	if not ChessPieceCatalog.has_type(type_id) or color not in ["white", "black"]:
		return false
	selected_type_id = ChessPieceCatalog.normalize_type_id(type_id)
	selected_color = color
	selected_tool = Tool.PIECE
	tool_selection_changed.emit(selected_tool, selected_type_id, selected_color)
	return true

func select_cursor_tool() -> void:
	selected_tool = Tool.CURSOR
	tool_selection_changed.emit(selected_tool, selected_type_id, selected_color)

func select_delete_tool() -> void:
	selected_tool = Tool.DELETE
	tool_selection_changed.emit(selected_tool, selected_type_id, selected_color)

func has_selected_piece_tool() -> bool:
	return selected_tool == Tool.PIECE

func place_selected(at: Vector2i) -> bool:
	if not has_selected_piece_tool():
		return false
	return place_piece(selected_type_id, selected_color, at)

func place_piece(type_id: StringName, color: String, at: Vector2i) -> bool:
	var piece := ChessPieceCatalog.create_piece(type_id, color, at)
	if piece == null:
		return false
	return _commit(ChessPositionEditor.place_piece(model.capture_position(), piece.capture_piece_state()), "Place %s" % type_id)

func move_piece(from: Vector2i, to: Vector2i) -> bool:
	return _commit(ChessPositionEditor.move_piece(model.capture_position(), from, to), "Move piece")

func remove_piece(at: Vector2i) -> bool:
	return _commit(ChessPositionEditor.remove_piece(model.capture_position(), at), "Remove piece")

func clear_board() -> bool:
	return _commit(ChessPositionEditor.clear_board(model.capture_position()), "Clear board")

func set_current_turn(color: String) -> bool:
	return _commit(ChessPositionEditor.set_current_turn(model.capture_position(), color), "Set turn")

func load_position(position: ChessPosition, label := "Load position") -> bool:
	if not editor_enabled or not model.is_settled():
		return false
	var before := model.capture_position()
	if not model.load_position(position.copy()):
		return false
	var after := model.capture_position()
	edit_committed.emit(before, after, label)
	validation_changed.emit(ChessPositionValidator.validate(after))
	return true

func validate_current_position() -> ChessPositionValidation:
	return ChessPositionValidator.validate(model.capture_position())

func _commit(result: Dictionary, label: String) -> bool:
	if not editor_enabled or not model.is_settled():
		return false
	if result.get("position") == null:
		edit_rejected.emit(result.get("errors", []))
		return false
	return load_position(result["position"], label)
