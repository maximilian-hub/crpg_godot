extends RefCounted
class_name ClassicCoreLiveBridge

const PieceArrivalContext := preload("res://scripts/core/chess_piece_arrival_context.gd")
const TargetedAbilityContext := preload("res://scripts/core/chess_targeted_ability_presentation_context.gd")

var model: ChessBoardModel
var state: ChessCoreState
var active := false
var fallback_reason := ""
var resolution_count := 0
var rejected_transition_count := 0
var projection_mismatch_count := 0
var pending_completion_events: Array[ChessCoreEvent] = []


func _init(owner: ChessBoardModel) -> void:
	model = owner


func synchronize_from_projection() -> bool:
	var imported := ClassicChessCore.import_position(model._capture_projected_position())
	if not imported.ok:
		active = false
		state = null
		fallback_reason = String(imported.get("error", "Unsupported Classic position."))
		return false
	state = imported.state
	active = true
	fallback_reason = ""
	return true


func deactivate(reason := "") -> void:
	active = false
	state = null
	fallback_reason = reason


func capture_position() -> ChessPosition:
	return ClassicChessCore.export_position(state) if active and state != null else null


func legal_actions(color: String) -> Array[ChessPrimaryAction]:
	var result: Array[ChessPrimaryAction] = []
	if not active or state == null: return result
	for core_action in ClassicChessCore.legal_actions(state, color):
		var piece := model.find_piece_by_id(core_action.piece_id)
		if piece != null:
			result.append(ChessPrimaryAction.new(core_action.kind as ChessPrimaryAction.Kind, piece, core_action.target, core_action.path))
	return result


func legal_moves(piece: ModelPiece) -> Array:
	var result := []
	if piece == null or not active or state == null: return result
	for action in ClassicChessCore.analysis_actions(state, piece.color):
		if action.kind == ChessCoreAction.Kind.MOVE and action.piece_id == piece.piece_id and action.path.size() == 1 and action.target not in result: result.append(action.target)
	return result


func submit_move(piece: ModelPiece, target: Vector2i) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.MOVE, target, [target])


func submit_move_path(piece: ModelPiece, path: Array[Vector2i]) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.MOVE, path.back() if not path.is_empty() else Vector2i(-1, -1), path)


func submit_active_ability(piece: KingPiece, target: Vector2i) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.ACTIVE_ABILITY, target, [])


func set_cooldowns_disabled(disabled: bool) -> void:
	if state != null:
		state.active_ability_cooldowns_disabled = disabled
		if disabled:
			for piece in state.pieces:
				if piece.is_king():
					piece.current_cooldown = 0
					piece.cooldown_reset_pending = false


func _submit_matching_action(piece: ModelPiece, kind: ChessCoreAction.Kind, target: Vector2i, path: Array[Vector2i]) -> bool:
	if not active or state == null or piece == null: return false
	var action: ChessCoreAction
	for candidate in ClassicChessCore.legal_actions(state, state.current_turn):
		if candidate.kind == kind and candidate.piece_id == piece.piece_id and candidate.target == target and candidate.path == path:
			action = candidate
			break
	if action == null:
		rejected_transition_count += 1
		return false
	var before := state
	var result := ClassicChessCore.resolve_action(before, action)
	if result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
		rejected_transition_count += 1
		return false
	resolution_count += 1
	state = result.state
	if not model.begin_action(piece.color):
		state = before
		rejected_transition_count += 1
		return false
	if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY:
		await _present_active_ability(before, result.state, action, piece as KingPiece, result.events)
	else:
		await _present_primary_transition(before, result.state, action, piece, result.events)
	await _present_automatic_reaction_timeline(result.events)
	var completion_events: Array[ChessCoreEvent] = result.events.duplicate()
	if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		if result.choice.kind == &"promotion":
			var selected := await model.request_promotion_selection(piece)
			var choice_result := ClassicChessCore.resolve_choice(state, selected)
			if choice_result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
				state = before; model.cancel_action(); rejected_transition_count += 1; return false
			resolution_count += 1
			var pre_promotion := state
			state = choice_result.state
			completion_events.append_array(choice_result.events)
			await _present_promotion(pre_promotion, state, piece)
			result = choice_result
		if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			pending_completion_events.assign(completion_events)
			await _present_reaction_events(completion_events, false, false)
			return true
	await _complete_action_from_events(completion_events)
	return true


func _present_active_ability(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, king: KingPiece, events: Array[ChessCoreEvent]) -> void:
	var target_core := before.occupant(action.target)
	var target := model.find_piece_by_id(target_core.piece_id) if target_core != null else null
	var ability_id: StringName = king.get_active_ability_id()
	var ability_name := king.get_active_ability_name()
	var context = TargetedAbilityContext.new(king, ability_id, ability_name, action.target, target)
	model.targeted_ability_committed.emit(context)
	context.close_claims()
	await context.wait_for_impact()
	if king is NecromancerKing:
		await _present_piece_events(events)
	elif king is MinotaurKing:
		await _present_charge_effect(before, after, action, king, target, events)
	else:
		var damage_event := _first_damage_event(events, target.piece_id)
		var damage := int(damage_event.data.get("amount", 0)) if damage_event != null else 0
		target.current_hp = int(damage_event.data.get("current_hp", target.current_hp - damage)) if damage_event != null else target.current_hp
		model.piece_damaged.emit(target, damage, target.current_hp, target.max_hp)
		if target.current_hp <= 0:
			model.destroy_piece(target, true)
	var final_king := after.piece_by_id(king.piece_id)
	if final_king != null:
		king.current_cooldown = final_king.current_cooldown
		king.cooldown_reset_pending = final_king.cooldown_reset_pending
		king.initial_cooldown_turn_pending = final_king.initial_cooldown_turn_pending
		if king.cooldown_reset_pending:
			king.cooldown_scheduled.emit(king)
		else:
			king.cooldown_ready.emit(king)
	context.report_effect()
	await context.wait_for_aftermath()


func submit_reaction_selection(coord: Vector2i) -> bool:
	if not active or state == null or state.pending_choice == null or state.pending_choice.kind != &"raise_dead" or coord not in state.pending_choice.options:
		return false
	model.pending_reaction.clear()
	var result := ClassicChessCore.resolve_choice(state, coord)
	if result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
		rejected_transition_count += 1
		return false
	state = result.state
	resolution_count += 1
	pending_completion_events.append_array(result.events)
	await _present_reaction_events(result.events, true)
	if result.status == ChessCoreStepResult.Status.PENDING_CHOICE: return true
	var completed := pending_completion_events.duplicate()
	pending_completion_events.clear()
	await _complete_action_from_events(completed)
	return true


func resolve_unplayable_turns() -> bool:
	if not active or state == null or state.battle_over or not ClassicChessCore.legal_actions(state, state.current_turn).is_empty():
		return false
	var result := ClassicChessCore.resolve_forced_passes(state)
	if result.status != ChessCoreStepResult.Status.COMPLETED:
		rejected_transition_count += 1
		return false
	state = result.state
	resolution_count += 1
	await _apply_turn_events(result.events)
	model.position_revision += 1
	if state.battle_over: model.battle_finished.emit(state.battle_result)
	model.settled_action_completed.emit()
	if not _projection_matches(): projection_mismatch_count += 1
	return true


func _present_primary_transition(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, piece: ModelPiece, events: Array[ChessCoreEvent]) -> void:
	var origin := action.from
	var defender := model.board[action.target.x][action.target.y] as ModelPiece
	var captured_at := action.target
	if piece.type == "pawn" and defender == null and origin.y != action.target.y:
		captured_at = Vector2i(origin.x, action.target.y)
		defender = model.board[captured_at.x][captured_at.y] as ModelPiece
	var after_piece := after.piece_by_id(piece.piece_id)
	var castle := piece is KingPiece and action.path.size() == 1 and absi(action.target.y - origin.y) == 2
	if action.path.size() == 2 and piece is ArakneKing:
		var intermediate: Vector2i = action.path[0]
		await _present_move(piece, origin, intermediate)
		model.skitter_step_started.emit(piece, intermediate, action.target)
		await _present_move(piece, intermediate, action.target)
	elif castle:
		await _present_castle(piece as KingPiece, origin, action.target)
	elif defender != null and defender.current_hp > piece.attack_power:
		await _present_damage(piece, defender, _first_damage_event(events, defender.piece_id))
	elif defender != null and after.piece_by_id(defender.piece_id) == null:
		await _present_capture(piece, defender, origin, action.target, captured_at, events)
	else:
		await _present_move(piece, origin, action.target)
	model.last_move = {"from": origin, "to": action.target, "piece": piece}
	if not _has_automatic_reaction(events):
		var final_piece := state.piece_by_id(piece.piece_id)
		if final_piece == null and model.is_piece_active(piece):
			model.destroy_piece(piece, true)
		else:
			_sync_piece_from_core(piece, final_piece)


func _present_reaction_events(events: Array[ChessCoreEvent], include_piece_events: bool, include_queued := true) -> void:
	for event in events:
		var piece_id := String(event.data.get("piece_id", ""))
		var caller := model.find_piece_by_id(piece_id)
		var action_type := String(event.data.get("action_type", ""))
		match event.kind:
			&"reaction_queued":
				if include_queued and caller != null:
					model.reaction_queued.emit(caller, action_type, event.data.get("event_coordinate"), int(event.data.get("sequence", 0)))
			&"reaction_selection_preparing":
				if caller != null:
					var gate := CompletionGate.new()
					model.reaction_selection_preparing.emit(caller, action_type, event.data.get("targets", []).duplicate(), gate)
					gate.close()
					await gate.wait_until_released()
			&"reaction_selection_requested":
				if caller != null:
					var targets: Array = event.data.get("targets", []).duplicate()
					model.pending_reaction = {
						"calling_piece": caller, "action_type": action_type,
						"event_data": state.pending_choice.event_coordinate if state.pending_choice != null else Vector2i(-1, -1),
						"sequence": int(event.data.get("sequence", 0)), "targets": targets,
					}
					model.reaction_selection_requested.emit(caller, action_type, targets)
			&"reaction_selection_committed":
				if caller != null: model.reaction_selection_committed.emit(caller, action_type, event.data.get("target"))
			&"piece_summoned":
				if include_piece_events: await _present_summoned_piece(event)
			&"piece_destroyed":
				if include_piece_events:
					var destroyed := model.find_piece_by_id(piece_id)
					if destroyed != null: model.destroy_piece(destroyed, true)
			&"reaction_selection_resolved":
				if caller != null: model.reaction_selection_resolved.emit(caller, action_type, event.data.get("target"))
			&"reaction_finished":
				# Automatic Rage lifecycle is replayed by the ordered timeline before
				# any subsequent coordinate choice is exposed.
				if action_type != "retaliating_rage":
					model.reaction_finished.emit(caller, action_type, event.data.get("event_coordinate"), int(event.data.get("sequence", 0)), bool(event.data.get("resolved", false)))


func _present_automatic_reaction_timeline(events: Array[ChessCoreEvent]) -> void:
	var automatic_active := false
	for event in events:
		var piece_id := String(event.data.get("piece_id", ""))
		var caller := model.find_piece_by_id(piece_id)
		var action_type := String(event.data.get("action_type", ""))
		match event.kind:
			&"reaction_queued":
				if caller != null:
					model.reaction_queued.emit(caller, action_type, event.data.get("event_coordinate"), int(event.data.get("sequence", 0)))
			&"automatic_reaction_started":
				automatic_active = true
				if caller is MinotaurKing:
					await model.announce_ability_started(caller, MinotaurKing.PASSIVE_ABILITY_NAME)
			&"piece_damaged":
				if automatic_active and caller != null:
					var amount := int(event.data.get("amount", 0))
					caller.current_hp = int(event.data.get("current_hp", caller.current_hp - amount))
					model.piece_damaged.emit(caller, amount, caller.current_hp, caller.max_hp)
			&"piece_destroyed":
				if automatic_active and caller != null:
					model.destroy_piece(caller, true)
			&"automatic_reaction_resolved":
				if caller is MinotaurKing:
					model.ability_effect_resolved.emit(caller, MinotaurKing.PASSIVE_ABILITY_NAME, event.data.get("affected_coordinates", []).duplicate())
				automatic_active = false
			&"reaction_finished":
				if action_type == "retaliating_rage":
					model.reaction_finished.emit(caller, action_type, null, int(event.data.get("sequence", 0)), bool(event.data.get("resolved", false)))


func _present_piece_events(events: Array[ChessCoreEvent]) -> void:
	for event in events:
		if event.kind == &"piece_summoned": await _present_summoned_piece(event)
		elif event.kind == &"piece_destroyed":
			var piece := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if piece != null: model.destroy_piece(piece, true)


func _present_summoned_piece(event: ChessCoreEvent) -> void:
	var coordinate: Vector2i = event.data.get("coordinate", Vector2i(-1, -1))
	var piece := ChessPieceCatalog.create_piece(StringName(event.data.get("piece_type", &"bone_pawn")), String(event.data.get("color", "")), coordinate)
	if piece == null: return
	piece.piece_id = String(event.data.get("piece_id", ""))
	model._reserve_state_id(piece.piece_id)
	if not model.add_piece(piece, coordinate):
		piece.free()
		return
	await model.announce_piece_summoned(piece)


func _present_move(piece: ModelPiece, origin: Vector2i, target: Vector2i) -> void:
	model.board[origin.x][origin.y] = null
	model.board[target.x][target.y] = piece
	piece.coordinate = target
	piece.has_moved = true
	var presentation := PieceArrivalContext.new([piece])
	model.piece_move_committed.emit(piece, origin, target, presentation)
	presentation.close_claims()
	await presentation.wait_for_arrival(piece)
	await model._announce_piece_landed(piece, origin, target)
	await presentation.wait_for_aftermath()


func _present_capture(attacker: ModelPiece, defender: ModelPiece, origin: Vector2i, target: Vector2i, captured_at: Vector2i, events: Array[ChessCoreEvent]) -> void:
	model.board[origin.x][origin.y] = null
	if model.board[captured_at.x][captured_at.y] == defender: model.board[captured_at.x][captured_at.y] = null
	model.board[target.x][target.y] = attacker
	attacker.coordinate = target
	attacker.has_moved = true
	var presentation := PieceArrivalContext.new([attacker], true)
	model.piece_capture_committed.emit(attacker, defender, origin, target, captured_at, presentation)
	presentation.close_claims()
	await presentation.wait_for_impact()
	model.destroy_piece(defender, false)
	await presentation.wait_for_arrival(attacker)
	await model._announce_piece_landed(attacker, origin, target)
	await presentation.wait_for_aftermath()


func _present_damage(attacker: ModelPiece, defender: ModelPiece, damage_event: ChessCoreEvent) -> void:
	var gate := CompletionGate.new()
	model.piece_attack_committed.emit(attacker, defender, attacker.coordinate, defender.coordinate, gate)
	gate.close()
	if damage_event != null:
		var amount := int(damage_event.data.get("amount", 0))
		defender.current_hp = int(damage_event.data.get("current_hp", defender.current_hp - amount))
		model.piece_damaged.emit(defender, amount, defender.current_hp, defender.max_hp)
	await gate.wait_until_released()


func _present_charge_effect(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, minotaur: MinotaurKing, target: ModelPiece, events: Array[ChessCoreEvent]) -> void:
	var target_core := before.occupant(action.target)
	if target_core == null:
		await _present_move(minotaur, action.from, action.target)
		minotaur.stunned = true
		minotaur.stun_timer = MinotaurCoreRules.SELF_STUN_DURATION
		model.piece_stunned.emit(minotaur, minotaur.stun_timer)
		return
	if target_core.max_hp <= 1:
		await _present_capture(minotaur, target, action.from, action.target, action.target, events)
		return
	var final_minotaur := after.piece_by_id(minotaur.piece_id)
	# Rage may subsequently destroy the charging Minotaur; its Charge landing is
	# still the square immediately before the durable target.
	var direction := Vector2i(signi(action.target.x - action.from.x), signi(action.target.y - action.from.y))
	var landing := action.target - direction
	if final_minotaur != null and final_minotaur.coordinate != landing:
		landing = final_minotaur.coordinate
	await _present_move(minotaur, action.from, landing)
	var damage_event := _first_damage_event(events, target.piece_id)
	if damage_event != null:
		var amount := int(damage_event.data.get("amount", 0))
		target.current_hp = int(damage_event.data.get("current_hp", target.current_hp - amount))
		model.piece_damaged.emit(target, amount, target.current_hp, target.max_hp)
		if target.current_hp <= 0:
			model.destroy_piece(target, true)


func _first_damage_event(events: Array[ChessCoreEvent], piece_id: String) -> ChessCoreEvent:
	for event in events:
		if event.kind == &"automatic_reaction_started":
			break
		if event.kind == &"piece_damaged" and String(event.data.get("piece_id", "")) == piece_id:
			return event
	return null


func _has_automatic_reaction(events: Array[ChessCoreEvent]) -> bool:
	for event in events:
		if event.kind == &"automatic_reaction_started": return true
	return false


func _present_castle(king: KingPiece, origin: Vector2i, target: Vector2i) -> void:
	var rook_from := Vector2i(origin.x, 7 if target.y == 6 else 0)
	var rook_to := Vector2i(origin.x, 5 if target.y == 6 else 3)
	var rook := model.board[rook_from.x][rook_from.y] as ModelPiece
	model.board[origin.x][origin.y] = null
	model.board[rook_from.x][rook_from.y] = null
	model.board[rook_to.x][rook_to.y] = rook
	model.board[target.x][target.y] = king
	king.coordinate = target; king.has_moved = true
	rook.coordinate = rook_to; rook.has_moved = true
	var presentation := PieceArrivalContext.new([rook, king])
	model.piece_castling_committed.emit(king, rook, origin, target, rook_from, rook_to, presentation)
	presentation.close_claims()
	await presentation.wait_for_arrival(rook)
	await model._announce_piece_landed(rook, rook_from, rook_to)
	await presentation.wait_for_arrival(king)
	await model._announce_piece_landed(king, origin, target)
	await presentation.wait_for_aftermath()


func _present_promotion(_before: ChessCoreState, after: ChessCoreState, pawn: ModelPiece) -> void:
	var promoted_core := after.occupant(pawn.coordinate)
	if promoted_core == null or promoted_core.type_id == &"pawn": return
	var promoted := ChessPieceCatalog.create_piece(promoted_core.type_id, promoted_core.color, promoted_core.coordinate)
	promoted.piece_id = promoted_core.piece_id
	model._reserve_state_id(promoted.piece_id)
	_sync_piece_from_core(promoted, promoted_core)
	model.unregister_piece(pawn)
	model.inject_dependencies(promoted)
	model.board[pawn.coordinate.x][pawn.coordinate.y] = promoted
	var completion := CompletionGate.new()
	model.piece_promotion_committed.emit(pawn, promoted, completion)
	completion.close()
	await completion.wait_until_released()
	model.piece_transformed.emit(pawn, promoted)


func _complete_action_from_events(events: Array[ChessCoreEvent]) -> void:
	model.pending_reaction.clear()
	model.selection_queue.clear()
	model.action_in_progress = false
	model.action_owner_color = ""
	await _apply_turn_events(events)
	model.position_revision += 1
	if state.battle_over:
		model.battle_finished.emit(state.battle_result)
	else:
		model.action_finished.emit()
	model.settled_action_completed.emit()
	if not _projection_matches(): projection_mismatch_count += 1


func _apply_turn_events(events: Array[ChessCoreEvent]) -> void:
	var forced_sequence_started := false
	model.current_turn = state.current_turn
	model.global_turn_number = state.global_turn_number
	model.consecutive_forced_passes = state.consecutive_forced_passes
	model.defeated_king_colors.assign(state.defeated_king_colors)
	model.battle_over = state.battle_over
	model.battle_result = state.battle_result
	for event in events:
		if event.kind in [&"cooldown_scheduled", &"cooldown_changed", &"cooldown_ready"]:
			_present_cooldown_event(event)
		elif event.kind == &"turn_changed":
			model.current_turn = String(event.data.get("color", model.current_turn))
			model.global_turn_number = int(event.data.get("global_turn_number", model.global_turn_number))
			model.turn_changed.emit(model.current_turn)
		elif event.kind == &"turn_passed":
			if not forced_sequence_started:
				forced_sequence_started = true
				model.forced_pass_in_progress = true
				model.forced_pass_sequence_started.emit()
			model.turn_passed.emit(String(event.data.get("color", "")), int(event.data.get("count", 0)))
			if model.forced_pass_delay_seconds > 0.0 and model.is_inside_tree():
				await model.get_tree().create_timer(model.forced_pass_delay_seconds).timeout
	model.current_turn = state.current_turn
	_sync_all_piece_state()
	if forced_sequence_started:
		model.forced_pass_in_progress = false
		model.forced_pass_sequence_finished.emit()


func _present_cooldown_event(event: ChessCoreEvent) -> void:
	var piece := model.find_piece_by_id(String(event.data.get("piece_id", ""))) as KingPiece
	if piece == null:
		return
	match event.kind:
		&"cooldown_scheduled":
			if piece.cooldown_reset_pending and piece.current_cooldown == 0:
				return
			piece.current_cooldown = 0
			piece.cooldown_reset_pending = true
			piece.cooldown_scheduled.emit(piece)
		&"cooldown_changed":
			piece.current_cooldown = int(event.data.get("value", 0))
			piece.cooldown_reset_pending = false
			piece.cooldown_changed.emit(piece, piece.current_cooldown)
		&"cooldown_ready":
			if not piece.cooldown_reset_pending and piece.current_cooldown == 0:
				return
			piece.current_cooldown = 0
			piece.cooldown_reset_pending = false
			piece.cooldown_ready.emit(piece)


func _sync_all_piece_state() -> void:
	for core_piece in state.pieces:
		var piece := model.find_piece_by_id(core_piece.piece_id)
		if piece != null: _sync_piece_from_core(piece, core_piece)


func _sync_piece_from_core(piece: ModelPiece, core_piece: ChessCorePiece) -> void:
	if piece == null or core_piece == null: return
	piece.coordinate = core_piece.coordinate
	piece.max_hp = core_piece.max_hp
	piece.current_hp = core_piece.current_hp
	piece.attack_power = core_piece.attack_power
	piece.has_moved = core_piece.has_moved
	piece.stunned = core_piece.stunned
	piece.stun_timer = core_piece.stun_timer
	if piece is KingPiece:
		var king := piece as KingPiece
		king.current_cooldown = core_piece.current_cooldown
		king.cooldown_reset_pending = core_piece.cooldown_reset_pending
		king.initial_cooldown_turn_pending = core_piece.initial_cooldown_turn_pending


func _projection_matches() -> bool:
	var projected := model._capture_projected_position()
	var authoritative := ClassicChessCore.export_position(state)
	return ChessPositionCodec.to_json(projected, false) == ChessPositionCodec.to_json(authoritative, false)
