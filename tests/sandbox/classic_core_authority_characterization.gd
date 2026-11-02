extends Node

const SANDBOX := preload("res://scenes/sandbox/board_sandbox.tscn")
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var sandbox = SANDBOX.instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	var model: ChessBoardModel = sandbox.model
	_expect(not sandbox.authority_options.is_empty() and sandbox.authority_options[0].get_item_count() == 1 and sandbox.authority_options[0].disabled, "sandbox shows pure core as the sole authoritative engine")
	var classic := _position([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4))])
	_expect(model.load_position(classic), "sandbox-compatible Classic position loads through the core")
	sandbox._refresh_control_states()
	_expect(String(model.get_live_authority_diagnostics().active) == "classic_core" and "Pure Core" in sandbox.authority_status_labels[0].text, "sandbox reports mandatory pure-core authority")
	var archer := _position([ArcherKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	_expect(model.load_position(archer), "migrated Archer positions also retain core authority")
	var before := ChessPositionCodec.to_json(model.capture_position(), false)
	var invalid := archer.copy(); invalid.pieces[0].custom_state["unsupported"] = true
	_expect(not model.load_position(invalid) and ChessPositionCodec.to_json(model.capture_position(), false) == before, "unsupported rule state is rejected without falling back or replacing the board")
	if failures.is_empty():
		print("PURE CORE SANDBOX AUTHORITY: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("PURE CORE SANDBOX AUTHORITY: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _position(pieces: Array) -> ChessPosition:
	var result := ChessPosition.new()
	for piece in pieces: result.pieces.append(piece.capture_piece_state())
	return result


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
