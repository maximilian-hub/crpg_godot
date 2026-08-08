extends Node

const ChessActionSimulatorScript = preload("res://scripts/ai/chess_action_simulator.gd")

class RejectOnceModel extends ChessBoardModel:
	var move_rejections_remaining: int = 0
	var reaction_rejections_remaining: int = 0

	func submit_move(piece: ModelPiece, to: Vector2i) -> bool:
		if move_rejections_remaining > 0:
			move_rejections_remaining -= 1
			return false
		return await super.submit_move(piece, to)

	func submit_reaction_selection(coord: Vector2i) -> bool:
		if reaction_rejections_remaining > 0:
			reaction_rejections_remaining -= 1
			return false
		return await super.submit_reaction_selection(coord)

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	await _test_authoritative_primary_actions()
	await _test_cpu_capture_and_tie_breaking()
	await _test_cpu_avoids_defended_capture()
	await _test_cpu_avoids_immediate_king_attack()
	await _test_tactical_simulation_preserves_live_model()
	await _test_simulation_clones_stale_last_move_safely()
	await _test_cpu_does_not_act_on_other_turn()
	await _test_cpu_active_ability()
	await _test_cpu_with_no_legal_action()
	await _test_rejected_commands_retry_without_spinning()
	await _test_cpu_owned_reaction()
	await _test_human_owned_reaction_is_untouched()
	await _test_two_cpu_turns()
	await _test_two_cpu_reaction_ownership()
	await _test_two_cpu_battle_completion_stops_scheduling()
	await _test_long_headless_cpu_battle()

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
		_expect(selected in actions, "CPU chooses only an action supplied by the Model")
		_expect(selected.target == pawn_a.coordinate or selected.target == pawn_b.coordinate, "tie-breaking never chooses below the top score")
		selected_targets[selected.target] = true
	_expect(selected_targets.size() == 2, "seeded tie-breaking can choose either equal best capture")
	cpu.set_random_seed(12345)
	var first_seeded_choice := cpu.choose_primary_action(actions)
	cpu.set_random_seed(12345)
	var repeated_seeded_choice := cpu.choose_primary_action(actions)
	_expect(first_seeded_choice == repeated_seeded_choice, "resetting the RNG seed reproduces the same decision")

	cpu.set_random_seed(7)
	cpu.configure(true, "black")
	await _wait_frames(3)
	_expect(model.current_turn == "white", "CPU submits and completes a primary action")
	_expect(model.board[0][3] == rook or model.board[3][0] == rook, "CPU prefers a legal capture over quiet moves")
	cpu.queue_free()
	model.free()


func _test_cpu_avoids_defended_capture() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var queen := Queen.new("black", Vector2i(4, 4))
	var defended_pawn := Pawn.new("white", Vector2i(4, 2))
	var safe_pawn := Pawn.new("white", Vector2i(2, 4))
	var defending_rook := Rook.new("white", Vector2i(4, 0))
	model.add_piece(queen, queen.coordinate)
	model.add_piece(defended_pawn, defended_pawn.coordinate)
	model.add_piece(safe_pawn, safe_pawn.coordinate)
	model.add_piece(defending_rook, defending_rook.coordinate)
	var cpu := _add_cpu(model, "black", false)
	cpu.set_random_seed(11)
	var selected: ChessPrimaryAction = await cpu.choose_tactical_action(
		model.get_legal_primary_actions("black")
	)
	_expect(selected.target == safe_pawn.coordinate, "CPU declines a Pawn capture that permits an immediate Queen recapture")
	_expect(model.board[4][4] == queen and model.board[4][2] == defended_pawn, "tactical capture evaluation does not alter the live board")
	cpu.queue_free()
	model.free()


func _test_cpu_avoids_immediate_king_attack() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var king := ClassicKing.new("black", Vector2i(4, 4))
	var enemy_rook := Rook.new("white", Vector2i(4, 0))
	model.add_piece(king, king.coordinate)
	model.add_piece(enemy_rook, enemy_rook.coordinate)
	var cpu := _add_cpu(model, "black", false)
	cpu.set_random_seed(23)
	var selected: ChessPrimaryAction = await cpu.choose_tactical_action(
		model.get_legal_primary_actions("black")
	)
	_expect(selected.piece == king and selected.target.x != 4, "CPU moves its threatened King off the enemy's immediate attack line")
	cpu.queue_free()
	model.free()


func _test_tactical_simulation_preserves_live_model() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var pawn := Pawn.new("black", Vector2i(3, 3))
	arakne.has_moved = true
	arakne.stunned = true
	arakne.stun_timer = 2
	arakne.current_cooldown = 0
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(pawn, pawn.coordinate)
	arakne.stunned = false
	var cpu := _add_cpu(model, "white", false)
	var selected: ChessPrimaryAction = await cpu.choose_tactical_action(
		model.get_legal_primary_actions("white")
	)
	_expect(selected != null, "tactical evaluator produces an action from an isolated Model copy")
	_expect(model.current_turn == "white" and not model.action_in_progress and not model.has_pending_reaction(), "tactical evaluation preserves live resolver and turn state")
	_expect(arakne.current_hp == arakne.max_hp and arakne.current_cooldown == 0 and arakne.has_moved, "tactical evaluation preserves live piece state")
	_expect(model.board[4][4] == arakne and model.board[3][3] == pawn, "ability simulation preserves every live fixture piece")
	cpu.queue_free()
	model.free()


func _test_simulation_clones_stale_last_move_safely() -> void:
	var model := _new_empty_model()
	var white_pawn := Pawn.new("white", Vector2i(3, 4))
	var removed_black_pawn := Pawn.new("black", Vector2i(3, 5))
	model.add_piece(white_pawn, white_pawn.coordinate)
	model.add_piece(removed_black_pawn, removed_black_pawn.coordinate)
	model.last_move = {
		"piece": removed_black_pawn,
		"piece_type": "pawn",
		"piece_color": "black",
		"from": Vector2i(1, 5),
		"to": Vector2i(3, 5),
	}
	model.destroy_piece(removed_black_pawn, true)
	var simulator: RefCounted = ChessActionSimulatorScript.new()
	var context: Dictionary = simulator.clone_model(model)
	var clone: ChessBoardModel = context["model"]
	var cloned_pawn: Pawn = context["piece_map"][white_pawn]
	_expect(clone.last_move.get("piece") == null, "simulation permits a removed last mover to have no cloned reference")
	_expect(clone.last_move.get("piece_type") == "pawn" and clone.last_move.get("piece_color") == "black", "simulation preserves immutable last-move metadata")
	_expect(Vector2i(2, 5) not in cloned_pawn.get_legal_moves(), "simulation enumerates Pawn moves safely after the last mover is removed")
	_expect(not clone.get_legal_primary_actions("white").is_empty(), "stale last-move metadata does not abort authoritative action enumeration")
	clone.free()
	model.free()


func _test_cpu_does_not_act_on_other_turn() -> void:
	var model := _new_empty_model()
	var white_rook := Rook.new("white", Vector2i(7, 0))
	model.add_piece(white_rook, white_rook.coordinate)
	var action_count := {"value": 0}
	model.action_started.connect(func(_color: String): action_count["value"] += 1)
	var cpu := _add_cpu(model, "black", true)
	await _wait_frames(4)
	_expect(action_count["value"] == 0 and model.current_turn == "white", "CPU does not act during the other color's turn")
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
	var stall_count := {"value": 0}
	model.action_started.connect(func(_color: String): action_count["value"] += 1)
	var cpu := _add_cpu(model, "black", true)
	cpu.decision_stalled.connect(func(_color: String, _decision_type: String): stall_count["value"] += 1)
	await _wait_frames(4)
	_expect(action_count["value"] == 0 and model.current_turn == "black", "CPU with no legal action stops without submitting or retrying")
	_expect(stall_count["value"] == 1, "CPU reports a no-legal-action stall instead of failing silently")
	cpu.queue_free()
	model.free()


func _test_rejected_commands_retry_without_spinning() -> void:
	var move_model := _new_empty_reject_model()
	var rook := Rook.new("white", Vector2i(7, 0))
	var pawn := Pawn.new("black", Vector2i(7, 3))
	move_model.add_piece(rook, rook.coordinate)
	move_model.add_piece(pawn, pawn.coordinate)
	move_model.move_rejections_remaining = 1
	var move_cpu := _add_cpu(move_model, "white", false)
	var move_rejections := {"value": 0}
	move_cpu.command_rejected.connect(
		func(_color: String, command_type: String, _attempt: int):
			if command_type == "primary":
				move_rejections["value"] += 1
	)
	move_cpu.configure(true, "white")
	await _wait_frames(5)
	_expect(move_rejections["value"] == 1, "CPU observes a rejected primary command")
	_expect(move_model.board[7][3] == rook and move_model.current_turn == "black", "CPU retries one rejected primary command successfully")
	move_cpu.queue_free()
	move_model.free()

	var reaction_model := _new_empty_reject_model()
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	reaction_model.add_piece(necromancer, necromancer.coordinate)
	reaction_model.add_piece(bishop, bishop.coordinate)
	reaction_model.reaction_rejections_remaining = 1
	var reaction_cpu := _add_cpu(reaction_model, "black", true)
	var reaction_rejections := {"value": 0}
	reaction_cpu.command_rejected.connect(
		func(_color: String, command_type: String, _attempt: int):
			if command_type == "reaction":
				reaction_rejections["value"] += 1
	)
	reaction_model.reaction_selection_resolved.connect(
		func(_piece: ModelPiece, _action_type: String, _target: Vector2i): reaction_cpu.is_enabled = false,
		CONNECT_ONE_SHOT
	)
	reaction_model.begin_action("white")
	reaction_model.destroy_piece(bishop, true)
	await reaction_model.continue_action_resolution()
	await _wait_frames(5)
	_expect(reaction_rejections["value"] == 1, "CPU observes a rejected reaction command")
	_expect(not reaction_model.has_pending_reaction() and _count_type(reaction_model, "bone_pawn") == 1, "CPU retries one rejected reaction command successfully")
	reaction_cpu.is_enabled = false
	reaction_cpu.queue_free()
	reaction_model.free()

	var bounded_model := _new_empty_reject_model()
	var bounded_rook := Rook.new("white", Vector2i(7, 0))
	var bounded_pawn := Pawn.new("black", Vector2i(7, 3))
	bounded_model.add_piece(bounded_rook, bounded_rook.coordinate)
	bounded_model.add_piece(bounded_pawn, bounded_pawn.coordinate)
	bounded_model.move_rejections_remaining = 3
	var bounded_cpu := _add_cpu(bounded_model, "white", false)
	var bounded_observation := {"rejections": 0, "stalls": 0}
	bounded_cpu.command_rejected.connect(func(_color: String, _type: String, _attempt: int): bounded_observation["rejections"] += 1)
	bounded_cpu.decision_stalled.connect(func(_color: String, _type: String): bounded_observation["stalls"] += 1)
	bounded_cpu.configure(true, "white")
	await _wait_frames(6)
	_expect(bounded_observation["rejections"] == 2 and bounded_observation["stalls"] == 1, "repeated rejection stops after one bounded retry")
	_expect(bounded_model.current_turn == "white" and bounded_model.board[7][0] == bounded_rook, "bounded rejection recovery does not submit an illegal fallback")
	bounded_cpu.queue_free()
	bounded_model.free()


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


func _test_two_cpu_turns() -> void:
	var model := _new_empty_model()
	var white_rook := Rook.new("white", Vector2i(7, 0))
	var black_pawn := Pawn.new("black", Vector2i(7, 3))
	var black_rook := Rook.new("black", Vector2i(0, 7))
	var white_pawn := Pawn.new("white", Vector2i(0, 4))
	model.add_piece(white_rook, white_rook.coordinate)
	model.add_piece(black_pawn, black_pawn.coordinate)
	model.add_piece(black_rook, black_rook.coordinate)
	model.add_piece(white_pawn, white_pawn.coordinate)
	var white_cpu := _add_cpu(model, "white", false)
	var black_cpu := _add_cpu(model, "black", false)
	var owners: Array[String] = []
	model.action_started.connect(
		func(color: String):
			owners.append(color)
			if owners.size() == 2:
				white_cpu.is_enabled = false
				black_cpu.is_enabled = false
	)
	black_cpu.configure(true, "black")
	white_cpu.configure(true, "white")
	await _wait_for_action_count(owners, 2)
	await _wait_frames(2)
	_expect(owners == ["white", "black"], "two CPU clients act once each in turn order")
	_expect(model.board[7][3] == white_rook and model.board[0][4] == black_rook, "each CPU submits its own highest-scoring capture")
	white_cpu.queue_free()
	black_cpu.queue_free()
	model.free()


func _test_two_cpu_reaction_ownership() -> void:
	var model := _new_empty_model()
	model.current_turn = "black"
	var necromancer := NecromancerKing.new("white", Vector2i(7, 7))
	var bishop := Bishop.new("black", Vector2i(4, 4))
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	var white_cpu := _add_cpu(model, "white", false)
	var black_cpu := _add_cpu(model, "black", false)
	model.reaction_selection_resolved.connect(
		func(_piece: ModelPiece, _action_type: String, _target: Vector2i):
			white_cpu.is_enabled = false
			black_cpu.is_enabled = false,
		CONNECT_ONE_SHOT
	)
	white_cpu.configure(true, "white")
	black_cpu.configure(true, "black")
	model.begin_action("black")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	await _wait_frames(3)
	_expect(not model.has_pending_reaction(), "matching CPU resolves a reaction owned by White")
	_expect(_count_type(model, "bone_pawn") == 1, "two-CPU reaction ownership produces the selected effect")
	white_cpu.queue_free()
	black_cpu.queue_free()
	model.free()


func _test_two_cpu_battle_completion_stops_scheduling() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var black_king := ClassicKing.new("black", Vector2i(3, 3))
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(black_king, black_king.coordinate)
	var white_cpu := _add_cpu(model, "white", false)
	var black_cpu := _add_cpu(model, "black", false)
	var action_count := {"value": 0}
	model.action_started.connect(func(_color: String): action_count["value"] += 1)
	black_cpu.configure(true, "black")
	white_cpu.configure(true, "white")
	await _wait_frames(4)
	var count_at_completion: int = action_count["value"]
	await _wait_frames(4)
	_expect(model.battle_over and model.battle_result == "white", "two-CPU fixture reaches battle completion")
	_expect(count_at_completion == 1 and action_count["value"] == count_at_completion, "neither CPU schedules after battle completion")
	white_cpu.queue_free()
	black_cpu.queue_free()
	model.free()


func _test_long_headless_cpu_battle() -> void:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	var white_cpu := _add_cpu(model, "white", false)
	var black_cpu := _add_cpu(model, "black", false)
	white_cpu.set_random_seed(1001)
	black_cpu.set_random_seed(2002)
	var observation := {"started": 0, "finished": 0, "rejections": 0, "stalls": 0}
	model.action_started.connect(func(_color: String): observation["started"] += 1)
	model.action_finished.connect(
		func():
			observation["finished"] += 1
			if observation["started"] >= 20:
				white_cpu.is_enabled = false
				black_cpu.is_enabled = false
	)
	white_cpu.command_rejected.connect(func(_color: String, _type: String, _attempt: int): observation["rejections"] += 1)
	black_cpu.command_rejected.connect(func(_color: String, _type: String, _attempt: int): observation["rejections"] += 1)
	white_cpu.decision_stalled.connect(func(_color: String, _type: String): observation["stalls"] += 1)
	black_cpu.decision_stalled.connect(func(_color: String, _type: String): observation["stalls"] += 1)
	black_cpu.configure(true, "black")
	white_cpu.configure(true, "white")

	for frame in range(1000):
		if model.battle_over or observation["started"] >= 20:
			break
		await get_tree().process_frame
	await _wait_for_model_idle(model)
	_expect(model.battle_over or observation["started"] >= 20, "headless CPU-vs-CPU game progresses through many actions")
	_expect(observation["rejections"] == 0, "long CPU-vs-CPU game submits no rejected commands")
	_expect(observation["stalls"] == 0, "long CPU-vs-CPU game encounters no resolver or no-action stalls")
	_expect(not model.action_in_progress and not model.has_pending_reaction(), "long CPU-vs-CPU checkpoint leaves the resolver settled")
	_expect(observation["finished"] == observation["started"] or (model.battle_over and observation["finished"] == observation["started"] - 1), "long CPU-vs-CPU action starts and completions remain balanced")
	white_cpu.queue_free()
	black_cpu.queue_free()
	model.free()


func _add_cpu(model: ChessBoardModel, color: String, enabled: bool) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	cpu.thinking_delay_seconds = 0.0
	cpu.evaluation_frame_budget_ms = 0.0
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


func _new_empty_reject_model() -> RejectOnceModel:
	var model := RejectOnceModel.new()
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


func _wait_for_action_count(owners: Array[String], expected: int, max_frames: int = 20) -> void:
	for frame in range(max_frames):
		if owners.size() >= expected:
			return
		await get_tree().process_frame


func _wait_for_model_idle(model: ChessBoardModel, max_frames: int = 100) -> void:
	for frame in range(max_frames):
		if not model.action_in_progress and not model.has_pending_reaction():
			return
		await get_tree().process_frame


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
