extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")

func _ready() -> void:
	var sandbox: BoardSandbox = SANDBOX.instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	var model: ChessBoardModel = sandbox.model
	var view: ChessBoardView = sandbox.get_node("ChessGame/CanvasLayer/ChessBoard")
	var adapter: ChessPresentationAdapter = sandbox.get_node("ChessGame/ChessPresentationAdapter")
	var failures: Array[String] = []
	_check(model != null and sandbox.editor.editor_enabled, "sandbox starts in Edit Mode", failures)
	_check(model.capture_position().pieces.size() == 32, "sandbox starts at normal position", failures)
	_check(view.scale_world_with_projection, "sandbox inherits projection-scaled piece presentation", failures)
	_check(is_equal_approx(view.viewport_height_width_ratio, 1.0), "sandbox inherits fluid board height ratio", failures)
	_check(is_equal_approx(view.viewport_width_cap_ratio, 0.72), "sandbox inherits fluid board width cap", failures)
	sandbox.editor.clear_board()
	await get_tree().process_frame
	_check(_count(model) == 0, "sandbox Clear empties authoritative model", failures)
	_check(view.get_node("Pieces").get_child_count() == 0 and adapter.piece_views.is_empty(), "whole-board rebuild removes stale PieceViews", failures)
	sandbox.undo()
	await get_tree().process_frame
	_check(_count(model) == 32, "sandbox Undo restores model", failures)
	_check(view.get_node("Pieces").get_child_count() == 32 and adapter.piece_views.size() == 32, "sandbox Undo rebuilds presentation mapping", failures)
	if failures.is_empty():
		print("BOARD SANDBOX CHARACTERIZATION: PASS (8 checks)")
		get_tree().quit(0)
	else:
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)

func _count(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null: count += 1
	return count

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
