extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var sandbox = SANDBOX.instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	var model: ChessBoardModel = sandbox.model
	_expect(not sandbox.authority_options.is_empty() and sandbox.authority_options[0].get_item_count() == 2, "sandbox exposes model and experimental Classic-core authority choices")
	var classic := _position([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4))])
	model.load_position(classic)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "sandbox-compatible Classic position accepts core authority")
	sandbox._refresh_control_states()
	_expect(String(model.get_live_authority_diagnostics().active) == "classic_core" and "Classic Core" in sandbox.authority_status_labels[0].text, "sandbox reports active core authority")
	model.load_position(classic.copy())
	_expect(model.active_live_authority == ChessBoardModel.LiveAuthority.CLASSIC_CORE, "compatible reset/load preserves requested core authority")
	var unsupported := _position([WraithKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	model.load_position(unsupported)
	sandbox._refresh_control_states()
	_expect(model.requested_live_authority == ChessBoardModel.LiveAuthority.CLASSIC_CORE and model.active_live_authority == ChessBoardModel.LiveAuthority.MODEL, "incompatible replacement keeps the request but safely activates model authority")
	_expect("Fallback:" in sandbox.authority_status_labels[0].text, "sandbox displays the incompatibility reason")
	model.load_position(classic.copy())
	_expect(model.active_live_authority == ChessBoardModel.LiveAuthority.CLASSIC_CORE, "later compatible replacement automatically restores requested core authority")
	if failures.is_empty():
		print("CLASSIC CORE SANDBOX AUTHORITY: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("CLASSIC CORE SANDBOX AUTHORITY: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _position(pieces: Array) -> ChessPosition:
	var result := ChessPosition.new()
	for piece in pieces: result.pieces.append(piece.capture_piece_state())
	return result


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
