extends Node

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	await _test_authoritative_primary_actions()
	await _test_cpu_capture_and_tie_breaking()
	await _test_cpu_active_ability()
	await _test_cpu_with_no_legal_action()
	await _test_cpu_owned_reaction()
	await _test_human_owned_reaction_is_untouched()

	if failures.is_empty():
		print("HEADLESS CPU CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	printerr("HEADLESS CPU CHARACTERIZATION: FAIL")
	get_tree().quit(1)


func _test_authoritative_primary_actions() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var rook := Rook.new("white", Vector2i(7, 0))
	var pawn := Pawn.new("black", Vector2i(3, 3))
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(rook, rook.coordinate)
	model.add_piece(pawn, pawn.coordinate)

	var actions := model.get_legal_primary_actions("white")
	_expect(_has_action(actions, ChessPrimaryAction.Kind.MOVE, rook), "primary list includes normal moves")
	_expect(_has_action(actions, ChessPrimaryAction.Kind.ACTIVE_ABILITY, arakne, pawn.coordinate), "primary list includes ready active abilities")
	_expect(model.get_legal_primary_actions("black").is_empty(), "primary list rejects the wrong-turn color")

	arakne.stunned = true
	actions = model.get_legal_primary_actions("white")
	_expect(not _has_action(actions, ChessPrimaryAction.Kind.MOVE, arakne), "primary list excludes stunned-piece moves")
	_expect(not _has_action(actions, ChessPrimaryAction.Kind.ACTIVE_ABILITY, arakne), "primary list excludes stunned active abilities")
	arakne.stunned = false
	model.action_in_progress = true
	_expect(model.get_legal_primary_actions("white").is_empty(), "primary list is empty during resolution")
	model.free()


func _test_cpu_capture_and_tie_breaking() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var rook := Rook.new("black", Vector2i(0, 0))
	var pawn_a := Pawn.new("white", Vector2i(0, 3))
	var pawn_b := Pawn.new("white", Vector2i(3, 0))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(pawn_a, pawn_a.coordinate)
	model.add_piece(pawn_b, pawn_b.coordinate)

	var cpu := _add_cpu(model, "black", false)
	var actions := model.get_legal_primary_actions("black")
	var selected_targets: Dictionary = {}
	for seed_value in range(1, 25):
		cpu.set_random_seed(seed_value)
		var selected := cpu.choose_primary_action(actions)
		_expect(selected.target == pawn_a.coordinate or selected.target == pawn_b.coordinate, "tie-breaking never chooses below the top score")
		selected_targets[selected.target] = true
	_expect(selected_targets.size() == 2, "seeded tie-breaking can choose either equal best capture")

	cpu.set_random_seed(7)
	cpu.configure(true, "black")
	await _wait_frames(3)
	_expect(model.current_turn == "white", "CPU submits and completes a primary action")
	_expect(model.board[0][3] == rook or model.board[3][0] == rook, "CPU prefers a legal capture over quiet moves")
	cpu.queue_free()
	model.free()


func _test_cpu_active_ability() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var pawn := Pawn.new("black", Vector2i(3, 3))
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(pawn, pawn.coordinate)
	var cpu := _add_cpu(model, "white", true)
	await _wait_frames(3)
	_expect(model.board[3][3] == null, "CPU active ability resolves its target")
	_expect(arakne.coordinate == Vector2i(4, 4) and arakne.current_cooldown > 0, "CPU used the active ability rather than a normal capture")
	cpu.queue_free()
	model.free()


func _test_cpu_with_no_legal_action() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var action_count := {"value": 0}
	model.action_started.connect(func(_color: String): action_count["value"] += 1)
	var cpu := _add_cpu(model, "black", true)
	await _wait_frames(4)
	_expect(action_count["value"] == 0 and model.current_turn == "black", "CPU with no legal action stops without submitting or retrying")
	cpu.queue_free()
	model.free()


func _test_cpu_owned_reaction() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	var cpu := _add_cpu(model, "black", true)
	model.reaction_selection_resolved.connect(
		func(_piece: ModelPiece, _action_type: String, _target: Vector2i): cpu.is_enabled = false,
		CONNECT_ONE_SHOT
	)
	model.begin_action("white")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	await _wait_frames(3)
	_expect(not model.has_pending_reaction(), "CPU resolves its Model-owned reaction selection")
	_expect(_count_type(model, "bone_pawn") == 1, "CPU Raise Dead creates a Bone Pawn")
	cpu.queue_free()
	model.free()


func _test_human_owned_reaction_is_untouched() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	var bishop := Bishop.new("black", Vector2i(4, 4))
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	var cpu := _add_cpu(model, "black", true)
	model.begin_action("white")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	await _wait_frames(2)
	_expect(model.has_pending_reaction(), "CPU leaves a human-owned reaction pending")
	_expect(model.get_pending_reaction()["calling_piece"] == necromancer, "pending human reaction keeps its owner")
	cpu.queue_free()
	model.free()


func _add_cpu(model: ChessBoardModel, color: String, enabled: bool) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure(enabled, color)
	return cpu


func _new_empty_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null:
				model.unregister_piece(piece)
	model.board.clear()
	for row_index in range(8):
		var row: Array = []
		for column_index in range(8):
			row.append(null)
		model.board.append(row)
	model.last_move = {}
	model.current_turn = "white"
	model.battle_over = false
	model.battle_result = ""
	model.defeated_king_colors.clear()
	model.selection_queue.clear()
	model.pending_reaction.clear()
	model.action_in_progress = false
	model.action_owner_color = ""
	return model


func _has_action(actions: Array[ChessPrimaryAction], kind: ChessPrimaryAction.Kind, piece: ModelPiece, target := Vector2i(-1, -1)) -> bool:
	for action in actions:
		if action.kind == kind and action.piece == piece and (target == Vector2i(-1, -1) or action.target == target):
			return true
	return false


func _count_type(model: ChessBoardModel, type: String) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null and piece.type == type:
				count += 1
	return count


func _wait_frames(frame_count: int) -> void:
	for frame in range(frame_count):
		await get_tree().process_frame


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
