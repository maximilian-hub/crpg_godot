extends RefCounted
class_name ClassicChessCore

const RhetoricianCoreRules := preload("res://scripts/core/pure/rhetorician_core_rules.gd")
const WraithCoreRules := preload("res://scripts/core/pure/wraith_core_rules.gd")
const ArcherCoreRules := preload("res://scripts/core/pure/archer_core_rules.gd")
const SUPPORTED_TYPES: Array[StringName] = [&"pawn", &"bone_pawn", &"knight", &"bishop", &"rook", &"queen", &"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king", &"quarterly_initiative_king", &"cannon_king", &"rhetorician_king", &"wraith_king", &"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge"]
const PROMOTION_OPTIONS: Array[StringName] = [&"queen", &"rook", &"bishop", &"knight"]
const MOVEMENT_GRANT_OPTIONS: Array[StringName] = [&"pawn", &"knight", &"bishop", &"rook"]
const MAX_CONSECUTIVE_FORCED_PASSES := 6


static func randomized_random_states() -> Dictionary:
	var lunacy := RandomNumberGenerator.new(); lunacy.randomize()
	var volley := RandomNumberGenerator.new(); volley.randomize()
	var curse_mark := RandomNumberGenerator.new(); curse_mark.randomize()
	return {
		&"lunacy": lunacy.state,
		&"archer_volley": volley.state,
		WraithCoreRules.CURSE_MARK_RANDOM_STREAM: curse_mark.state,
	}


static func seeded_random_state(seed: int) -> int:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	return rng.state


static func import_position(position: ChessPosition) -> Dictionary:
	if position == null:
		return {"ok": false, "error": "Position is null."}
	if position.board_size != Vector2i(8, 8) or position.board_type != &"default":
		return {"ok": false, "error": "Only the default 8x8 board is supported."}
	for color in ["white", "black"]:
		var lunacy := int(position.lunacy_by_color.get(color, 0))
		var socratic_turns := int(position.socratic_turns_by_color.get(color, 0))
		if lunacy < 0 or lunacy > RhetoricianCoreRules.LUNACY_THRESHOLD or socratic_turns < 0 or socratic_turns > RhetoricianCoreRules.SOCRATIC_TURN_COUNT:
			return {"ok": false, "error": "Invalid Rhetorician state."}
		if socratic_turns > 0 and not position.random_states.has(&"lunacy"):
			return {"ok": false, "error": "Active Socratic state requires a serialized Lunacy RNG."}
	var state := ChessCoreState.new()
	state.board_size = position.board_size
	state.board_type = position.board_type
	state.current_turn = position.current_turn
	state.battle_over = position.battle_over
	state.battle_result = position.battle_result
	state.defeated_king_colors.assign(position.defeated_king_colors)
	state.random_states = position.random_states.duplicate(true)
	state.lunacy_by_color = position.lunacy_by_color.duplicate(true)
	state.socratic_turns_by_color = position.socratic_turns_by_color.duplicate(true)
	state.global_turn_number = position.global_turn_number
	state.active_ability_cooldowns_disabled = position.active_ability_cooldowns_disabled
	var occupied := {}
	for source in position.pieces:
		var type_id := ChessPieceCatalog.normalize_type_id(source.type_id)
		if type_id not in SUPPORTED_TYPES:
			return {"ok": false, "error": "Unsupported Classic piece type: %s" % source.type_id}
		if type_id in ArcherCoreRules.TYPES:
			if not ArcherCoreRules.validate_custom_state(source):
				return {"ok": false, "error": "Invalid Archer custom state."}
		elif type_id == &"cannon_king":
			if source.custom_state.keys().any(func(key): return String(key) != "scheduled_arc_cooldown"):
				return {"ok": false, "error": "Unsupported Cannon custom state."}
		elif not source.custom_state.is_empty():
			return {"ok": false, "error": "Custom piece state is outside the Classic slice."}
		for movement_type in source.granted_movement_types:
			if movement_type not in MOVEMENT_GRANT_OPTIONS:
				return {"ok": false, "error": "Unsupported granted movement type: %s" % movement_type}
		if not ChessCoreKingRules.is_supported_king(type_id) and (source.current_cooldown != 0 or source.cooldown_reset_pending or source.initial_cooldown_turn_pending):
			return {"ok": false, "error": "Active-ability cooldown state is outside the Classic slice."}
		if source.coordinate.x < 0 or source.coordinate.y < 0 or source.coordinate.x >= 8 or source.coordinate.y >= 8 or occupied.has(source.coordinate):
			return {"ok": false, "error": "Piece coordinates are invalid or overlapping."}
		var piece := ChessCorePiece.from_piece_state(source)
		if type_id in ArcherCoreRules.TYPES:
			ArcherCoreRules.normalize_custom_state(piece)
		if piece.piece_id.is_empty(): piece.piece_id = state.allocate_piece_id()
		_reserve_id(state, piece.piece_id)
		state.add_piece(piece)
		occupied[piece.coordinate] = true
	for source_effect in position.tile_effects:
		if source_effect.type_id not in [&"cursed_mark", &"archer_arrow"]:
			return {"ok": false, "error": "Unsupported tile effect: %s" % source_effect.type_id}
		if source_effect.owner_color not in ["white", "black"] or not _in_bounds(source_effect.coordinate) or not source_effect.custom_state.is_empty():
			return {"ok": false, "error": "Invalid Cursed Mark state."}
		var effect_source := state.piece_by_id(source_effect.source_piece_id)
		if source_effect.type_id == &"cursed_mark" and (effect_source == null or effect_source.type_id != &"wraith_king" or effect_source.color != source_effect.owner_color):
			return {"ok": false, "error": "Cursed Mark source is not its owning Wraith King."}
		if source_effect.type_id == &"archer_arrow" and (effect_source == null or effect_source.type_id not in ArcherCoreRules.QUIVER_TYPES or effect_source.color != source_effect.owner_color):
			return {"ok": false, "error": "Archer Arrow source is not its owning Quiver Archer."}
		var effect := ChessCoreTileEffect.from_effect_state(source_effect)
		if effect.effect_id.is_empty(): effect.effect_id = state.allocate_state_id("effect")
		if state.effects_by_id.has(effect.effect_id): return {"ok": false, "error": "Duplicate tile-effect id."}
		_reserve_id(state, effect.effect_id)
		state.add_effect(effect)
	for source_entity in position.autonomous_entities:
		if source_entity.type_id not in [&"arc_mortar", &"wraith"]:
			return {"ok": false, "error": "Unsupported autonomous entity: %s" % source_entity.type_id}
		if source_entity.owner_color not in ["white", "black"] or not _in_bounds(source_entity.coordinate):
			return {"ok": false, "error": "Autonomous entity owner or coordinate is invalid."}
		if source_entity.type_id == &"arc_mortar":
			if source_entity.coordinate.x >= 7 or source_entity.coordinate.y >= 7 or source_entity.custom_state.keys().any(func(key): return String(key) != "landing_turn"):
				return {"ok": false, "error": "Unsupported Arc Mortar state."}
		else:
			if source_entity.custom_state.keys().any(func(key): return String(key) != "next_move_turn"):
				return {"ok": false, "error": "Unsupported Wraith custom state."}
			var wraith_source := state.piece_by_id(source_entity.source_piece_id)
			var wraith_target := state.piece_by_id(source_entity.target_piece_id)
			if wraith_source == null or wraith_source.type_id != &"wraith_king" or wraith_source.color != source_entity.owner_color or wraith_target == null or wraith_target.color == source_entity.owner_color:
				return {"ok": false, "error": "Wraith source or target is invalid."}
		var entity := ChessCoreAutonomousEntity.from_entity_state(source_entity)
		if entity.entity_id.is_empty(): entity.entity_id = state.allocate_state_id("entity")
		if state.entities_by_id.has(entity.entity_id): return {"ok": false, "error": "Duplicate autonomous-entity id."}
		_reserve_id(state, entity.entity_id)
		state.add_entity(entity)
	if position.last_move != null and position.last_move.is_present:
		var moved_id := ""
		var candidate := state.occupant(position.last_move.to)
		if candidate != null and candidate.color == position.last_move.piece_color and candidate.type_id == ChessPieceCatalog.normalize_type_id(position.last_move.piece_type_id):
			moved_id = candidate.piece_id
		state.last_move = {
			"piece_id": moved_id,
			"piece_type": ChessPieceCatalog.normalize_type_id(position.last_move.piece_type_id),
			"piece_color": position.last_move.piece_color,
			"from": position.last_move.from,
			"to": position.last_move.to,
		}
	return {"ok": true, "state": state, "error": ""}


static func export_position(state: ChessCoreState) -> ChessPosition:
	if state == null or state.pending_choice != null:
		return null
	var result := ChessPosition.new()
	result.board_size = state.board_size
	result.board_type = state.board_type
	result.current_turn = state.current_turn
	result.battle_over = state.battle_over
	result.battle_result = state.battle_result
	result.defeated_king_colors.assign(state.defeated_king_colors)
	result.random_states = state.random_states.duplicate(true)
	result.lunacy_by_color = state.lunacy_by_color.duplicate(true)
	result.socratic_turns_by_color = state.socratic_turns_by_color.duplicate(true)
	result.global_turn_number = state.global_turn_number
	result.active_ability_cooldowns_disabled = state.active_ability_cooldowns_disabled
	for piece in state.pieces: result.pieces.append(piece.to_piece_state())
	for effect in state.tile_effects: result.tile_effects.append(effect.to_effect_state())
	for entity in state.autonomous_entities: result.autonomous_entities.append(entity.to_entity_state())
	if not state.last_move.is_empty():
		result.last_move.is_present = true
		result.last_move.from = state.last_move.get("from", Vector2i.ZERO)
		result.last_move.to = state.last_move.get("to", Vector2i.ZERO)
		result.last_move.piece_type_id = state.last_move.get("piece_type", &"")
		result.last_move.piece_color = state.last_move.get("piece_color", "")
	return result


static func legal_actions(state: ChessCoreState, color: String) -> Array[ChessCoreAction]:
	var result: Array[ChessCoreAction] = []
	if state == null or state.battle_over or state.pending_choice != null or color != state.current_turn:
		return result
	return analysis_actions(state, color)


## Rule-only action enumeration for evaluation and search ordering. Unlike the
## command-facing legal_actions(), this may query either color without changing
## the state or pretending that color owns the current turn.
static func analysis_actions(state: ChessCoreState, color: String) -> Array[ChessCoreAction]:
	var result: Array[ChessCoreAction] = []
	if state == null or state.battle_over or state.pending_choice != null or color not in ["white", "black"]:
		return result
	var ordered: Array = state.analysis_cache.get("ordered_pieces", [])
	var ordered_cache_hit := not ordered.is_empty() or state.pieces.is_empty()
	var profile_ordering := state.performance_metrics != null and state.performance_metrics.detailed_analysis_enabled
	var ordered_started := Time.get_ticks_usec() if profile_ordering else 0
	if ordered.is_empty() and not state.pieces.is_empty():
		ordered = state.pieces.duplicate()
		ordered.sort_custom(func(a: ChessCorePiece, b: ChessCorePiece):
			if a.coordinate.x != b.coordinate.x: return a.coordinate.x < b.coordinate.x
			return a.coordinate.y < b.coordinate.y
		)
		state.analysis_cache["ordered_pieces"] = ordered
	if profile_ordering:
		state.performance_metrics.record_ordered_pieces(Time.get_ticks_usec() - ordered_started, ordered_cache_hit)
	for piece: ChessCorePiece in ordered:
		if piece.color != color or piece.stunned or piece.current_hp <= 0:
			continue
		var movement_paths := _legal_paths(state, piece, false)
		for movement_type in piece.granted_movement_types:
			for destination in _moves_as(state, piece, movement_type):
				movement_paths.append([destination])
		var accepted_paths: Array[Array] = []
		for path in movement_paths:
			if not path.is_empty() and not _rhetorician_attack_blocked(state, piece, path.back()):
				accepted_paths.append(path)
		movement_paths = accepted_paths
		if piece.type_id == &"arakne_king":
			for path in movement_paths:
				var action := ChessCoreAction.new()
				action.piece_id = piece.piece_id
				action.color = piece.color
				action.from = piece.coordinate
				action.target = path.back()
				action.path.assign(path)
				result.append(action)
		else:
			for path in movement_paths:
				var target: Vector2i = path.back()
				var action := ChessCoreAction.new()
				action.piece_id = piece.piece_id
				action.color = piece.color
				action.from = piece.coordinate
				action.target = target
				action.path = [target]
				result.append(action)
		var rules = ChessCoreKingRules.for_type(piece.type_id)
		if rules != null and _ability_ready(state, piece):
			for target in rules.active_targets(state, piece):
				var action := ChessCoreAction.new()
				action.kind = ChessCoreAction.Kind.ACTIVE_ABILITY
				action.piece_id = piece.piece_id
				action.color = piece.color
				action.from = piece.coordinate
				action.target = target
				result.append(action)
		if ArcherCoreRules.uses_charge(piece) and ArcherCoreRules.charge_level(piece) == 0 and not ArcherCoreRules.is_suppressed(state, piece):
			var charge := ChessCoreAction.new()
			charge.kind = ChessCoreAction.Kind.ARCHER_CHARGE
			charge.piece_id = piece.piece_id
			charge.color = piece.color
			charge.from = piece.coordinate
			charge.target = piece.coordinate
			result.append(charge)
	return result


## Direct attack geometry used by tactical analysis. This intentionally excludes
## castling and pawn forward movement, matching ModelPiece's attack relationship
## rather than command legality.
static func directly_attacks_square(state: ChessCoreState, piece: ChessCorePiece, target: Vector2i) -> bool:
	if state == null or piece == null or piece.stunned or piece.current_hp <= 0 or not _in_bounds(target) or target == piece.coordinate:
		return false
	if _rhetorician_attack_blocked(state, piece, target):
		return false
	if piece.type_id in ArcherCoreRules.TYPES:
		return ArcherCoreRules.can_ranged_attack(state, piece, target)
	return directly_attacks_in_occupancy(piece, piece.coordinate, target, state.occupancy)


## Projected-board variant for AI and editor analysis. The occupancy values stay
## pure-data pieces; callers may cheaply move references between squares without
## cloning or resolving a turn.
static func directly_attacks_in_occupancy(piece: ChessCorePiece, origin: Vector2i, target: Vector2i, occupancy: Dictionary) -> bool:
	if piece == null or piece.stunned or piece.current_hp <= 0 or not _in_bounds(target) or target == origin:
		return false
	var defender = occupancy.get(target)
	if defender is ChessCorePiece and defender.type_id == &"rhetorician_king" and defender.color != piece.color and maxi(absi(origin.x - target.x), absi(origin.y - target.y)) == 1:
		return false
	if piece.type_id in ArcherCoreRules.TYPES:
		var projected := ChessCoreState.new()
		projected.occupancy = occupancy
		return ArcherCoreRules.can_ranged_attack(projected, piece, target)
	return geometrically_attacks_in_occupancy(piece, origin, target, occupancy)


## Raw piece geometry used by AI relationship maps and Rhetorician Lunacy.
## Command legality applies Can Words Prevent Harm? separately.
static func geometrically_attacks_in_occupancy(piece: ChessCorePiece, origin: Vector2i, target: Vector2i, occupancy: Dictionary) -> bool:
	if piece == null or piece.stunned or piece.current_hp <= 0 or not _in_bounds(target) or target == origin:
		return false
	if _movement_type_attacks(piece.type_id, piece.color, origin, target, occupancy):
		return true
	for movement_type in piece.granted_movement_types:
		if _movement_type_attacks(movement_type, piece.color, origin, target, occupancy):
			return true
	return false


static func _movement_type_attacks(type_id: StringName, color: String, origin: Vector2i, target: Vector2i, occupancy: Dictionary) -> bool:
	var delta := target - origin
	match type_id:
		&"pawn", &"bone_pawn":
			var direction := -1 if color == "white" else 1
			return delta.x == direction and absi(delta.y) == 1
		&"knight":
			return Vector2i(absi(delta.x), absi(delta.y)) in [Vector2i(1, 2), Vector2i(2, 1)]
		&"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king", &"quarterly_initiative_king", &"cannon_king", &"rhetorician_king", &"wraith_king":
			return absi(delta.x) <= 1 and absi(delta.y) <= 1
		&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge":
			# Archer threats require variant state and suppression, so callers with a
			# full state use directly_attacks_square().
			return false
		&"bishop":
			return absi(delta.x) == absi(delta.y) and _occupancy_ray_is_clear(occupancy, origin, target)
		&"rook":
			return (delta.x == 0 or delta.y == 0) and _occupancy_ray_is_clear(occupancy, origin, target)
		&"queen":
			return (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y)) and _occupancy_ray_is_clear(occupancy, origin, target)
	return false


static func attackers(state: ChessCoreState, target: Vector2i, color := "") -> Array[ChessCorePiece]:
	var result: Array[ChessCorePiece] = []
	if state == null: return result
	for piece in state.pieces:
		if (color.is_empty() or piece.color == color) and directly_attacks_square(state, piece, target):
			result.append(piece)
	return result


static func resolve_action(source: ChessCoreState, submitted: ChessCoreAction, emit_events := true) -> ChessCoreStepResult:
	var resolution_started := Time.get_ticks_usec()
	var result := _resolve_action_unprofiled(source, submitted, emit_events)
	if source != null and source.performance_metrics != null and submitted != null:
		var king_type: StringName = &""
		var source_piece := source.piece_by_id(submitted.piece_id)
		if source_piece != null:
			for candidate in source.pieces:
				if candidate.color == source_piece.color and candidate.is_king():
					king_type = candidate.type_id
					break
		source.performance_metrics.record_resolution(submitted.kind, king_type, Time.get_ticks_usec() - resolution_started, result.events.size(), emit_events)
	return result


static func _resolve_action_unprofiled(source: ChessCoreState, submitted: ChessCoreAction, emit_events := true) -> ChessCoreStepResult:
	if source == null or submitted == null:
		return ChessCoreStepResult.rejected(source, "State and action are required.")
	# Validate the submitted command directly. Enumerating every legal action here
	# duplicated work already performed by the search and dominated short plies.
	var piece := source.piece_by_id(submitted.piece_id)
	if (
		piece == null
		or source.battle_over
		or source.pending_choice != null
		or piece.color != source.current_turn
		or piece.stunned
		or piece.current_hp <= 0
		or submitted.color != piece.color
		or submitted.from != piece.coordinate
	):
		return ChessCoreStepResult.rejected(source, "Action is not legal in this state.")
	if submitted.kind == ChessCoreAction.Kind.ACTIVE_ABILITY:
		return _resolve_active_ability(source, submitted, emit_events)
	if submitted.kind == ChessCoreAction.Kind.ARCHER_CHARGE:
		return _resolve_archer_charge(source, submitted, emit_events)
	var legal_move := false
	if submitted.kind == ChessCoreAction.Kind.MOVE and not submitted.path.is_empty() and submitted.target == submitted.path.back():
		var legal_paths := _legal_paths(source, piece)
		for movement_type in piece.granted_movement_types:
			for destination in _moves_as(source, piece, movement_type):
				if not _rhetorician_attack_blocked(source, piece, destination): legal_paths.append([destination])
		legal_move = submitted.path in legal_paths
	if not legal_move:
		return ChessCoreStepResult.rejected(source, "Action is not legal in this state.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	_append_event(result.events, emit_events, &"action_started", {"color": state.current_turn})
	state.consecutive_forced_passes = 0
	state.resolution_context = {"action_owner": state.current_turn, "primary_piece_id": submitted.piece_id, "wraith_bonus_used": false}
	piece = state.piece_by_id(submitted.piece_id)
	var origin := piece.coordinate
	var target_piece := state.occupant(submitted.target)
	var is_en_passant := piece.type_id == &"pawn" and target_piece == null and origin.y != submitted.target.y and _en_passant_victim(state, piece, submitted.target) != null
	var is_castle := piece.is_king() and submitted.path.size() == 1 and _can_castle(state, piece, submitted.target)
	if is_castle:
		_resolve_castle(state, piece, submitted.target, result.events, emit_events)
	elif submitted.path.size() == 2 and piece.type_id == &"arakne_king":
		var intermediate: Vector2i = submitted.path[0]
		state.move_piece(piece, intermediate)
		piece.has_moved = true
		_append_event(result.events, emit_events, &"piece_moved", {"piece_id": piece.piece_id, "from": origin, "to": intermediate})
		_append_event(result.events, emit_events, &"piece_landed", {"piece_id": piece.piece_id, "from": origin, "to": intermediate})
		_append_event(result.events, emit_events, &"skitter_step_started", {"piece_id": piece.piece_id, "from": intermediate, "to": submitted.target})
		state.move_piece(piece, submitted.target)
		_append_event(result.events, emit_events, &"piece_moved", {"piece_id": piece.piece_id, "from": intermediate, "to": submitted.target})
		_append_event(result.events, emit_events, &"piece_landed", {"piece_id": piece.piece_id, "from": intermediate, "to": submitted.target})
	elif is_en_passant:
		var victim := _en_passant_victim(state, piece, submitted.target)
		_commit_capture(state, piece, victim, submitted.target, victim.coordinate, result.events, emit_events)
	elif piece.type_id in ArcherCoreRules.TYPES and target_piece != null:
		_resolve_archer_attack(state, piece, target_piece, result.events, emit_events)
	elif target_piece != null:
		if target_piece.current_hp <= piece.attack_power:
			_commit_capture(state, piece, target_piece, submitted.target, submitted.target, result.events, emit_events)
		else:
			_deal_damage(state, target_piece, piece.attack_power, result.events, emit_events)
	else:
		if piece.type_id in ArcherCoreRules.TYPES and ArcherCoreRules.charge_level(piece) > 0:
			_cancel_archer_draw(piece, result.events, emit_events, "Draw Cancelled")
		state.move_piece(piece, submitted.target)
		piece.has_moved = true
		_append_event(result.events, emit_events, &"piece_moved", {"piece_id": piece.piece_id, "from": origin, "to": submitted.target})
		_append_event(result.events, emit_events, &"piece_landed", {"piece_id": piece.piece_id, "from": origin, "to": submitted.target})
		_collect_archer_arrows(state, piece, submitted.target, result.events, emit_events)
		_wraith_on_landed(state, piece, result.events, emit_events)
	state.last_move = {"piece_id": piece.piece_id, "piece_type": piece.type_id, "piece_color": piece.color, "from": origin, "to": submitted.target}
	if piece.type_id == &"bone_pawn" and state.piece_by_id(piece.piece_id) != null and _is_terminal_rank(piece):
		_destroy_piece(state, piece, piece.coordinate, result.events, emit_events)
	if not state.defeated_king_colors.is_empty():
		_complete_battle(state, result.events, emit_events)
		result.status = ChessCoreStepResult.Status.COMPLETED
		return result
	if piece.type_id == &"pawn" and piece.coordinate.x == (0 if piece.color == "white" else 7):
		var choice := ChessCoreChoice.new()
		choice.kind = &"promotion"
		choice.piece_id = piece.piece_id
		choice.options.assign(PROMOTION_OPTIONS)
		state.pending_choice = choice
		state.resolution_context = {"action_owner": piece.color}
		result.choice = choice.copy()
		_append_event(result.events, emit_events, &"choice_requested", {"kind": &"promotion", "piece_id": piece.piece_id, "options": Array(PROMOTION_OPTIONS)})
		result.status = ChessCoreStepResult.Status.PENDING_CHOICE
		return result
	_complete_or_pause(state, result, emit_events)
	return result


static func _resolve_archer_charge(source: ChessCoreState, submitted: ChessCoreAction, emit_events: bool) -> ChessCoreStepResult:
	var piece := source.piece_by_id(submitted.piece_id)
	if piece == null or piece.type_id != ArcherCoreRules.CHARGE_TYPE or submitted.color != piece.color or submitted.from != piece.coordinate or submitted.target != piece.coordinate or not submitted.path.is_empty() or piece.color != source.current_turn or piece.stunned or ArcherCoreRules.charge_level(piece) != 0 or ArcherCoreRules.is_suppressed(source, piece):
		return ChessCoreStepResult.rejected(source, "Archer charge is not legal in this state.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	piece = state.piece_by_id(submitted.piece_id)
	state.resolution_context = {"action_owner": state.current_turn, "primary_piece_id": piece.piece_id, "archer_charge_started": true, "wraith_bonus_used": false}
	state.consecutive_forced_passes = 0
	piece.custom_state["charge_level"] = 1
	_append_event(result.events, emit_events, &"action_started", {"color": state.current_turn})
	_append_event(result.events, emit_events, &"archer_state_changed", {"piece_id": piece.piece_id, "state": &"drawing", "message": "Drawing Bow"})
	_complete_or_pause(state, result, emit_events)
	return result


static func _resolve_archer_attack(state: ChessCoreState, archer: ChessCorePiece, defender: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if ArcherCoreRules.uses_draw(archer) and ArcherCoreRules.draw_target(archer) == Vector2i(-1, -1):
		archer.custom_state["draw_target"] = [defender.coordinate.x, defender.coordinate.y]
		archer.custom_state["draw_target_piece_id"] = defender.piece_id
		archer.custom_state["draw_turns_waited"] = 0
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"drawing", "message": "Drawing Bow"})
		return
	_append_event(events, emit_events, &"archer_attack_committed", {"attacker_id": archer.piece_id, "defender_id": defender.piece_id, "from": archer.coordinate, "to": defender.coordinate})
	if ArcherCoreRules.uses_quiver(archer):
		archer.custom_state["arrows"] = maxi(0, ArcherCoreRules.arrows(archer) - 1)
		_drop_archer_arrow(state, archer, defender.coordinate, events, emit_events)
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"quiver", "message": "Arrow Fired — %d Remaining" % ArcherCoreRules.arrows(archer)})
	if ArcherCoreRules.uses_charge(archer):
		_cancel_archer_draw(archer, events, emit_events, "")
	_deal_damage(state, defender, 1, events, emit_events)


static func _resolve_archer_volley(state: ChessCoreState, archer: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var enemy_color := "black" if archer.color == "white" else "white"
	var rear_rank := 7 if enemy_color == "white" else 0
	var furthest_rank := rear_rank
	for piece in state.pieces:
		if piece.color != enemy_color: continue
		furthest_rank = mini(furthest_rank, piece.coordinate.x) if enemy_color == "white" else maxi(furthest_rank, piece.coordinate.x)
	var candidates: Array[Vector2i] = []
	for row in range(mini(rear_rank, furthest_rank), maxi(rear_rank, furthest_rank) + 1):
		for column in range(8): candidates.append(Vector2i(row, column))
	var rng := RandomNumberGenerator.new()
	rng.state = int(state.random_states.get(&"archer_volley", 0))
	var targets: Array[Vector2i] = []
	while not candidates.is_empty() and targets.size() < ArcherCoreRules.VOLLEY_SQUARE_COUNT:
		targets.append(candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
	state.random_states[&"archer_volley"] = rng.state
	_append_event(events, emit_events, &"archer_volley_committed", {"piece_id": archer.piece_id, "targets": targets.duplicate()})
	for coordinate in targets:
		var occupant := state.occupant(coordinate)
		if occupant != null: _deal_damage(state, occupant, 1, events, emit_events)


static func _drop_archer_arrow(state: ChessCoreState, archer: ChessCorePiece, coordinate: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var effect := ChessCoreTileEffect.new()
	effect.effect_id = state.allocate_state_id("effect")
	effect.type_id = &"archer_arrow"
	effect.coordinate = coordinate
	effect.owner_color = archer.color
	effect.source_piece_id = archer.piece_id
	state.add_effect(effect)
	_append_event(events, emit_events, &"tile_effect_added", {"effect_id": effect.effect_id, "type_id": effect.type_id, "coordinate": coordinate, "owner_color": effect.owner_color, "source_piece_id": effect.source_piece_id})
	_append_event(events, emit_events, &"archer_arrow_dropped", {"effect_id": effect.effect_id, "piece_id": archer.piece_id, "coordinate": coordinate})


static func _collect_archer_arrows(state: ChessCoreState, collector: ChessCorePiece, coordinate: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	for effect in state.tile_effects.duplicate():
		if effect.type_id != &"archer_arrow" or effect.coordinate != coordinate or effect.owner_color != collector.color: continue
		var archer := state.piece_by_id(effect.source_piece_id)
		if archer == null or not ArcherCoreRules.uses_quiver(archer) or ArcherCoreRules.arrows(archer) >= 2: continue
		archer.custom_state["arrows"] = ArcherCoreRules.arrows(archer) + 1
		state.remove_effect(effect)
		_append_event(events, emit_events, &"tile_effect_removed", {"effect_id": effect.effect_id, "type_id": effect.type_id, "coordinate": coordinate, "source_piece_id": effect.source_piece_id})
		_append_event(events, emit_events, &"archer_arrow_collected", {"collector_id": collector.piece_id, "piece_id": archer.piece_id, "effect_id": effect.effect_id})
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"quiver", "message": "Arrow Recovered — %d/2" % ArcherCoreRules.arrows(archer)})


static func _cancel_archer_draw(archer: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool, message: String) -> void:
	archer.custom_state["draw_target"] = [-1, -1]
	archer.custom_state["draw_target_piece_id"] = ""
	archer.custom_state["draw_turns_waited"] = 0
	archer.custom_state["charge_level"] = 0
	_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"idle", "message": message})


static func _resolve_active_ability(source: ChessCoreState, submitted: ChessCoreAction, emit_events: bool) -> ChessCoreStepResult:
	var source_piece := source.piece_by_id(submitted.piece_id)
	var rules = ChessCoreKingRules.for_type(source_piece.type_id) if source_piece != null else null
	if rules == null or not submitted.path.is_empty() or not _ability_ready(source, source_piece) or submitted.target not in rules.active_targets(source, source_piece):
		return ChessCoreStepResult.rejected(source, "Active ability is not legal in this state.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	_append_event(result.events, emit_events, &"action_started", {"color": state.current_turn})
	state.consecutive_forced_passes = 0
	state.resolution_context = {"action_owner": state.current_turn, "wraith_bonus_used": false}
	var piece := state.piece_by_id(submitted.piece_id)
	var target := state.occupant(submitted.target)
	var effect: Dictionary = rules.active_effect(state, piece, target)
	_append_event(result.events, emit_events, &"ability_committed", {
		"piece_id": piece.piece_id,
		"ability_id": effect.get("ability_id", &""),
		"target": submitted.target,
		"target_piece_id": target.piece_id if target != null else "",
	})
	if effect.get("movement_grant", false):
		var hp_cost := int(effect.get("hp_cost", 0))
		if hp_cost > 0: _deal_damage(state, piece, hp_cost, result.events, emit_events)
		if not state.defeated_king_colors.is_empty():
			_complete_battle(state, result.events, emit_events)
			result.status = ChessCoreStepResult.Status.COMPLETED
			return result
		var choice := ChessCoreChoice.new()
		choice.kind = &"movement_type_grant"
		choice.piece_id = piece.piece_id
		choice.target_piece_id = String(effect.get("target_piece_id", ""))
		choice.options.assign(effect.get("options", []))
		state.pending_choice = choice
		result.choice = choice.copy()
		_append_event(result.events, emit_events, &"choice_requested", {"kind": choice.kind, "piece_id": piece.piece_id, "target_piece_id": choice.target_piece_id, "options": choice.options.duplicate()})
		result.status = ChessCoreStepResult.Status.PENDING_CHOICE
		return result
	if effect.get("compel", false):
		_resolve_compel(state, piece, target, effect.get("destination", Vector2i(-1, -1)), result.events, emit_events)
		if target != null and state.piece_by_id(target.piece_id) != null and target.type_id == &"pawn" and _is_terminal_rank(target):
			var choice := ChessCoreChoice.new()
			choice.kind = &"promotion"
			choice.piece_id = target.piece_id
			choice.options.assign(PROMOTION_OPTIONS)
			state.pending_choice = choice
			state.resolution_context["deferred_ability_cooldown_piece_id"] = piece.piece_id
			result.choice = choice.copy()
			_append_event(result.events, emit_events, &"choice_requested", {"kind": &"promotion", "piece_id": target.piece_id, "options": Array(PROMOTION_OPTIONS)})
			result.status = ChessCoreStepResult.Status.PENDING_CHOICE
			return result
	elif effect.get("arc_mortar", false):
		_launch_arc_mortar(state, piece, submitted.target, result.events, emit_events)
	elif effect.get("summon_wraith", false):
		_summon_wraith(state, piece, target, result.events, emit_events)
	elif effect.get("archer_volley", false):
		_resolve_archer_volley(state, piece, result.events, emit_events)
	elif effect.has("summon_type"):
		_summon_bone_pawn(state, piece.color, submitted.target, result.events, emit_events)
	elif effect.get("charge", false):
		_resolve_charge(state, piece, submitted.target, target, int(effect.get("damage", 2)), result.events, emit_events)
	else:
		var damage := int(effect.get("damage", 0))
		_deal_damage(state, target, damage, result.events, emit_events)
	_schedule_cooldown(state, piece, result.events, emit_events)
	if not state.defeated_king_colors.is_empty():
		_complete_battle(state, result.events, emit_events)
		result.status = ChessCoreStepResult.Status.COMPLETED
	else: _complete_or_pause(state, result, emit_events)
	return result


static func resolve_choice(source: ChessCoreState, option, emit_events := true) -> ChessCoreStepResult:
	if source == null or source.pending_choice == null:
		return ChessCoreStepResult.rejected(source, "No choice is pending.")
	if option not in source.pending_choice.options:
		return ChessCoreStepResult.rejected(source, "Choice is invalid.")
	if source.pending_choice.kind == &"raise_dead":
		return _resolve_raise_dead_choice(source, option, emit_events)
	if source.pending_choice.kind == &"movement_type_grant":
		return _resolve_movement_type_grant_choice(source, option, emit_events)
	if source.pending_choice.kind == &"lingering_malice":
		return _resolve_lingering_malice_choice(source, option, emit_events)
	if source.pending_choice.kind != &"promotion":
		return ChessCoreStepResult.rejected(source, "The pending choice kind is unsupported.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	var pawn := state.piece_by_id(state.pending_choice.piece_id)
	if pawn == null or pawn.type_id != &"pawn":
		return ChessCoreStepResult.rejected(source, "The promoting pawn is no longer present.")
	var old_id := pawn.piece_id
	var coordinate := pawn.coordinate
	var color := pawn.color
	state.remove_piece(pawn)
	var promoted := ChessCorePiece.new()
	promoted.type_id = option
	promoted.piece_id = state.allocate_piece_id()
	promoted.color = color
	promoted.coordinate = coordinate
	# Match ChessBoardModel.transform_piece(): promotion creates a fresh piece
	# whose movement history starts unset. This is significant for promoted rooks.
	promoted.has_moved = false
	state.add_piece(promoted)
	state.pending_choice = null
	_append_event(result.events, emit_events, &"piece_promoted", {"old_piece_id": old_id, "new_piece_id": promoted.piece_id, "piece_type": option, "coordinate": coordinate})
	var deferred_cooldown_id := String(state.resolution_context.get("deferred_ability_cooldown_piece_id", ""))
	if not deferred_cooldown_id.is_empty():
		state.resolution_context.erase("deferred_ability_cooldown_piece_id")
		_schedule_cooldown(state, state.piece_by_id(deferred_cooldown_id), result.events, emit_events)
	_complete_or_pause(state, result, emit_events)
	return result


static func resolve_forced_passes(source: ChessCoreState, emit_events := true) -> ChessCoreStepResult:
	if source == null or source.pending_choice != null:
		return ChessCoreStepResult.rejected(source, "A settled state is required.")
	var result := ChessCoreStepResult.new()
	result.state = source.copy()
	_resolve_forced_passes(result.state, result.events, emit_events)
	if bool(result.state.resolution_context.get("socratic_ready", false)):
		var nested := _begin_socratic_resolution(result.state, emit_events)
		result.events.append_array(nested.events)
		result.state = nested.state
		result.choice = nested.choice
		result.status = nested.status
		return result
	if result.state.pending_choice != null:
		result.choice = result.state.pending_choice.copy()
		result.status = ChessCoreStepResult.Status.PENDING_CHOICE
	else:
		result.status = ChessCoreStepResult.Status.COMPLETED
	return result


static func _legal_destinations(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	match piece.type_id:
		&"pawn": return _pawn_moves(state, piece)
		&"bone_pawn": return _bone_pawn_moves(state, piece)
		&"knight": return _jump_moves(state, piece, [Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2)])
		&"bishop": return _ray_moves(state, piece, [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)])
		&"rook": return _ray_moves(state, piece, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)])
		&"queen": return _ray_moves(state, piece, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)])
		&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge":
			var moves: Array[Vector2i] = []
			if ArcherCoreRules.uses_draw(piece) and ArcherCoreRules.draw_target(piece) != Vector2i(-1, -1):
				return moves
			for row in range(8):
				for column in range(8):
					var target := Vector2i(row, column)
					var occupant := state.occupant(target)
					var distance := maxi(absi(target.x - piece.coordinate.x), absi(target.y - piece.coordinate.y))
					if distance == 1 and occupant == null:
						moves.append(target)
					elif ArcherCoreRules.can_ranged_attack(state, piece, target):
						moves.append(target)
			return moves
		&"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king", &"quarterly_initiative_king", &"cannon_king", &"rhetorician_king", &"wraith_king":
			var moves: Array[Vector2i] = []
			# Preserve the former row-major order while visiting only the king's
			# neighborhood instead of scanning all 64 squares for every query.
			for row in range(maxi(0, piece.coordinate.x - 1), mini(7, piece.coordinate.x + 1) + 1):
				for column in range(maxi(0, piece.coordinate.y - 1), mini(7, piece.coordinate.y + 1) + 1):
					var target := Vector2i(row, column)
					var delta := target - piece.coordinate
					var quarterly_efficiency := piece.type_id == &"quarterly_initiative_king" and state.occupant(target) != null and state.occupant(target).color == piece.color
					if target != piece.coordinate and absi(delta.x) <= 1 and absi(delta.y) <= 1 and (_available(state, target, piece.color) or quarterly_efficiency): moves.append(target)
			if not piece.has_moved:
				for target in [Vector2i(7 if piece.color == "white" else 0, 2), Vector2i(7 if piece.color == "white" else 0, 6)]:
					if _can_castle(state, piece, target): moves.append(target)
			return moves
	return []


static func _moves_as(state: ChessCoreState, piece: ChessCorePiece, movement_type: StringName) -> Array[Vector2i]:
	match movement_type:
		&"pawn": return _pawn_moves(state, piece)
		&"knight": return _jump_moves(state, piece, [Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2)])
		&"bishop": return _ray_moves(state, piece, [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)])
		&"rook": return _ray_moves(state, piece, [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	return []


static func _legal_paths(state: ChessCoreState, piece: ChessCorePiece, filter_rhetorician := true) -> Array[Array]:
	var destinations := _legal_destinations(state, piece)
	if filter_rhetorician:
		destinations = destinations.filter(func(destination): return not _rhetorician_attack_blocked(state, piece, destination))
	if piece.type_id == &"arakne_king":
		return ArakneCoreRules.movement_paths(state, piece, destinations)
	var result: Array[Array] = []
	for destination in destinations:
		result.append([destination])
	return result


static func _rhetorician_attack_blocked(state: ChessCoreState, attacker: ChessCorePiece, destination: Vector2i) -> bool:
	var defender := state.occupant(destination)
	return (
		defender != null
		and defender.type_id == &"rhetorician_king"
		and defender.color != attacker.color
		and maxi(absi(attacker.coordinate.x - destination.x), absi(attacker.coordinate.y - destination.y)) == 1
	)


static func _pawn_moves(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var direction := -1 if piece.color == "white" else 1
	var one := piece.coordinate + Vector2i(direction, 0)
	if _in_bounds(one) and state.occupant(one) == null:
		result.append(one)
		var two := piece.coordinate + Vector2i(direction * 2, 0)
		if not piece.has_moved and _in_bounds(two) and state.occupant(two) == null: result.append(two)
	for column_delta in [-1, 1]:
		var target := piece.coordinate + Vector2i(direction, column_delta)
		if not _in_bounds(target): continue
		var occupant := state.occupant(target)
		if occupant != null and occupant.color != piece.color:
			result.append(target)
		elif _en_passant_victim(state, piece, target) != null:
			result.append(target)
	return result


static func _bone_pawn_moves(state: ChessCoreState, piece: ChessCorePiece) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var direction := -1 if piece.color == "white" else 1
	var forward := piece.coordinate + Vector2i(direction, 0)
	if _in_bounds(forward) and state.occupant(forward) == null: result.append(forward)
	for column_delta in [-1, 1]:
		var target := piece.coordinate + Vector2i(direction, column_delta)
		var occupant := state.occupant(target) if _in_bounds(target) else null
		if occupant != null and occupant.color != piece.color: result.append(target)
	return result


static func _jump_moves(state: ChessCoreState, piece: ChessCorePiece, offsets: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in offsets:
		var target: Vector2i = piece.coordinate + offset
		if _in_bounds(target) and _available(state, target, piece.color): result.append(target)
	return result


static func _ray_moves(state: ChessCoreState, piece: ChessCorePiece, directions: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in directions:
		var target: Vector2i = piece.coordinate + direction
		while _in_bounds(target):
			var occupant := state.occupant(target)
			if occupant == null:
				result.append(target)
			elif occupant.color != piece.color:
				result.append(target)
				break
			else:
				break
			target += direction
	return result


static func _ray_is_clear(state: ChessCoreState, origin: Vector2i, target: Vector2i) -> bool:
	return _occupancy_ray_is_clear(state.occupancy, origin, target)


static func _occupancy_ray_is_clear(occupancy: Dictionary, origin: Vector2i, target: Vector2i) -> bool:
	var delta := target - origin
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var square := origin + step
	while square != target:
		if occupancy.get(square) != null: return false
		square += step
	return true


static func _can_castle(state: ChessCoreState, king: ChessCorePiece, target: Vector2i) -> bool:
	var row := 7 if king.color == "white" else 0
	if king.coordinate != Vector2i(row, 4) or target.x != row or target.y not in [2, 6] or state.occupant(target) != null:
		return false
	var rook_column := 0 if target.y == 2 else 7
	var rook := state.occupant(Vector2i(row, rook_column))
	if rook == null or rook.type_id != &"rook" or rook.color != king.color or rook.has_moved:
		return false
	for column in range(mini(4, rook_column) + 1, maxi(4, rook_column)):
		if state.occupant(Vector2i(row, column)) != null: return false
	return true


static func _en_passant_victim(state: ChessCoreState, pawn: ChessCorePiece, target: Vector2i) -> ChessCorePiece:
	if state.occupant(target) != null or absi(target.y - pawn.coordinate.y) != 1:
		return null
	var direction := -1 if pawn.color == "white" else 1
	if target.x != pawn.coordinate.x + direction or state.last_move.is_empty(): return null
	var previous_from: Vector2i = state.last_move.get("from", Vector2i.ZERO)
	var previous_to: Vector2i = state.last_move.get("to", Vector2i.ZERO)
	if absi(previous_to.x - previous_from.x) != 2 or previous_to != Vector2i(pawn.coordinate.x, target.y): return null
	var victim := state.occupant(previous_to)
	if victim == null or victim.type_id != &"pawn" or victim.color == pawn.color: return null
	if not String(state.last_move.get("piece_id", "")).is_empty() and victim.piece_id != state.last_move.get("piece_id", ""): return null
	return victim


static func _resolve_castle(state: ChessCoreState, king: ChessCorePiece, target: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var origin := king.coordinate
	var rook_from := Vector2i(origin.x, 7 if target.y == 6 else 0)
	var rook_to := Vector2i(origin.x, 5 if target.y == 6 else 3)
	var rook := state.occupant(rook_from)
	state.move_piece(king, target); king.has_moved = true
	state.move_piece(rook, rook_to); rook.has_moved = true
	_append_event(events, emit_events, &"pieces_castled", {"king_id": king.piece_id, "rook_id": rook.piece_id, "king_from": origin, "king_to": target, "rook_from": rook_from, "rook_to": rook_to})
	_append_event(events, emit_events, &"piece_landed", {"piece_id": rook.piece_id, "from": rook_from, "to": rook_to})
	_append_event(events, emit_events, &"piece_landed", {"piece_id": king.piece_id, "from": origin, "to": target})


static func _commit_capture(state: ChessCoreState, attacker: ChessCorePiece, defender: ChessCorePiece, target: Vector2i, captured_at: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var origin := attacker.coordinate
	_destroy_piece(state, defender, captured_at, events, emit_events, false)
	state.move_piece(attacker, target)
	attacker.has_moved = true
	_append_event(events, emit_events, &"piece_captured", {"attacker_id": attacker.piece_id, "defender_id": defender.piece_id, "from": origin, "to": target, "captured_at": captured_at})
	_append_event(events, emit_events, &"piece_destroyed", {"piece_id": defender.piece_id, "coordinate": captured_at})
	_append_event(events, emit_events, &"piece_landed", {"piece_id": attacker.piece_id, "from": origin, "to": target})
	_collect_archer_arrows(state, attacker, target, events, emit_events)
	if attacker.type_id == &"wraith_king" and state.piece_by_id(attacker.piece_id) != null:
		_add_random_cursed_mark(state, attacker, events, emit_events, &"king_capture")
		_wraith_on_landed(state, attacker, events, emit_events)


static func _add_random_cursed_mark(state: ChessCoreState, wraith: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool, spawn_reason: StringName, entity_id := "") -> void:
	if wraith == null or state.piece_by_id(wraith.piece_id) == null:
		return
	var candidates: Array[Vector2i] = []
	for row in range(state.board_size.x):
		for column in range(state.board_size.y):
			var coordinate := Vector2i(row, column)
			if not state.has_effect(&"cursed_mark", coordinate):
				candidates.append(coordinate)
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.state = int(state.random_states.get(
		WraithCoreRules.CURSE_MARK_RANDOM_STREAM,
		seeded_random_state(0)
	))
	var coordinate := candidates[rng.randi_range(0, candidates.size() - 1)]
	state.random_states[WraithCoreRules.CURSE_MARK_RANDOM_STREAM] = rng.state
	var effect := ChessCoreTileEffect.new()
	effect.effect_id = state.allocate_state_id("effect")
	effect.type_id = &"cursed_mark"
	effect.coordinate = coordinate
	effect.owner_color = wraith.color
	effect.source_piece_id = wraith.piece_id
	state.add_effect(effect)
	_append_event(events, emit_events, &"tile_effect_added", {
		"effect_id": effect.effect_id,
		"type_id": effect.type_id,
		"coordinate": coordinate,
		"owner_color": effect.owner_color,
		"source_piece_id": effect.source_piece_id,
		"spawn_reason": spawn_reason,
		"entity_id": entity_id,
	})


static func _wraith_on_landed(state: ChessCoreState, wraith: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if wraith == null or wraith.type_id != &"wraith_king" or not state.has_effect(&"cursed_mark", wraith.coordinate):
		return
	state.next_reaction_sequence += 1
	var reaction := ChessCoreReaction.new()
	reaction.calling_piece_id = wraith.piece_id
	reaction.action_type = &"lingering_malice"
	reaction.priority = 0
	reaction.sequence = state.next_reaction_sequence
	reaction.event_coordinate = wraith.coordinate
	state.reaction_queue.append(reaction)
	_append_event(events, emit_events, &"reaction_queued", {"piece_id": wraith.piece_id, "action_type": reaction.action_type, "event_coordinate": reaction.event_coordinate, "sequence": reaction.sequence})


static func _remove_cursed_mark(state: ChessCoreState, coordinate: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> bool:
	for effect in state.tile_effects.duplicate():
		if effect.type_id == &"cursed_mark" and effect.coordinate == coordinate:
			state.remove_effect(effect)
			_append_event(events, emit_events, &"tile_effect_removed", {"effect_id": effect.effect_id, "type_id": effect.type_id, "coordinate": coordinate, "source_piece_id": effect.source_piece_id})
			return true
	return false


static func _resolve_compel(state: ChessCoreState, rhetorician: ChessCorePiece, compelled: ChessCorePiece, destination: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if compelled == null or state.piece_by_id(compelled.piece_id) == null or not _in_bounds(destination) or destination == rhetorician.coordinate:
		return
	var origin := compelled.coordinate
	var occupant := state.occupant(destination)
	if occupant == null:
		state.move_piece(compelled, destination)
		compelled.has_moved = true
		_append_event(events, emit_events, &"piece_moved", {"piece_id": compelled.piece_id, "from": origin, "to": destination, "self_propelled": true})
		_append_event(events, emit_events, &"piece_landed", {"piece_id": compelled.piece_id, "from": origin, "to": destination, "self_propelled": true})
	else:
		_commit_capture(state, compelled, occupant, destination, destination, events, emit_events)
	if compelled.type_id == &"bone_pawn" and state.piece_by_id(compelled.piece_id) != null and _is_terminal_rank(compelled):
		_destroy_piece(state, compelled, compelled.coordinate, events, emit_events)


static func _resolve_charge(state: ChessCoreState, minotaur: ChessCorePiece, target_coordinate: Vector2i, target: ChessCorePiece, damage: int, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var origin := minotaur.coordinate
	if target == null:
		state.move_piece(minotaur, target_coordinate)
		minotaur.has_moved = true
		minotaur.stunned = true
		minotaur.stun_timer = MinotaurCoreRules.SELF_STUN_DURATION
		_append_event(events, emit_events, &"piece_moved", {"piece_id": minotaur.piece_id, "from": origin, "to": target_coordinate})
		_append_event(events, emit_events, &"piece_landed", {"piece_id": minotaur.piece_id, "from": origin, "to": target_coordinate})
		_append_event(events, emit_events, &"piece_stunned", {"piece_id": minotaur.piece_id, "duration": MinotaurCoreRules.SELF_STUN_DURATION})
		return
	if target.max_hp <= 1:
		_commit_capture(state, minotaur, target, target_coordinate, target_coordinate, events, emit_events)
		return
	var direction := Vector2i(signi(target_coordinate.x - origin.x), signi(target_coordinate.y - origin.y))
	var landing := target_coordinate - direction
	state.move_piece(minotaur, landing)
	minotaur.has_moved = true
	_append_event(events, emit_events, &"piece_moved", {"piece_id": minotaur.piece_id, "from": origin, "to": landing})
	_append_event(events, emit_events, &"piece_landed", {"piece_id": minotaur.piece_id, "from": origin, "to": landing})
	_deal_damage(state, target, damage, events, emit_events)


static func _deal_damage(state: ChessCoreState, target: ChessCorePiece, damage: int, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if target == null or damage <= 0 or state.piece_by_id(target.piece_id) == null:
		return
	if target.type_id in ArcherCoreRules.TYPES and ArcherCoreRules.is_drawing(target):
		damage *= 2
	target.current_hp -= damage
	_append_event(events, emit_events, &"piece_damaged", {"piece_id": target.piece_id, "amount": damage, "current_hp": target.current_hp, "max_hp": target.max_hp})
	if target.current_hp <= 0:
		_destroy_piece(state, target, target.coordinate, events, emit_events)
	elif target.type_id == &"minotaur_king" and not target.stunned and state.defeated_king_colors.is_empty():
		_queue_rage(state, target, events, emit_events)


static func _destroy_piece(state: ChessCoreState, piece: ChessCorePiece, coordinate: Vector2i, events: Array[ChessCoreEvent], emit_events: bool, append_destroy_event := true) -> void:
	if piece == null or state.piece_by_id(piece.piece_id) == null: return
	if piece.is_king() and piece.color not in state.defeated_king_colors:
		state.defeated_king_colors.append(piece.color)
	_queue_raise_dead(state, piece, coordinate, events, emit_events)
	if piece.type_id == &"wraith_king":
		for effect in state.tile_effects.duplicate():
			if effect.type_id == &"cursed_mark" and effect.source_piece_id == piece.piece_id:
				state.remove_effect(effect)
				_append_event(events, emit_events, &"tile_effect_removed", {
					"effect_id": effect.effect_id,
					"type_id": effect.type_id,
					"coordinate": effect.coordinate,
					"source_piece_id": effect.source_piece_id,
				})
	for entity in state.autonomous_entities.duplicate():
		if entity.source_piece_id != piece.piece_id and entity.target_piece_id != piece.piece_id: continue
		state.remove_entity(entity)
		_append_event(events, emit_events, &"autonomous_entity_removed", {
			"entity_id": entity.entity_id,
			"reason": &"source_destroyed" if entity.source_piece_id == piece.piece_id else &"target_destroyed",
		})
	state.remove_piece(piece)
	if append_destroy_event: _append_event(events, emit_events, &"piece_destroyed", {"piece_id": piece.piece_id, "coordinate": coordinate})


static func _queue_rage(state: ChessCoreState, minotaur: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	state.next_reaction_sequence += 1
	var reaction := ChessCoreReaction.new()
	reaction.calling_piece_id = minotaur.piece_id
	reaction.action_type = &"retaliating_rage"
	reaction.priority = 100
	reaction.sequence = state.next_reaction_sequence
	reaction.event_coordinate = minotaur.coordinate
	state.reaction_queue.append(reaction)
	_append_event(events, emit_events, &"reaction_queued", {"piece_id": minotaur.piece_id, "action_type": reaction.action_type, "event_coordinate": null, "sequence": reaction.sequence})


static func _queue_raise_dead(state: ChessCoreState, destroyed: ChessCorePiece, coordinate: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if destroyed.type_id not in [&"knight", &"bishop", &"rook", &"queen"] or not state.defeated_king_colors.is_empty(): return
	var owner := String(state.resolution_context.get("action_owner", state.current_turn))
	for candidate in state.pieces:
		if candidate.type_id != &"necromancer_king" or candidate.current_hp <= 0: continue
		state.next_reaction_sequence += 1
		var reaction := ChessCoreReaction.new()
		reaction.calling_piece_id = candidate.piece_id
		reaction.action_type = &"raise_dead"
		reaction.priority = 1 if candidate.color != owner else 0
		reaction.sequence = state.next_reaction_sequence
		reaction.event_coordinate = coordinate
		state.reaction_queue.append(reaction)
		_append_event(events, emit_events, &"reaction_queued", {"piece_id": candidate.piece_id, "action_type": reaction.action_type, "event_coordinate": coordinate, "sequence": reaction.sequence})


static func _summon_bone_pawn(state: ChessCoreState, color: String, target: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> ChessCorePiece:
	if not _in_bounds(target) or state.occupant(target) != null: return null
	var pawn := ChessCorePiece.new()
	pawn.type_id = &"bone_pawn"
	pawn.piece_id = state.allocate_piece_id()
	pawn.color = color
	pawn.coordinate = target
	state.add_piece(pawn)
	_append_event(events, emit_events, &"piece_summoned", {"piece_id": pawn.piece_id, "piece_type": pawn.type_id, "color": color, "coordinate": target})
	if _is_terminal_rank(pawn): _destroy_piece(state, pawn, target, events, emit_events)
	return pawn


static func _is_terminal_rank(piece: ChessCorePiece) -> bool:
	return piece.coordinate.x == (0 if piece.color == "white" else 7)


static func _complete_or_pause(state: ChessCoreState, result: ChessCoreStepResult, emit_events: bool) -> void:
	if not _prepare_next_reaction(state, result.events, emit_events):
		if state.battle_over:
			# The model consumes the forced Socratic turn after its selected move
			# returns, even when that move ends the battle.
			if not state.socratic_resolution_color.is_empty():
				_complete_socratic_resolution(state, result.events, emit_events)
			state.resolution_context.clear()
			result.status = ChessCoreStepResult.Status.COMPLETED
			return
		_finish_action(state, result.events, emit_events)
		if state.pending_choice != null:
			result.choice = state.pending_choice.copy()
			result.status = ChessCoreStepResult.Status.PENDING_CHOICE
			return
		if _prepare_next_reaction(state, result.events, emit_events):
			result.choice = state.pending_choice.copy()
			result.status = ChessCoreStepResult.Status.PENDING_CHOICE
			return
		# Action completion itself can create an automatic reaction (for example a
		# due Wraith damaging a Minotaur). Once that queue drains, resume the
		# interrupted completion lifecycle instead of clearing its turn context.
		if bool(state.resolution_context.get("completion_interrupted", false)):
			state.resolution_context.erase("completion_interrupted")
			_complete_or_pause(state, result, emit_events)
			return
		if not state.socratic_resolution_color.is_empty():
			_complete_socratic_resolution(state, result.events, emit_events)
			state.resolution_context.clear()
			result.status = ChessCoreStepResult.Status.COMPLETED
			return
		if bool(state.resolution_context.get("socratic_ready", false)):
			var nested := _begin_socratic_resolution(state, emit_events)
			result.events.append_array(nested.events)
			result.state = nested.state
			result.choice = nested.choice
			result.status = nested.status
			return
		state.resolution_context.clear()
		result.status = ChessCoreStepResult.Status.COMPLETED
		return
	result.choice = state.pending_choice.copy()
	result.status = ChessCoreStepResult.Status.PENDING_CHOICE


static func _prepare_next_reaction(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events: bool) -> bool:
	while not state.reaction_queue.is_empty():
		state.reaction_queue.sort_custom(func(a: ChessCoreReaction, b: ChessCoreReaction):
			return a.sequence < b.sequence if a.priority == b.priority else a.priority > b.priority
		)
		var reaction: ChessCoreReaction = state.reaction_queue.pop_front()
		var caller := state.piece_by_id(reaction.calling_piece_id)
		if caller == null or caller.current_hp <= 0:
			_append_event(events, emit_events, &"reaction_finished", {"piece_id": reaction.calling_piece_id, "action_type": reaction.action_type, "event_coordinate": reaction.event_coordinate, "sequence": reaction.sequence, "resolved": false})
			continue
		if reaction.action_type == &"retaliating_rage":
			_resolve_rage(state, caller, reaction, events, emit_events)
			if not state.defeated_king_colors.is_empty():
				_complete_battle(state, events, emit_events)
				return false
			continue
		if reaction.action_type == &"lingering_malice":
			var lingering_targets := _lingering_malice_targets(state, caller, reaction.event_coordinate)
			if lingering_targets.is_empty():
				_append_event(events, emit_events, &"reaction_finished", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "event_coordinate": reaction.event_coordinate, "sequence": reaction.sequence, "resolved": false})
				continue
			var lingering_choice := ChessCoreChoice.new()
			lingering_choice.kind = &"lingering_malice"
			lingering_choice.piece_id = caller.piece_id
			lingering_choice.action_type = reaction.action_type
			lingering_choice.sequence = reaction.sequence
			lingering_choice.event_coordinate = reaction.event_coordinate
			lingering_choice.options.assign(lingering_targets)
			state.pending_choice = lingering_choice
			_append_event(events, emit_events, &"reaction_selection_preparing", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "targets": lingering_targets.duplicate(), "sequence": reaction.sequence})
			_append_event(events, emit_events, &"reaction_selection_requested", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "targets": lingering_targets.duplicate(), "sequence": reaction.sequence})
			return true
		if reaction.action_type != &"raise_dead":
			_append_event(events, emit_events, &"reaction_finished", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "event_coordinate": reaction.event_coordinate, "sequence": reaction.sequence, "resolved": false})
			continue
		var targets := _raise_dead_targets(state, reaction.event_coordinate)
		if targets.is_empty():
			_append_event(events, emit_events, &"reaction_finished", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "event_coordinate": reaction.event_coordinate, "sequence": reaction.sequence, "resolved": false})
			continue
		var choice := ChessCoreChoice.new()
		choice.kind = &"raise_dead"
		choice.piece_id = caller.piece_id
		choice.action_type = reaction.action_type
		choice.sequence = reaction.sequence
		choice.event_coordinate = reaction.event_coordinate
		choice.options.assign(targets)
		state.pending_choice = choice
		_append_event(events, emit_events, &"reaction_selection_preparing", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "targets": targets.duplicate(), "sequence": reaction.sequence})
		_append_event(events, emit_events, &"reaction_selection_requested", {"piece_id": caller.piece_id, "action_type": reaction.action_type, "targets": targets.duplicate(), "sequence": reaction.sequence})
		return true
	return false


static func _lingering_malice_targets(state: ChessCoreState, wraith: ChessCorePiece, event_coordinate: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if wraith == null or wraith.type_id != &"wraith_king" or wraith.coordinate != event_coordinate or not state.has_effect(&"cursed_mark", event_coordinate):
		return result
	result.append(wraith.coordinate)
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		var target := wraith.coordinate + offset
		var occupant := state.occupant(target) if _in_bounds(target) else null
		if _in_bounds(target) and (occupant == null or occupant.color != wraith.color): result.append(target)
	return result


static func _resolve_lingering_malice_choice(source: ChessCoreState, option, emit_events: bool) -> ChessCoreStepResult:
	if not option is Vector2i: return ChessCoreStepResult.rejected(source, "Lingering Malice requires a coordinate.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	var choice := state.pending_choice
	var wraith := state.piece_by_id(choice.piece_id)
	if wraith == null or wraith.type_id != &"wraith_king" or option not in _lingering_malice_targets(state, wraith, choice.event_coordinate):
		return ChessCoreStepResult.rejected(source, "The Lingering Malice choice is no longer legal.")
	state.pending_choice = null
	_append_event(result.events, emit_events, &"reaction_selection_committed", {"piece_id": wraith.piece_id, "action_type": choice.action_type, "target": option, "sequence": choice.sequence})
	if option != wraith.coordinate:
		_remove_cursed_mark(state, wraith.coordinate, result.events, emit_events)
		var origin := wraith.coordinate
		var occupant := state.occupant(option)
		if occupant == null:
			state.move_piece(wraith, option)
			wraith.has_moved = true
			_append_event(result.events, emit_events, &"piece_moved", {"piece_id": wraith.piece_id, "from": origin, "to": option})
			_append_event(result.events, emit_events, &"piece_landed", {"piece_id": wraith.piece_id, "from": origin, "to": option})
			_wraith_on_landed(state, wraith, result.events, emit_events)
		elif occupant.current_hp <= wraith.attack_power:
			_commit_capture(state, wraith, occupant, option, option, result.events, emit_events)
		else:
			_deal_damage(state, occupant, wraith.attack_power, result.events, emit_events)
	_append_event(result.events, emit_events, &"reaction_selection_resolved", {"piece_id": wraith.piece_id, "action_type": choice.action_type, "target": option, "sequence": choice.sequence})
	_append_event(result.events, emit_events, &"reaction_finished", {"piece_id": wraith.piece_id, "action_type": choice.action_type, "event_coordinate": choice.event_coordinate, "sequence": choice.sequence, "resolved": true})
	if not state.defeated_king_colors.is_empty():
		_complete_battle(state, result.events, emit_events)
		result.status = ChessCoreStepResult.Status.COMPLETED
	else:
		_complete_or_pause(state, result, emit_events)
	return result


static func _resolve_rage(state: ChessCoreState, minotaur: ChessCorePiece, reaction: ChessCoreReaction, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if minotaur.type_id != &"minotaur_king" or minotaur.stunned:
		_append_event(events, emit_events, &"reaction_finished", {"piece_id": minotaur.piece_id, "action_type": reaction.action_type, "event_coordinate": null, "sequence": reaction.sequence, "resolved": false})
		return
	_append_event(events, emit_events, &"automatic_reaction_started", {"piece_id": minotaur.piece_id, "action_type": reaction.action_type, "sequence": reaction.sequence})
	var affected: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		var coordinate: Vector2i = minotaur.coordinate + offset
		if not _in_bounds(coordinate):
			continue
		affected.append(coordinate)
		var target := state.occupant(coordinate)
		if target != null:
			_deal_damage(state, target, MinotaurCoreRules.RAGE_DAMAGE, events, emit_events)
	_append_event(events, emit_events, &"automatic_reaction_resolved", {"piece_id": minotaur.piece_id, "action_type": reaction.action_type, "affected_coordinates": affected, "sequence": reaction.sequence})
	_append_event(events, emit_events, &"reaction_finished", {"piece_id": minotaur.piece_id, "action_type": reaction.action_type, "event_coordinate": null, "sequence": reaction.sequence, "resolved": true})


static func _resolve_raise_dead_choice(source: ChessCoreState, option, emit_events: bool) -> ChessCoreStepResult:
	if not option is Vector2i: return ChessCoreStepResult.rejected(source, "Raise Dead requires a coordinate.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	var choice := state.pending_choice
	var caller := state.piece_by_id(choice.piece_id)
	if caller == null or caller.type_id != &"necromancer_king": return ChessCoreStepResult.rejected(source, "The reacting Necromancer is no longer active.")
	state.pending_choice = null
	_append_event(result.events, emit_events, &"reaction_selection_committed", {"piece_id": caller.piece_id, "action_type": choice.action_type, "target": option, "sequence": choice.sequence})
	_summon_bone_pawn(state, caller.color, option, result.events, emit_events)
	_append_event(result.events, emit_events, &"reaction_selection_resolved", {"piece_id": caller.piece_id, "action_type": choice.action_type, "target": option, "sequence": choice.sequence})
	_append_event(result.events, emit_events, &"reaction_finished", {"piece_id": caller.piece_id, "action_type": choice.action_type, "event_coordinate": choice.event_coordinate, "sequence": choice.sequence, "resolved": true})
	if not state.defeated_king_colors.is_empty():
		_complete_battle(state, result.events, emit_events)
		result.status = ChessCoreStepResult.Status.COMPLETED
	else: _complete_or_pause(state, result, emit_events)
	return result


static func _resolve_movement_type_grant_choice(source: ChessCoreState, option, emit_events: bool) -> ChessCoreStepResult:
	if not option is StringName and not option is String:
		return ChessCoreStepResult.rejected(source, "A movement grant requires a movement type.")
	var movement_type := StringName(option)
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	var choice := state.pending_choice
	var quarterly := state.piece_by_id(choice.piece_id)
	var recipient := state.piece_by_id(choice.target_piece_id)
	if quarterly == null or quarterly.type_id != &"quarterly_initiative_king" or recipient == null or recipient.color != quarterly.color or recipient == quarterly:
		return ChessCoreStepResult.rejected(source, "The Quarterly grant participants are no longer active.")
	state.pending_choice = null
	if movement_type not in recipient.granted_movement_types:
		recipient.granted_movement_types.append(movement_type)
	_append_event(result.events, emit_events, &"choice_resolved", {"kind": &"movement_type_grant", "piece_id": quarterly.piece_id, "target_piece_id": recipient.piece_id, "option": movement_type})
	_append_event(result.events, emit_events, &"movement_type_granted", {"piece_id": recipient.piece_id, "movement_type": movement_type})
	_schedule_cooldown(state, quarterly, result.events, emit_events)
	_complete_or_pause(state, result, emit_events)
	return result


static func _raise_dead_targets(state: ChessCoreState, death_square: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		var target: Vector2i = death_square + offset
		if _in_bounds(target) and state.occupant(target) == null: result.append(target)
	if _in_bounds(death_square) and state.occupant(death_square) == null: result.append(death_square)
	return result


static func _finish_action(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var completed_color := String(state.resolution_context.get("action_owner", state.current_turn))
	if not bool(state.resolution_context.get("wraith_phase_resolved", false)):
		state.resolution_context["wraith_phase_resolved"] = true
		_run_wraith_phase(state, completed_color, events, emit_events)
		if not state.defeated_king_colors.is_empty():
			_complete_battle(state, events, emit_events)
			return
		if not state.reaction_queue.is_empty():
			state.resolution_context["completion_interrupted"] = true
			return
	if not bool(state.resolution_context.get("turn_switched", false)):
		_advance_archer_charge_after_action(state, completed_color, events, emit_events)
		_switch_turn(state, events, emit_events)
		state.resolution_context["turn_switched"] = true
		if _resolve_archer_turn_entry(state, state.current_turn, events, emit_events):
			if not state.defeated_king_colors.is_empty():
				_complete_battle(state, events, emit_events)
				return
			_switch_turn(state, events, emit_events)
		_resolve_arc_mortars_at_turn_start(state, state.current_turn, events, emit_events)
		if not state.defeated_king_colors.is_empty():
			_complete_battle(state, events, emit_events)
			return
		if not state.reaction_queue.is_empty():
			state.resolution_context["completion_interrupted"] = true
			return
	if state.socratic_resolution_color.is_empty() and int(state.socratic_turns_by_color.get(state.current_turn, 0)) > 0:
		state.resolution_context["socratic_ready"] = true
		return
	_resolve_forced_passes(state, events, emit_events)
	if not state.battle_over:
		_append_event(events, emit_events, &"action_finished", {"color": completed_color})


static func _switch_turn(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events := true) -> void:
	state.current_turn = "black" if state.current_turn == "white" else "white"
	if state.current_turn == "white": state.global_turn_number += 1
	_append_event(events, emit_events, &"turn_changed", {"color": state.current_turn, "global_turn_number": state.global_turn_number})
	for piece in state.pieces:
		if piece.color != state.current_turn:
			continue
		if piece.stunned and piece.stun_timer > 0:
			piece.stun_timer -= 1
			if piece.stun_timer == 0: piece.stunned = false
		if ChessCoreKingRules.for_type(piece.type_id) != null or (piece.is_king() and piece.initial_cooldown_turn_pending):
			_advance_cooldown(state, piece, events, emit_events)
	_apply_lunacy_turn_start(state, state.current_turn, events, emit_events)


static func _advance_archer_charge_after_action(state: ChessCoreState, completed_color: String, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	for piece in state.pieces:
		if piece.color != completed_color or not ArcherCoreRules.uses_charge(piece): continue
		var level := ArcherCoreRules.charge_level(piece)
		if level <= 0 or level >= 3: return
		if bool(state.resolution_context.get("archer_charge_started", false)) or String(state.resolution_context.get("primary_piece_id", "")) == piece.piece_id: return
		piece.custom_state["charge_level"] = level + 1
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": piece.piece_id, "state": &"drawing", "message": "Charge Level MAX" if level + 1 == 3 else "Charge Level 2"})
		return


static func _resolve_archer_turn_entry(state: ChessCoreState, color: String, events: Array[ChessCoreEvent], emit_events: bool) -> bool:
	var archer: ChessCorePiece
	for piece in state.pieces:
		if piece.color == color and piece.type_id in ArcherCoreRules.TYPES:
			archer = piece
			break
	if archer == null: return false
	if ArcherCoreRules.is_suppressed(state, archer) and ArcherCoreRules.is_drawing(archer):
		_cancel_archer_draw(archer, events, emit_events, "Draw Cancelled — Suppressed")
		return false
	var target_coordinate := ArcherCoreRules.draw_target(archer)
	if target_coordinate == Vector2i(-1, -1):
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"drawing" if ArcherCoreRules.charge_level(archer) > 0 else &"idle", "message": ""})
		return false
	var target_id := String(archer.custom_state.get("draw_target_piece_id", ""))
	var candidate := state.piece_by_id(target_id) if not target_id.is_empty() else state.occupant(target_coordinate)
	var valid := candidate != null and candidate.color != archer.color and ArcherCoreRules.can_ranged_attack(state, archer, candidate.coordinate)
	if not valid:
		_cancel_archer_draw(archer, events, emit_events, "Shot Cancelled")
		return false
	archer.custom_state["draw_target"] = [candidate.coordinate.x, candidate.coordinate.y]
	if ArcherCoreRules.uses_draw(archer) and int(archer.custom_state.get("draw_turns_waited", 0)) < 1:
		archer.custom_state["draw_turns_waited"] = int(archer.custom_state.get("draw_turns_waited", 0)) + 1
		_append_event(events, emit_events, &"archer_state_changed", {"piece_id": archer.piece_id, "state": &"drawing", "message": "Drawing Bow"})
		return false
	_cancel_archer_draw(archer, events, emit_events, "Loose!")
	_append_event(events, emit_events, &"archer_attack_committed", {"attacker_id": archer.piece_id, "defender_id": candidate.piece_id, "from": archer.coordinate, "to": candidate.coordinate})
	if ArcherCoreRules.uses_quiver(archer):
		archer.custom_state["arrows"] = maxi(0, ArcherCoreRules.arrows(archer) - 1)
		_drop_archer_arrow(state, archer, candidate.coordinate, events, emit_events)
	_deal_damage(state, candidate, 1, events, emit_events)
	return true


static func _apply_lunacy_turn_start(state: ChessCoreState, color: String, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var king: ChessCorePiece
	for piece in state.pieces:
		if piece.color == color and piece.type_id == &"rhetorician_king":
			king = piece
			break
	if king == null or not _rhetorician_is_threatened(state, king):
		return
	_add_lunacy(state, color, 1, events, emit_events)


static func _add_lunacy(state: ChessCoreState, color: String, amount: int, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if color not in ["white", "black"] or amount <= 0 or int(state.socratic_turns_by_color.get(color, 0)) > 0:
		return
	var value := int(state.lunacy_by_color.get(color, 0)) + amount
	state.lunacy_by_color[color] = value
	if value >= RhetoricianCoreRules.LUNACY_THRESHOLD:
		state.socratic_turns_by_color[color] = RhetoricianCoreRules.SOCRATIC_TURN_COUNT
	_append_event(events, emit_events, &"lunacy_changed", {"color": color, "value": value, "socratic_turns_remaining": int(state.socratic_turns_by_color[color])})


static func _rhetorician_is_threatened(state: ChessCoreState, king: ChessCorePiece) -> bool:
	for enemy in state.pieces:
		if enemy.color == king.color or enemy.stunned or enemy.current_hp <= 0:
			continue
		# Match ChessBoardModel: native movement geometry counts even when the
		# adjacent-attack passive blocks the command. Granted movement and active
		# abilities do not contribute to Lunacy.
		if _movement_type_attacks(enemy.type_id, enemy.color, enemy.coordinate, king.coordinate, state.occupancy):
			return true
	return false


static func _begin_socratic_resolution(source: ChessCoreState, emit_events: bool) -> ChessCoreStepResult:
	var prepared := source.copy()
	prepared.resolution_context.erase("socratic_ready")
	var forced_color := prepared.current_turn
	var moves: Array[ChessCoreAction] = []
	for action in legal_actions(prepared, forced_color):
		if action.kind == ChessCoreAction.Kind.MOVE:
			moves.append(action)
	var result := ChessCoreStepResult.new()
	if moves.is_empty():
		result.state = prepared
		result.status = ChessCoreStepResult.Status.COMPLETED
		prepared.socratic_resolution_color = forced_color
		_append_event(result.events, emit_events, &"socratic_turn_skipped", {"color": forced_color})
		_switch_turn(prepared, result.events, emit_events)
		_complete_socratic_resolution(prepared, result.events, emit_events)
		_resolve_forced_passes(prepared, result.events, emit_events)
		if bool(prepared.resolution_context.get("socratic_ready", false)):
			var continued := _begin_socratic_resolution(prepared, emit_events)
			result.events.append_array(continued.events)
			result.state = continued.state
			result.choice = continued.choice
			result.status = continued.status
		else:
			prepared.resolution_context.clear()
		return result
	var rng := RandomNumberGenerator.new()
	rng.state = int(prepared.random_states.get(&"lunacy", 0))
	var chosen: ChessCoreAction = moves[rng.randi_range(0, moves.size() - 1)]
	prepared.random_states[&"lunacy"] = rng.state
	prepared.socratic_resolution_color = forced_color
	prepared.resolution_context.clear()
	var selected_event := _event(&"socratic_action_selected", {
		"color": forced_color, "piece_id": chosen.piece_id, "from": chosen.from,
		"target": chosen.target, "path": chosen.path.duplicate(),
	})
	var nested := resolve_action(prepared, chosen, emit_events)
	if emit_events:
		nested.events.push_front(selected_event)
	return nested


static func _complete_socratic_resolution(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var color := state.socratic_resolution_color
	if color.is_empty():
		return
	state.socratic_resolution_color = ""
	var remaining := maxi(0, int(state.socratic_turns_by_color.get(color, 0)) - 1)
	state.socratic_turns_by_color[color] = remaining
	if remaining == 0:
		state.lunacy_by_color[color] = 0
	_append_event(events, emit_events, &"lunacy_changed", {"color": color, "value": int(state.lunacy_by_color[color]), "socratic_turns_remaining": remaining})


static func _ability_ready(state: ChessCoreState, piece: ChessCorePiece) -> bool:
	return piece != null and ChessCoreKingRules.for_type(piece.type_id) != null and (state.active_ability_cooldowns_disabled or (piece.current_cooldown == 0 and not piece.cooldown_reset_pending))


static func _schedule_cooldown(state: ChessCoreState, piece: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if state.active_ability_cooldowns_disabled:
		piece.current_cooldown = 0
		piece.cooldown_reset_pending = false
		_append_event(events, emit_events, &"cooldown_ready", {"piece_id": piece.piece_id})
		return
	piece.current_cooldown = 0
	piece.cooldown_reset_pending = ChessCoreKingRules.base_cooldown(piece.type_id) > 0
	_append_event(events, emit_events, &"cooldown_scheduled" if piece.cooldown_reset_pending else &"cooldown_ready", {"piece_id": piece.piece_id})


static func _advance_cooldown(state: ChessCoreState, piece: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if not piece.is_king():
		return
	if state.active_ability_cooldowns_disabled:
		piece.current_cooldown = 0
		piece.cooldown_reset_pending = false
		piece.initial_cooldown_turn_pending = false
		_append_event(events, emit_events, &"cooldown_ready", {"piece_id": piece.piece_id})
		return
	if piece.cooldown_reset_pending:
		piece.initial_cooldown_turn_pending = false
		piece.cooldown_reset_pending = false
		piece.current_cooldown = int(piece.custom_state.get("scheduled_arc_cooldown", ChessCoreKingRules.base_cooldown(piece.type_id))) if piece.type_id == &"cannon_king" else ChessCoreKingRules.base_cooldown(piece.type_id)
		_append_event(events, emit_events, &"cooldown_changed", {"piece_id": piece.piece_id, "value": piece.current_cooldown})
		return
	if piece.initial_cooldown_turn_pending:
		piece.initial_cooldown_turn_pending = false
		return
	if ChessCoreKingRules.for_type(piece.type_id) == null:
		return
	if piece.current_cooldown > 0:
		piece.current_cooldown -= 1
		var event_kind := &"cooldown_changed" if piece.current_cooldown > 0 else &"cooldown_ready"
		_append_event(events, emit_events, event_kind, {"piece_id": piece.piece_id, "value": piece.current_cooldown})


static func _resolve_forced_passes(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events := true) -> void:
	while not state.battle_over and legal_actions(state, state.current_turn).is_empty():
		var created_turn_entry_context := not state.resolution_context.has("action_owner")
		if created_turn_entry_context:
			state.resolution_context = {"action_owner": state.current_turn}
		state.consecutive_forced_passes += 1
		_append_event(events, emit_events, &"turn_passed", {"color": state.current_turn, "count": state.consecutive_forced_passes})
		if state.consecutive_forced_passes >= MAX_CONSECUTIVE_FORCED_PASSES:
			state.battle_over = true
			state.battle_result = "draw"
			_append_event(events, emit_events, &"battle_finished", {"result": "draw"})
			return
		state.resolution_context = {"action_owner": state.current_turn, "wraith_bonus_used": false, "wraith_phase_resolved": true}
		_run_wraith_phase(state, state.current_turn, events, emit_events)
		if not state.defeated_king_colors.is_empty():
			_complete_battle(state, events, emit_events)
			return
		if _prepare_next_reaction(state, events, emit_events): return
		_switch_turn(state, events, emit_events)
		if created_turn_entry_context: state.resolution_context["turn_switched"] = true
		_resolve_arc_mortars_at_turn_start(state, state.current_turn, events, emit_events)
		if not state.defeated_king_colors.is_empty():
			_complete_battle(state, events, emit_events)
			return
		if _prepare_next_reaction(state, events, emit_events): return
		if state.socratic_resolution_color.is_empty() and int(state.socratic_turns_by_color.get(state.current_turn, 0)) > 0:
			state.resolution_context["socratic_ready"] = true
			return
		if created_turn_entry_context: state.resolution_context.clear()
	state.consecutive_forced_passes = 0


static func _complete_battle(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	state.battle_over = true
	state.pending_choice = null
	state.reaction_queue.clear()
	state.resolution_context.clear()
	var white_defeated := "white" in state.defeated_king_colors
	var black_defeated := "black" in state.defeated_king_colors
	state.battle_result = "draw" if white_defeated and black_defeated else ("black" if white_defeated else "white")
	_append_event(events, emit_events, &"battle_finished", {"result": state.battle_result})


static func _launch_arc_mortar(state: ChessCoreState, cannon: ChessCorePiece, anchor: Vector2i, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var has_enemy := false
	for coordinate in CannonCoreRules.area(anchor):
		var occupant := state.occupant(coordinate)
		if occupant != null and occupant.color != cannon.color:
			has_enemy = true
			break
	cannon.custom_state["scheduled_arc_cooldown"] = CannonCoreRules.BASE_COOLDOWN if has_enemy else CannonCoreRules.BASE_COOLDOWN - 1
	var entity := ChessCoreAutonomousEntity.new()
	entity.entity_id = state.allocate_state_id("entity")
	entity.type_id = &"arc_mortar"
	entity.coordinate = anchor
	entity.owner_color = cannon.color
	entity.custom_state["landing_turn"] = state.global_turn_number + CannonCoreRules.DELAY_ROUNDS
	state.add_entity(entity)
	_append_event(events, emit_events, &"autonomous_entity_added", {"entity_id": entity.entity_id, "type_id": entity.type_id, "coordinate": anchor, "owner_color": entity.owner_color, "landing_turn": entity.custom_state.landing_turn})


static func _summon_wraith(state: ChessCoreState, source: ChessCorePiece, target: ChessCorePiece, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	if source == null or target == null or source.color == target.color: return
	var owned := WraithCoreRules.entities_from_source(state, source.piece_id)
	var replacement: ChessCoreAutonomousEntity = owned[0] if owned.size() >= WraithCoreRules.MAX_ACTIVE_WRAITHS else null
	for existing in owned:
		if existing.target_piece_id == target.piece_id and existing != replacement: return
	if replacement != null:
		state.remove_entity(replacement)
		_append_event(events, emit_events, &"autonomous_entity_removed", {"entity_id": replacement.entity_id, "reason": &"replaced"})
	var entity := ChessCoreAutonomousEntity.new()
	entity.entity_id = state.allocate_state_id("entity")
	entity.type_id = &"wraith"
	entity.coordinate = source.coordinate
	entity.owner_color = source.color
	entity.source_piece_id = source.piece_id
	entity.target_piece_id = target.piece_id
	entity.custom_state["next_move_turn"] = state.global_turn_number + WraithCoreRules.MOVE_INTERVAL_ROUNDS
	state.add_entity(entity)
	_append_event(events, emit_events, &"autonomous_entity_added", {
		"entity_id": entity.entity_id, "type_id": entity.type_id, "coordinate": entity.coordinate,
		"owner_color": entity.owner_color, "source_piece_id": entity.source_piece_id,
		"target_piece_id": entity.target_piece_id, "next_move_turn": entity.custom_state.next_move_turn,
	})


static func _run_wraith_phase(state: ChessCoreState, owner_color: String, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	for entity in state.autonomous_entities.duplicate():
		if entity.type_id != &"wraith" or entity.owner_color != owner_color or entity not in state.autonomous_entities: continue
		var next_move_turn := int(entity.custom_state.get("next_move_turn", 0))
		if next_move_turn <= 0:
			entity.custom_state["next_move_turn"] = state.global_turn_number + WraithCoreRules.MOVE_INTERVAL_ROUNDS
			continue
		if state.global_turn_number < next_move_turn: continue
		entity.custom_state["next_move_turn"] = state.global_turn_number + WraithCoreRules.MOVE_INTERVAL_ROUNDS
		var source := state.piece_by_id(entity.source_piece_id)
		var target := state.piece_by_id(entity.target_piece_id)
		if source == null or target == null or source.current_hp <= 0 or target.current_hp <= 0:
			state.remove_entity(entity)
			_append_event(events, emit_events, &"autonomous_entity_removed", {"entity_id": entity.entity_id, "reason": &"invalid_target"})
			continue
		while entity in state.autonomous_entities:
			var from: Vector2i = entity.coordinate
			var delta: Vector2i = target.coordinate - entity.coordinate
			var destination: Vector2i = entity.coordinate + Vector2i(signi(delta.x), signi(delta.y))
			entity.coordinate = destination
			_append_event(events, emit_events, &"autonomous_entity_moved", {"entity_id": entity.entity_id, "from": from, "to": destination})
			if destination == target.coordinate and state.piece_by_id(target.piece_id) != null:
				_deal_damage(state, target, WraithCoreRules.DAMAGE, events, emit_events)
				var captured := state.piece_by_id(target.piece_id) == null
				if entity in state.autonomous_entities:
					state.remove_entity(entity)
					_append_event(events, emit_events, &"autonomous_entity_removed", {"entity_id": entity.entity_id, "reason": &"reached_target"})
				if captured:
					_add_random_cursed_mark(state, source, events, emit_events, &"wraith_projectile_capture", entity.entity_id)
				break
			if not _remove_cursed_mark(state, destination, events, emit_events):
				break
		if not state.defeated_king_colors.is_empty(): return


static func _resolve_arc_mortars_at_turn_start(state: ChessCoreState, color: String, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	for entity in state.autonomous_entities.duplicate():
		if entity.type_id != &"arc_mortar" or entity.owner_color != color: continue
		var landing_turn := int(entity.custom_state.get("landing_turn", 0))
		if landing_turn <= 0:
			entity.custom_state["landing_turn"] = state.global_turn_number + CannonCoreRules.DELAY_ROUNDS
			continue
		if state.global_turn_number < landing_turn: continue
		var area := CannonCoreRules.area(entity.coordinate)
		_append_event(events, emit_events, &"arc_mortar_impact", {"entity_id": entity.entity_id, "affected_coordinates": area.duplicate()})
		for coordinate in area:
			var target := state.occupant(coordinate)
			if target != null: _deal_damage(state, target, CannonCoreRules.DAMAGE, events, emit_events)
		state.remove_entity(entity)
		_append_event(events, emit_events, &"autonomous_entity_removed", {"entity_id": entity.entity_id, "reason": &"impact"})


static func _append_event(events: Array[ChessCoreEvent], enabled: bool, kind: StringName, data: Dictionary) -> void:
	if enabled: events.append(_event(kind, data))


static func _available(state: ChessCoreState, target: Vector2i, color: String) -> bool:
	var occupant := state.occupant(target)
	return occupant == null or occupant.color != color


static func _in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < 8 and coordinate.y < 8


static func _reserve_id(state: ChessCoreState, id: String) -> void:
	var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
	if suffix.is_valid_int(): state.next_state_id = maxi(state.next_state_id, suffix.to_int() + 1)


static func _event(kind: StringName, data: Dictionary) -> ChessCoreEvent:
	return ChessCoreEvent.make(kind, data)
