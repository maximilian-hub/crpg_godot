extends Node

const ActionCodec := preload("res://scripts/state/chess_action_codec.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_startup_modes_and_state_parity()
	_test_explicit_disposal_owns_destroyed_pieces()
	_test_position_replacement_disposes_old_pieces()
	_test_predelete_cleanup_backstop()
	_test_repeated_lifecycle()
	if failures.is_empty():
		print("SIMULATION LIFECYCLE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_startup_modes_and_state_parity() -> void:
	var live := ChessBoardModel.new()
	live.diagnostic_logging_enabled = false
	add_child(live)
	_expect(live.is_initialized, "default startup initializes a live battle")
	_expect(live.owned_piece_registration_count == 32, "default startup registers exactly 32 pieces")
	var position := live.capture_position()
	var expected_json := ChessPositionCodec.to_json(position, false)
	var expected_actions := _action_keys(live.get_legal_primary_actions(live.current_turn))

	var simulation := ChessBoardModel.new()
	simulation.diagnostic_logging_enabled = false
	simulation.startup_mode = ChessBoardModel.StartupMode.EMPTY
	add_child(simulation)
	_expect(not simulation.is_initialized, "empty startup does not initialize a default battle")
	_expect(simulation.board.is_empty(), "empty startup creates no board")
	_expect(simulation.owned_piece_registration_count == 0, "empty startup creates no throwaway pieces")
	_expect(simulation.load_position(position.copy()), "empty startup accepts an authoritative position")
	_expect(simulation.is_settled(), "loaded empty-start simulation is settled")
	_expect(ChessPositionCodec.to_json(simulation.capture_position(), false) == expected_json, "empty-start load preserves serialized state")
	_expect(_action_keys(simulation.get_legal_primary_actions(simulation.current_turn)) == expected_actions, "empty-start load preserves legal actions")

	simulation.free()
	live.free()


func _test_explicit_disposal_owns_destroyed_pieces() -> void:
	var model := _loaded_simulation()
	var refs: Array[WeakRef] = []
	for row in model.board:
		for piece in row:
			if piece != null: refs.append(weakref(piece))
	var victim: ModelPiece = model.board[1][0]
	var victim_ref: WeakRef = weakref(victim)
	model.destroy_piece(victim, true)
	_expect(victim_ref.get_ref() != null, "destroyed piece remains valid until model disposal")
	var registered := model.owned_piece_registration_count
	var disposed := model.dispose_owned_state()
	_expect(disposed == registered, "explicit disposal releases surviving and destroyed owned pieces")
	_expect(model.owned_piece_disposal_count == registered, "disposal diagnostics balance registrations")
	_expect(model.dispose_owned_state() == 0, "explicit disposal is idempotent")
	for reference in refs:
		_expect(reference.get_ref() == null, "explicit disposal invalidates every owned piece")
	model.free()


func _test_predelete_cleanup_backstop() -> void:
	var model := _loaded_simulation()
	var reference: WeakRef = weakref(model.board[0][0])
	model.free()
	_expect(reference.get_ref() == null, "freeing a model invokes owned-piece cleanup")


func _test_position_replacement_disposes_old_pieces() -> void:
	var model := _loaded_simulation()
	var position := model.capture_position()
	var old_reference: WeakRef = weakref(model.board[0][0])
	_expect(model.load_position(position), "settled simulation accepts position replacement")
	_expect(old_reference.get_ref() == null, "position replacement disposes the previous owned pieces")
	_expect(model.owned_piece_registration_count == 64, "position replacement records both reconstructed armies")
	_expect(model.dispose_owned_state() == 32, "position replacement retains ownership of only the current army")
	_expect(model.owned_piece_disposal_count == 64, "replacement and final cleanup balance every registered piece")
	model.free()


func _test_repeated_lifecycle() -> void:
	var references: Array[WeakRef] = []
	for _index in range(40):
		var model := _loaded_simulation()
		references.append(weakref(model.board[0][0]))
		var registered := model.owned_piece_registration_count
		var disposed := model.dispose_owned_state()
		_expect(disposed == registered, "repeated simulation balances registered and disposed pieces")
		model.free()
	for reference in references:
		_expect(reference.get_ref() == null, "repeated simulations retain no sampled pieces")


func _loaded_simulation() -> ChessBoardModel:
	var source := ChessBoardModel.new()
	source.diagnostic_logging_enabled = false
	source.initialize_battle()
	var position := source.capture_position()
	source.free()
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	add_child(model)
	if not model.load_position(position): failures.append("fixture position failed to load")
	return model


func _action_keys(actions: Array[ChessPrimaryAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(JSON.stringify(ActionCodec.describe(action)))
	result.sort()
	return result


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
