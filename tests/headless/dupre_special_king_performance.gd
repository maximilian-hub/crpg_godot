extends Node

var failures: Array[String] = []


func _ready() -> void:
	var classic := await _benchmark(&"classic")
	var minotaur := await _benchmark(&"minotaur")
	var rhetorician := await _benchmark(&"rhetorician")
	var necromancer := await _benchmark(&"necromancer")
	print("DUPRE SPECIAL KING PERFORMANCE: ", JSON.stringify({
		"classic": classic,
		"minotaur": minotaur,
		"rhetorician": rhetorician,
		"necromancer": necromancer,
	}))
	for result in [classic, minotaur, rhetorician, necromancer]:
		if not bool(result.get("produced_action", false)):
			failures.append(String(result.label) + " produced no action")
		if int(result.get("invalid_root_candidates", 0)) > 0:
			failures.append(String(result.label) + " produced an invalid simulation candidate")
		if int(result.get("elapsed_usec", 0)) > 6_000_000:
			failures.append(String(result.label) + " exceeded the configured search budget by more than scheduling tolerance")
	if int(minotaur.get("exact_root_candidates", 0)) < 1 or bool(minotaur.get("fallback_used", true)):
		failures.append("crowded Minotaur benchmark did not establish an exact candidate before timeout")
	if failures.is_empty():
		print("DUPRE SPECIAL KING PERFORMANCE: PASS")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _benchmark(kind: StringName) -> Dictionary:
	var model := _position(kind)
	add_child(model)
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(90210)
	(cpu.brain as DupreAiBrain).max_book_moves = 0
	var started := Time.get_ticks_usec()
	var thought = await cpu.think()
	var elapsed := Time.get_ticks_usec() - started
	var profile: Dictionary = cpu.brain.get_last_profile()
	profile["label"] = kind
	profile["elapsed_usec"] = elapsed
	profile["produced_action"] = thought != null
	cpu.queue_free(); model.queue_free()
	await get_tree().process_frame
	return profile


func _position(kind: StringName) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	var white_king: KingPiece
	match kind:
		&"minotaur":
			white_king = MinotaurKing.new("white", Vector2i(7, 4))
			white_king.set_cooldown(0)
		&"rhetorician":
			white_king = RhetoricianKing.new("white", Vector2i(7, 4))
			white_king.set_cooldown(0)
		&"necromancer":
			white_king = NecromancerKing.new("white", Vector2i(7, 4))
			white_king.set_cooldown(0)
		_:
			white_king = ClassicKing.new("white", Vector2i(7, 4))
	var black_king := ClassicKing.new("black", Vector2i(0, 4))
	if kind == &"minotaur":
		black_king.max_hp = 4
		black_king.current_hp = 4
	for piece in [
		white_king, Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)), Knight.new("white", Vector2i(5, 2)), Pawn.new("white", Vector2i(6, 0)),
		black_king, Queen.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(0, 0)), Knight.new("black", Vector2i(2, 2)), Pawn.new("black", Vector2i(1, 0)),
	]: model.add_piece(piece, piece.coordinate)
	model.current_turn = "white"
	return model
