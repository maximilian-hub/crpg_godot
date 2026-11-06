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
var last_rejection_context := ""
var last_projection_mismatch_context := ""
var pending_completion_events: Array[ChessCoreEvent] = []
var presented_reaction_sequences: Dictionary = {}


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
	model._next_state_id = state.next_state_id
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


func legal_move_paths(piece: ModelPiece) -> Array:
	var result: Array = []
	if piece == null or not active or state == null: return result
	for action in ClassicChessCore.analysis_actions(state, piece.color):
		if action.kind == ChessCoreAction.Kind.MOVE and action.piece_id == piece.piece_id and action.path not in result:
			result.append(action.path.duplicate())
	return result


func active_ability_targets(piece: KingPiece) -> Array:
	var result: Array = []
	if piece == null or not active or state == null: return result
	for action in ClassicChessCore.analysis_actions(state, piece.color):
		if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action.piece_id == piece.piece_id and action.target not in result:
			result.append(action.target)
	return result


func is_archer_suppressed(piece: ArcherKing) -> bool:
	if piece == null or not active or state == null: return false
	var core_piece := state.piece_by_id(piece.piece_id)
	return ArcherCoreRules.is_suppressed(state, core_piece) if core_piece != null else false


func submit_move(piece: ModelPiece, target: Vector2i) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.MOVE, target, [target])


func submit_move_path(piece: ModelPiece, path: Array[Vector2i]) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.MOVE, path.back() if not path.is_empty() else Vector2i(-1, -1), path)


func submit_active_ability(piece: KingPiece, target: Vector2i) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.ACTIVE_ABILITY, target, [])


func submit_archer_charge(piece: ArcherKing) -> bool:
	return await _submit_matching_action(piece, ChessCoreAction.Kind.ARCHER_CHARGE, piece.coordinate, [])


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
	presented_reaction_sequences.clear()
	var action: ChessCoreAction
	for candidate in ClassicChessCore.legal_actions(state, state.current_turn):
		if candidate.kind == kind and candidate.piece_id == piece.piece_id and candidate.target == target and candidate.path == path:
			action = candidate
			break
	if action == null:
		_record_rejection("matching live action was not legal")
		return false
	var before := state
	var result := ClassicChessCore.resolve_action(before, action)
	if result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
		_record_rejection("pure action resolution did not complete or request a choice")
		return false
	resolution_count += 1
	state = result.state
	if not model.begin_action(piece.color):
		state = before
		_record_rejection("live model refused to begin the projected action")
		return false
	var quarterly_context = null
	var rhetorician_context = null
	if action.kind == ChessCoreAction.Kind.ARCHER_CHARGE and piece is ArcherKing:
		_present_archer_state_events(result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and piece is ArcherKing:
		await _present_archer_volley(piece as ArcherKing, result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and piece is QuarterlyInitiativeKing:
		quarterly_context = await _present_quarterly_ability_started(before, result.state, action, piece as QuarterlyInitiativeKing, result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and piece is RhetoricianKing:
		rhetorician_context = await _present_rhetorician_ability_started(before, result.state, action, piece as RhetoricianKing, result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and piece is CannonKing:
		await _present_cannon_ability(before, result.state, action, piece as CannonKing, result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and piece is WraithKing:
		await _present_wraith_ability(before, result.state, action, piece as WraithKing, result.events)
	elif action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY:
		await _present_active_ability(before, result.state, action, piece as KingPiece, result.events)
	else:
		await _present_primary_transition(before, result.state, action, piece, result.events)
	await _present_tile_effect_additions(result.events, result.state)
	await _present_archer_effect_events(result.events)
	await _present_turn_entry_consequences(result.events)
	await _present_socratic_action(result.events)
	await _present_automatic_reaction_timeline(result.events)
	var completion_events: Array[ChessCoreEvent] = result.events.duplicate()
	if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		if result.choice.kind == &"promotion":
			var promoting_piece := model.find_piece_by_id(result.choice.piece_id)
			var selected := await model.request_promotion_selection(promoting_piece)
			var choice_result := ClassicChessCore.resolve_choice(state, selected)
			if choice_result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
				state = before; model.cancel_action(); _record_rejection("promotion choice failed to resolve"); return false
			resolution_count += 1
			var pre_promotion := state
			state = choice_result.state
			completion_events.append_array(choice_result.events)
			await _present_promotion(pre_promotion, state, promoting_piece)
			result = choice_result
			if rhetorician_context != null:
				rhetorician_context.report_effect()
				await rhetorician_context.wait_for_aftermath()
		elif result.choice.kind == &"movement_type_grant":
			var target_core := state.piece_by_id(result.choice.target_piece_id)
			var grant_target := model.find_piece_by_id(result.choice.target_piece_id)
			var selected := await model.request_movement_type_grant(piece as QuarterlyInitiativeKing, grant_target)
			var choice_result := ClassicChessCore.resolve_choice(state, selected)
			if choice_result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
				state = before; model.cancel_action(); _record_rejection("movement grant choice failed to resolve"); return false
			resolution_count += 1
			state = choice_result.state
			completion_events.append_array(choice_result.events)
			if grant_target != null and target_core != null:
				grant_target.grant_movement_type(StringName(selected))
			result = choice_result
			if quarterly_context != null:
				quarterly_context.report_effect()
				await quarterly_context.wait_for_aftermath()
		if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			pending_completion_events.assign(completion_events)
			await _present_reaction_events(completion_events, false, false)
			return true
	await _complete_action_from_events(completion_events)
	return true


func _present_rhetorician_ability_started(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, king: RhetoricianKing, events: Array[ChessCoreEvent]):
	var target_core := before.occupant(action.target)
	var target := model.find_piece_by_id(target_core.piece_id) if target_core != null else null
	var context = TargetedAbilityContext.new(king, RhetoricianKing.ACTIVE_ABILITY_ID, RhetoricianKing.ACTIVE_ABILITY_NAME, action.target, target)
	model.targeted_ability_committed.emit(context)
	context.close_claims()
	await context.wait_for_impact()
	if target != null:
		var delta := king.coordinate - target.coordinate
		var destination := target.coordinate + Vector2i(signi(delta.x), signi(delta.y))
		var occupant := model.board[destination.x][destination.y] as ModelPiece
		if occupant == null:
			await _present_move(target, target.coordinate, destination, true)
		else:
			await _present_capture(target, occupant, target.coordinate, destination, destination, events, true)
	# Promotion occurs inside the compelled movement before the ability returns;
	# later reaction choices occur after the ability effect has completed.
	if after.pending_choice == null or after.pending_choice.kind != &"promotion":
		context.report_effect()
		await context.wait_for_aftermath()
	return context


func _present_quarterly_ability_started(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, king: QuarterlyInitiativeKing, events: Array[ChessCoreEvent]):
	var target_core := before.occupant(action.target)
	var target := model.find_piece_by_id(target_core.piece_id) if target_core != null else null
	var context = TargetedAbilityContext.new(king, king.get_active_ability_id(), king.get_active_ability_name(), action.target, target)
	model.targeted_ability_committed.emit(context)
	context.close_claims()
	await context.wait_for_impact()
	var damage_event := _first_damage_event(events, king.piece_id)
	if damage_event != null:
		var damage := int(damage_event.data.get("amount", 0))
		king.current_hp = int(damage_event.data.get("current_hp", king.current_hp - damage))
		model.piece_damaged.emit(king, damage, king.current_hp, king.max_hp)
		if king.current_hp <= 0:
			model.destroy_piece(king, true)
	if after.pending_choice == null:
		context.report_effect()
		await context.wait_for_aftermath()
	return context


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


func _present_archer_volley(archer: ArcherKing, events: Array[ChessCoreEvent]) -> void:
	var targets: Array[Vector2i] = []
	for event in events:
		if event.kind == &"archer_volley_committed":
			targets.assign(event.data.get("targets", []))
			break
	var gate := CompletionGate.new()
	model.archer_volley_committed.emit(archer, targets, gate)
	gate.close()
	await gate.wait_until_released()
	for event in events:
		if event.kind != &"piece_damaged": continue
		var target := model.find_piece_by_id(String(event.data.get("piece_id", "")))
		if target == null: continue
		var amount := int(event.data.get("amount", 0))
		target.current_hp = int(event.data.get("current_hp", target.current_hp - amount))
		model.piece_damaged.emit(target, amount, target.current_hp, target.max_hp)
		if target.current_hp <= 0: model.destroy_piece(target, true)
	_sync_piece_from_core(archer, state.piece_by_id(archer.piece_id))


func _present_cannon_ability(_before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, king: CannonKing, events: Array[ChessCoreEvent]) -> void:
	var context = TargetedAbilityContext.new(king, CannonKing.ACTIVE_ABILITY_ID, CannonKing.ACTIVE_ABILITY_NAME, action.target, null)
	model.targeted_ability_committed.emit(context)
	context.close_claims()
	await context.wait_for_impact()
	var added_event: ChessCoreEvent
	for event in events:
		if event.kind == &"autonomous_entity_added": added_event = event; break
	if added_event != null:
		var core_entity: ChessCoreAutonomousEntity = after.entities_by_id.get(String(added_event.data.get("entity_id", "")))
		if core_entity != null:
			var entity: ChessAutonomousEntityState = core_entity.to_entity_state()
			model.autonomous_entities.append(entity)
			model._reserve_state_id(entity.entity_id)
			var gate := CompletionGate.new()
			model.autonomous_entity_added.emit(entity, gate)
			gate.close()
			await gate.wait_until_released()
	var final_king := after.piece_by_id(king.piece_id)
	_sync_piece_from_core(king, final_king)
	king.scheduled_arc_cooldown = int(final_king.custom_state.get("scheduled_arc_cooldown", king.base_cooldown)) if final_king != null else king.base_cooldown
	context.report_effect()
	await context.wait_for_aftermath()


func _present_wraith_ability(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, king: WraithKing, events: Array[ChessCoreEvent]) -> void:
	var target_core := before.occupant(action.target)
	var target := model.find_piece_by_id(target_core.piece_id) if target_core != null else null
	var context = TargetedAbilityContext.new(king, WraithKing.ACTIVE_ABILITY_ID, WraithKing.ACTIVE_ABILITY_NAME, action.target, target)
	model.targeted_ability_committed.emit(context)
	context.close_claims()
	await context.wait_for_impact()
	for event in events:
		if event.kind == &"autonomous_entity_removed" and StringName(event.data.get("reason", &"")) == &"replaced":
			await _present_entity_removed(event)
		elif event.kind == &"autonomous_entity_added" and StringName(event.data.get("type_id", &"")) == &"wraith":
			var core_entity: ChessCoreAutonomousEntity = after.entities_by_id.get(String(event.data.get("entity_id", "")))
			if core_entity != null:
				var entity := core_entity.to_entity_state()
				model.autonomous_entities.append(entity)
				model._reserve_state_id(entity.entity_id)
				var gate := CompletionGate.new()
				model.autonomous_entity_added.emit(entity, gate)
				gate.close()
				await gate.wait_until_released()
	_sync_piece_from_core(king, after.piece_by_id(king.piece_id))
	context.report_effect()
	await context.wait_for_aftermath()


func submit_reaction_selection(coord: Vector2i) -> bool:
	if not active or state == null or state.pending_choice == null or state.pending_choice.kind != &"raise_dead" or coord not in state.pending_choice.options:
		return false
	var choice_kind: StringName = state.pending_choice.kind
	model.pending_reaction.clear()
	var result := ClassicChessCore.resolve_choice(state, coord)
	if result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
		_record_rejection("reaction choice failed to resolve")
		return false
	state = result.state
	model.authoritative_selection_committed.emit(choice_kind, coord)
	resolution_count += 1
	pending_completion_events.append_array(result.events)
	await _present_reaction_events(result.events, true)
	await _present_turn_entry_consequences(result.events)
	if result.status == ChessCoreStepResult.Status.PENDING_CHOICE: return true
	var completed := pending_completion_events.duplicate()
	pending_completion_events.clear()
	await _complete_action_from_events(completed)
	return true


func resolve_unplayable_turns() -> bool:
	if not active or state == null or state.battle_over or not ClassicChessCore.legal_actions(state, state.current_turn).is_empty():
		return false
	var result := ClassicChessCore.resolve_forced_passes(state)
	if result.status not in [ChessCoreStepResult.Status.COMPLETED, ChessCoreStepResult.Status.PENDING_CHOICE]:
		_record_rejection("forced-pass resolution failed")
		return false
	state = result.state
	resolution_count += 1
	await _present_turn_entry_consequences(result.events)
	await _present_automatic_reaction_timeline(result.events)
	if result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
		pending_completion_events.assign(result.events)
		await _present_reaction_events(result.events, false, false)
		return true
	await _apply_turn_events(result.events)
	model.position_revision += 1
	_validate_projection("forced-pass completion")
	if state.battle_over: model.battle_finished.emit(state.battle_result)
	model.settled_action_completed.emit()
	return true


func _present_primary_transition(before: ChessCoreState, after: ChessCoreState, action: ChessCoreAction, piece: ModelPiece, events: Array[ChessCoreEvent]) -> void:
	var origin := action.from
	var defender := model.board[action.target.x][action.target.y] as ModelPiece
	var captured_at := action.target
	if piece.type == "pawn" and defender == null and origin.y != action.target.y:
		captured_at = Vector2i(origin.x, action.target.y)
		defender = model.board[captured_at.x][captured_at.y] as ModelPiece
	var after_piece := after.piece_by_id(piece.piece_id)
	var castle := piece is KingPiece and not piece is ArcherKing and action.path.size() == 1 and origin.y == 4 and action.target.y in [2, 6]
	if action.path.size() == 2 and piece is ArakneKing:
		var intermediate: Vector2i = action.path[0]
		await _present_move(piece, origin, intermediate)
		model.skitter_step_started.emit(piece, intermediate, action.target)
		await _present_move(piece, intermediate, action.target)
	elif castle:
		await _present_castle(piece as KingPiece, origin, action.target)
	elif piece is ArcherKing and defender != null:
		var damage_event := _first_damage_event(events, defender.piece_id)
		var presentation := PieceArrivalContext.new([piece], true, true)
		model.archer_attack_committed.emit(piece, defender, origin, action.target, presentation)
		presentation.close_claims()
		await presentation.wait_for_impact()
		if damage_event != null:
			var amount := int(damage_event.data.get("amount", 0))
			defender.current_hp = int(damage_event.data.get("current_hp", defender.current_hp - amount))
			model.piece_damaged.emit(defender, amount, defender.current_hp, defender.max_hp)
			if defender.current_hp <= 0: model.destroy_piece(defender, true)
		elif after.piece_by_id(defender.piece_id) == null:
			model.destroy_piece(defender, true)
		await presentation.wait_for_aftermath()
		_present_archer_state_events(events)
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
	var selected_reaction_active := false
	for event in events:
		var piece_id := String(event.data.get("piece_id", ""))
		var caller := model.find_piece_by_id(piece_id)
		var action_type := String(event.data.get("action_type", ""))
		match event.kind:
			&"reaction_queued":
				if include_queued:
					_present_reaction_queued_event(event)
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
				selected_reaction_active = true
				if caller != null: model.reaction_selection_committed.emit(caller, action_type, event.data.get("target"))
			&"tile_effect_removed":
				if include_piece_events and selected_reaction_active: _present_tile_effect_removed(event)
			&"tile_effect_added":
				if include_piece_events and selected_reaction_active: _present_tile_effect_added(event, state)
			&"piece_moved":
				if include_piece_events and selected_reaction_active and caller != null:
					await _present_move(caller, event.data.get("from", caller.coordinate), event.data.get("to", caller.coordinate))
			&"piece_captured":
				if include_piece_events and selected_reaction_active:
					var attacker := model.find_piece_by_id(String(event.data.get("attacker_id", "")))
					var defender := model.find_piece_by_id(String(event.data.get("defender_id", "")))
					if attacker != null and defender != null:
						await _present_capture(attacker, defender, event.data.get("from", attacker.coordinate), event.data.get("to", defender.coordinate), event.data.get("captured_at", defender.coordinate), events)
			&"piece_damaged":
				if include_piece_events and selected_reaction_active:
					var damaged := model.find_piece_by_id(piece_id)
					if damaged != null:
						var amount := int(event.data.get("amount", 0))
						damaged.current_hp = int(event.data.get("current_hp", damaged.current_hp - amount))
						model.piece_damaged.emit(damaged, amount, damaged.current_hp, damaged.max_hp)
			&"piece_summoned":
				if include_piece_events: await _present_summoned_piece(event)
			&"piece_destroyed":
				if include_piece_events:
					var destroyed := model.find_piece_by_id(piece_id)
					if destroyed != null: model.destroy_piece(destroyed, true)
			&"reaction_selection_resolved":
				if caller != null: model.reaction_selection_resolved.emit(caller, action_type, event.data.get("target"))
				selected_reaction_active = false
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
				_present_reaction_queued_event(event)
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


func _present_socratic_action(events: Array[ChessCoreEvent]) -> void:
	for index in range(events.size()):
		var selected := events[index]
		if selected.kind != &"socratic_action_selected": continue
		var segment: Array[ChessCoreEvent] = []
		for following in range(index + 1, events.size()):
			if events[following].kind == &"socratic_action_selected": break
			segment.append(events[following])
		await _present_one_socratic_action(selected, segment)


func _present_one_socratic_action(selected: ChessCoreEvent, consequence_events: Array[ChessCoreEvent]) -> void:
	var piece := model.find_piece_by_id(String(selected.data.get("piece_id", "")))
	if piece == null:
		return
	var origin: Vector2i = selected.data.get("from", piece.coordinate)
	var target: Vector2i = selected.data.get("target", Vector2i(-1, -1))
	var path: Array[Vector2i] = []
	path.assign(selected.data.get("path", []))
	var defender := model.board[target.x][target.y] as ModelPiece
	var captured_at := target
	if piece.type == "pawn" and defender == null and origin.y != target.y:
		captured_at = Vector2i(origin.x, target.y)
		defender = model.board[captured_at.x][captured_at.y] as ModelPiece
	var castle := piece is KingPiece and not piece is ArcherKing and path.size() == 1 and origin.y == 4 and target.y in [2, 6]
	if path.size() == 2 and piece is ArakneKing:
		await _present_move(piece, origin, path[0])
		model.skitter_step_started.emit(piece, path[0], target)
		await _present_move(piece, path[0], target)
	elif castle:
		await _present_castle(piece as KingPiece, origin, target)
	elif defender != null:
		var damage_event := _first_damage_event(consequence_events, defender.piece_id)
		if damage_event != null and int(damage_event.data.get("current_hp", defender.current_hp)) > 0:
			await _present_damage(piece, defender, damage_event)
		else:
			await _present_capture(piece, defender, origin, target, captured_at, consequence_events)
	else:
		await _present_move(piece, origin, target)
	model.last_move = {"from": origin, "to": target, "piece": piece}

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


func _present_move(piece: ModelPiece, origin: Vector2i, target: Vector2i, self_propelled := false) -> void:
	model.board[origin.x][origin.y] = null
	model.board[target.x][target.y] = piece
	piece.coordinate = target
	piece.has_moved = true
	var presentation := PieceArrivalContext.new([piece], false, self_propelled)
	model.piece_move_committed.emit(piece, origin, target, presentation)
	presentation.close_claims()
	await presentation.wait_for_arrival(piece)
	await model._announce_piece_landed(piece, origin, target)
	await presentation.wait_for_aftermath()


func _present_capture(attacker: ModelPiece, defender: ModelPiece, origin: Vector2i, target: Vector2i, captured_at: Vector2i, events: Array[ChessCoreEvent], self_propelled := false) -> void:
	model.board[origin.x][origin.y] = null
	if model.board[captured_at.x][captured_at.y] == defender: model.board[captured_at.x][captured_at.y] = null
	model.board[target.x][target.y] = attacker
	attacker.coordinate = target
	attacker.has_moved = true
	var presentation := PieceArrivalContext.new([attacker], true, self_propelled)
	model.piece_capture_committed.emit(attacker, defender, origin, target, captured_at, presentation)
	presentation.close_claims()
	await presentation.wait_for_impact()
	# Pure Core resolves the complete action before presentation begins, but a
	# capture reaction should still announce itself at physical contact. This is
	# the hand rig's defender-pickup/clack beat, before its placement and retreat.
	_present_capture_reactions_at_impact(events, captured_at)
	model.destroy_piece(defender, false)
	await presentation.wait_for_arrival(attacker)
	await model._announce_piece_landed(attacker, origin, target)
	await presentation.wait_for_aftermath()


func _present_capture_reactions_at_impact(events: Array[ChessCoreEvent], captured_at: Vector2i) -> void:
	for event in events:
		if (
			event.kind == &"reaction_queued"
			and StringName(event.data.get("action_type", &"")) == &"raise_dead"
			and event.data.get("event_coordinate") == captured_at
		):
			_present_reaction_queued_event(event)


func _present_reaction_queued_event(event: ChessCoreEvent) -> void:
	var sequence := int(event.data.get("sequence", 0))
	if presented_reaction_sequences.has(sequence):
		return
	var caller := model.find_piece_by_id(String(event.data.get("piece_id", "")))
	if caller == null:
		return
	presented_reaction_sequences[sequence] = true
	model.reaction_queued.emit(
		caller,
		String(event.data.get("action_type", "")),
		event.data.get("event_coordinate"),
		sequence
	)


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
	model.action_in_progress = false
	model.action_owner_color = ""
	await _apply_turn_events(events)
	model.position_revision += 1
	# Validate the facade before completion signals allow listeners to begin the
	# next lifecycle operation or otherwise alter the newly settled projection.
	_validate_projection("action completion")
	if state.battle_over:
		model.battle_finished.emit(state.battle_result)
	else:
		model.action_finished.emit()
	model.settled_action_completed.emit()


func _record_rejection(context: String) -> void:
	rejected_transition_count += 1
	last_rejection_context = context


func _record_projection_mismatch(context: String) -> void:
	projection_mismatch_count += 1
	last_projection_mismatch_context = context


func _apply_turn_events(events: Array[ChessCoreEvent]) -> void:
	var forced_sequence_started := false
	model.current_turn = state.current_turn
	model.global_turn_number = state.global_turn_number
	model.consecutive_forced_passes = state.consecutive_forced_passes
	model.defeated_king_colors.assign(state.defeated_king_colors)
	model.battle_over = state.battle_over
	model.battle_result = state.battle_result
	model.last_move.clear()
	if not state.last_move.is_empty():
		var moved_piece := model.find_piece_by_id(String(state.last_move.get("piece_id", "")))
		var move_target: Vector2i = state.last_move.get("to", Vector2i.ZERO)
		if moved_piece == null:
			var occupant := model.board[move_target.x][move_target.y] as ModelPiece if model.is_in_bounds(move_target.x, move_target.y) else null
			if occupant != null and occupant.color == String(state.last_move.get("piece_color", "")):
				moved_piece = occupant
		model.last_move = {
			"from": state.last_move.get("from", Vector2i.ZERO),
			"to": move_target,
			"piece": moved_piece,
			"piece_type": state.last_move.get("piece_type", moved_piece.get_position_type_id() if moved_piece != null else &""),
			"piece_color": state.last_move.get("piece_color", moved_piece.color if moved_piece != null else ""),
		}
	model._projected_random_states = state.random_states.duplicate(true)
	model._next_state_id = state.next_state_id
	for event in events:
		if event.kind in [&"cooldown_scheduled", &"cooldown_changed", &"cooldown_ready"]:
			_present_cooldown_event(event)
		elif event.kind == &"piece_stunned" and StringName(event.data.get("reason", &"")) == &"summoning_sickness":
			var stunned_piece := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if stunned_piece != null:
				stunned_piece.stunned = true
				stunned_piece.stun_timer = int(event.data.get("duration", stunned_piece.stun_timer))
				model.piece_stunned.emit(stunned_piece, stunned_piece.stun_timer)
		elif event.kind == &"piece_recovered":
			var recovered_piece := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if recovered_piece != null:
				recovered_piece.stunned = false
				recovered_piece.stun_timer = 0
				model.piece_recovered.emit(recovered_piece)
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
		elif event.kind == &"lunacy_changed":
			var color := String(event.data.get("color", ""))
			if color in ["white", "black"]:
				model.lunacy_by_color[color] = int(event.data.get("value", 0))
				model.socratic_turns_by_color[color] = int(event.data.get("socratic_turns_remaining", 0))
			model.lunacy_changed.emit(
				color,
				int(event.data.get("value", 0)),
				int(event.data.get("socratic_turns_remaining", 0))
			)
	model.current_turn = state.current_turn
	model.lunacy_by_color = state.lunacy_by_color.duplicate(true)
	model.socratic_turns_by_color = state.socratic_turns_by_color.duplicate(true)
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
	var projected_by_id := {}
	for row in model.board:
		for piece in row:
			if piece is ModelPiece:
				projected_by_id[piece.piece_id] = piece
	for raw_piece in model._owned_pieces.values():
		if is_instance_valid(raw_piece) and not projected_by_id.has(raw_piece.piece_id):
			projected_by_id[raw_piece.piece_id] = raw_piece
	for row in model.board:
		row.fill(null)
	for core_piece in state.pieces:
		var piece: ModelPiece = projected_by_id.get(core_piece.piece_id)
		if piece == null:
			piece = ChessPieceCatalog.create_piece(core_piece.type_id, core_piece.color, core_piece.coordinate)
			if piece == null: continue
			piece.piece_id = core_piece.piece_id
			model.inject_dependencies(piece)
			model.piece_added.emit(piece)
		_sync_piece_from_core(piece, core_piece)
		model.board[core_piece.coordinate.x][core_piece.coordinate.y] = piece


func _sync_piece_from_core(piece: ModelPiece, core_piece: ChessCorePiece) -> void:
	if piece == null or core_piece == null: return
	piece.coordinate = core_piece.coordinate
	piece.max_hp = core_piece.max_hp
	piece.current_hp = core_piece.current_hp
	piece.attack_power = core_piece.attack_power
	piece.has_moved = core_piece.has_moved
	piece.stunned = core_piece.stunned
	piece.stun_timer = core_piece.stun_timer
	piece.granted_movement_types.assign(core_piece.granted_movement_types)
	if piece is KingPiece:
		var king := piece as KingPiece
		king.current_cooldown = core_piece.current_cooldown
		king.cooldown_reset_pending = core_piece.cooldown_reset_pending
		king.initial_cooldown_turn_pending = core_piece.initial_cooldown_turn_pending
		if king is CannonKing:
			(king as CannonKing).scheduled_arc_cooldown = int(core_piece.custom_state.get("scheduled_arc_cooldown", king.base_cooldown))
		if king is ArcherKing:
			(king as ArcherKing).restore_custom_state(core_piece.custom_state)


func _present_turn_entry_consequences(events: Array[ChessCoreEvent]) -> void:
	var presenting_mortar := false
	var presenting_wraith := false
	var archer_presentation: PieceArrivalContext
	var archer_defender_id := ""
	for event in events:
		if event.kind == &"tile_effect_removed" and StringName(event.data.get("type_id", &"")) == &"cursed_mark":
			_present_tile_effect_removed(event)
		elif event.kind == &"tile_effect_refreshed" and StringName(event.data.get("type_id", &"")) == &"cursed_mark":
			_present_tile_effect_refreshed(event, state)
		elif event.kind == &"tile_effect_added" and StringName(event.data.get("spawn_reason", &"")) == &"wraith_projectile_capture":
			_present_tile_effect_added(event, state)
		elif event.kind == &"archer_attack_committed":
			var attacker := model.find_piece_by_id(String(event.data.get("attacker_id", ""))) as ArcherKing
			var defender := model.find_piece_by_id(String(event.data.get("defender_id", "")))
			if attacker != null and defender != null:
				archer_defender_id = defender.piece_id
				archer_presentation = PieceArrivalContext.new([attacker], true, true)
				model.archer_attack_committed.emit(attacker, defender, event.data.get("from", attacker.coordinate), event.data.get("to", defender.coordinate), archer_presentation)
				archer_presentation.close_claims()
				await archer_presentation.wait_for_impact()
		elif archer_presentation != null and event.kind == &"piece_damaged" and String(event.data.get("piece_id", "")) == archer_defender_id:
			var damaged := model.find_piece_by_id(archer_defender_id)
			if damaged != null:
				var amount := int(event.data.get("amount", 0))
				damaged.current_hp = int(event.data.get("current_hp", damaged.current_hp - amount))
				model.piece_damaged.emit(damaged, amount, damaged.current_hp, damaged.max_hp)
				if damaged.current_hp > 0:
					await archer_presentation.wait_for_aftermath()
					archer_presentation = null
		elif archer_presentation != null and event.kind == &"piece_destroyed" and String(event.data.get("piece_id", "")) == archer_defender_id:
			var destroyed := model.find_piece_by_id(archer_defender_id)
			if destroyed != null: model.destroy_piece(destroyed, true)
			await archer_presentation.wait_for_aftermath()
			archer_presentation = null
		elif event.kind == &"arc_mortar_impact":
			presenting_mortar = true
			var entity_id := String(event.data.get("entity_id", ""))
			var entity: ChessAutonomousEntityState
			for candidate in model.autonomous_entities:
				if candidate.entity_id == entity_id: entity = candidate; break
			if entity != null:
				var gate := CompletionGate.new()
				model.arc_mortar_impact.emit(entity, event.data.get("affected_coordinates", []).duplicate(), gate)
				gate.close()
				await gate.wait_until_released()
		elif presenting_mortar and event.kind == &"piece_damaged":
			var damaged := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if damaged != null:
				var amount := int(event.data.get("amount", 0))
				damaged.current_hp = int(event.data.get("current_hp", damaged.current_hp - amount))
				model.piece_damaged.emit(damaged, amount, damaged.current_hp, damaged.max_hp)
		elif presenting_mortar and event.kind == &"piece_destroyed":
			var destroyed := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if destroyed != null: model.destroy_piece(destroyed, true)
		elif presenting_mortar and event.kind == &"autonomous_entity_removed":
			await _present_entity_removed(event)
			presenting_mortar = false
		elif event.kind == &"autonomous_entity_moved":
			presenting_wraith = true
			var entity := _model_entity(String(event.data.get("entity_id", "")))
			if entity != null:
				var from: Vector2i = event.data.get("from", entity.coordinate)
				var to: Vector2i = event.data.get("to", entity.coordinate)
				entity.coordinate = to
				var gate := CompletionGate.new()
				model.autonomous_entity_moved.emit(entity, from, to, gate)
				gate.close()
				await gate.wait_until_released()
		elif presenting_wraith and event.kind == &"piece_damaged":
			var damaged := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if damaged != null:
				var amount := int(event.data.get("amount", 0))
				damaged.current_hp = int(event.data.get("current_hp", damaged.current_hp - amount))
				model.piece_damaged.emit(damaged, amount, damaged.current_hp, damaged.max_hp)
		elif presenting_wraith and event.kind == &"piece_destroyed":
			var destroyed := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if destroyed != null: model.destroy_piece(destroyed, true)
		elif presenting_wraith and event.kind == &"autonomous_entity_removed":
			await _present_entity_removed(event)
			presenting_wraith = false
		elif event.kind == &"piece_destroyed":
			# A lethal Wraith impact removes the projectile before reporting the
			# target's destruction. Keep destruction presentation independent of
			# the projectile's lifetime so the defeated view and its effect are not
			# left behind after the authoritative piece has gone away.
			var destroyed := model.find_piece_by_id(String(event.data.get("piece_id", "")))
			if destroyed != null: model.destroy_piece(destroyed, true)
		elif event.kind == &"autonomous_entity_removed":
			var removed_entity := _model_entity(String(event.data.get("entity_id", "")))
			if removed_entity != null and removed_entity.type_id == &"wraith": await _present_entity_removed(event)


func _model_entity(entity_id: String) -> ChessAutonomousEntityState:
	for entity in model.autonomous_entities:
		if entity.entity_id == entity_id: return entity
	return null


func _present_tile_effect_additions(events: Array[ChessCoreEvent], core_state: ChessCoreState) -> void:
	for event in events:
		if event.kind == &"tile_effect_refreshed" and StringName(event.data.get("spawn_reason", &"")) != &"wraith_projectile_capture":
			_present_tile_effect_refreshed(event, core_state)
		elif event.kind == &"tile_effect_added" and StringName(event.data.get("spawn_reason", &"")) != &"wraith_projectile_capture":
			_present_tile_effect_added(event, core_state)


func _present_tile_effect_added(event: ChessCoreEvent, core_state: ChessCoreState) -> void:
	var effect_id := String(event.data.get("effect_id", ""))
	if model.tile_effects.any(func(effect): return effect.effect_id == effect_id): return
	var core_effect: ChessCoreTileEffect = core_state.effects_by_id.get(effect_id)
	if core_effect == null: return
	var effect := core_effect.to_effect_state()
	model.tile_effects.append(effect)
	model._reserve_state_id(effect.effect_id)
	model.tile_effect_added.emit(effect)


func _present_tile_effect_removed(event: ChessCoreEvent) -> void:
	var effect_id := String(event.data.get("effect_id", ""))
	for effect in model.tile_effects.duplicate():
		if effect.effect_id != effect_id: continue
		model.tile_effects.erase(effect)
		model.tile_effect_removed.emit(effect)
		return


func _present_tile_effect_refreshed(event: ChessCoreEvent, core_state: ChessCoreState) -> void:
	var effect_id := String(event.data.get("effect_id", ""))
	var core_effect: ChessCoreTileEffect = core_state.effects_by_id.get(effect_id)
	if core_effect == null: return
	for effect in model.tile_effects:
		if effect.effect_id != effect_id: continue
		effect.owner_color = core_effect.owner_color
		effect.source_piece_id = core_effect.source_piece_id
		effect.custom_state = core_effect.custom_state.duplicate(true)
		model.tile_effect_refreshed.emit(effect)
		return


func _present_archer_state_events(events: Array[ChessCoreEvent]) -> void:
	for event in events:
		if event.kind != &"archer_state_changed": continue
		var archer := model.find_piece_by_id(String(event.data.get("piece_id", ""))) as ArcherKing
		if archer != null:
			model.archer_state_changed.emit(archer, StringName(event.data.get("state", &"idle")), String(event.data.get("message", "")))


func _present_archer_effect_events(events: Array[ChessCoreEvent]) -> void:
	_present_archer_state_events(events)
	for event in events:
		if event.kind == &"tile_effect_removed" and StringName(event.data.get("type_id", &"")) == &"archer_arrow":
			_present_tile_effect_removed(event)
		elif event.kind == &"archer_arrow_dropped":
			var effect_id := String(event.data.get("effect_id", ""))
			for effect in model.tile_effects:
				if effect.effect_id == effect_id:
					model.archer_arrow_dropped.emit(effect)
					break
		elif event.kind == &"archer_arrow_collected":
			var collector := model.find_piece_by_id(String(event.data.get("collector_id", "")))
			var archer := model.find_piece_by_id(String(event.data.get("piece_id", ""))) as ArcherKing
			if collector != null and archer != null: model.archer_arrow_collected.emit(collector, archer)


func _present_entity_removed(event: ChessCoreEvent) -> void:
	var entity_id := String(event.data.get("entity_id", ""))
	for entity in model.autonomous_entities.duplicate():
		if entity.entity_id != entity_id: continue
		model.autonomous_entities.erase(entity)
		var gate := CompletionGate.new()
		model.autonomous_entity_removed.emit(entity, StringName(event.data.get("reason", &"")), gate)
		gate.close()
		await gate.wait_until_released()
		return


func _validate_projection(context: String) -> bool:
	var projected := model._capture_projected_position()
	var authoritative := ClassicChessCore.export_position(state)
	if projected == null:
		_record_projection_mismatch("%s: projected position unavailable" % context)
		return false
	if authoritative == null:
		var reason := "authoritative position unavailable"
		if state == null:
			reason = "authoritative state unavailable"
		elif state.pending_choice != null:
			reason = "authoritative state still has pending choice '%s'" % String(state.pending_choice.kind)
		_record_projection_mismatch("%s: %s" % [context, reason])
		return false
	if ChessPositionCodec.to_json(projected, false) != ChessPositionCodec.to_json(authoritative, false):
		_record_projection_mismatch(context)
		return false
	return true
