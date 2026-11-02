extends RefCounted
class_name ClassicChessCore

const SUPPORTED_TYPES: Array[StringName] = [&"pawn", &"bone_pawn", &"knight", &"bishop", &"rook", &"queen", &"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king"]
const PROMOTION_OPTIONS: Array[StringName] = [&"queen", &"rook", &"bishop", &"knight"]
const MAX_CONSECUTIVE_FORCED_PASSES := 6


static func import_position(position: ChessPosition) -> Dictionary:
	if position == null:
		return {"ok": false, "error": "Position is null."}
	if position.board_size != Vector2i(8, 8) or position.board_type != &"default":
		return {"ok": false, "error": "Only the default 8x8 board is supported."}
	if not position.tile_effects.is_empty() or not position.autonomous_entities.is_empty():
		return {"ok": false, "error": "Tile effects and autonomous entities are outside the Classic slice."}
	if int(position.lunacy_by_color.get("white", 0)) != 0 or int(position.lunacy_by_color.get("black", 0)) != 0 or int(position.socratic_turns_by_color.get("white", 0)) != 0 or int(position.socratic_turns_by_color.get("black", 0)) != 0:
		return {"ok": false, "error": "Rhetorician state is outside the Classic slice."}
	var state := ChessCoreState.new()
	state.board_size = position.board_size
	state.board_type = position.board_type
	state.current_turn = position.current_turn
	state.battle_over = position.battle_over
	state.battle_result = position.battle_result
	state.defeated_king_colors.assign(position.defeated_king_colors)
	state.random_states = position.random_states.duplicate(true)
	state.global_turn_number = position.global_turn_number
	state.active_ability_cooldowns_disabled = position.active_ability_cooldowns_disabled
	var occupied := {}
	for source in position.pieces:
		var type_id := ChessPieceCatalog.normalize_type_id(source.type_id)
		if type_id not in SUPPORTED_TYPES:
			return {"ok": false, "error": "Unsupported Classic piece type: %s" % source.type_id}
		if not source.granted_movement_types.is_empty() or not source.custom_state.is_empty():
			return {"ok": false, "error": "RPG piece modifiers are outside the Classic slice."}
		if not ChessCoreKingRules.is_supported_king(type_id) and (source.current_cooldown != 0 or source.cooldown_reset_pending or source.initial_cooldown_turn_pending):
			return {"ok": false, "error": "Active-ability cooldown state is outside the Classic slice."}
		if source.coordinate.x < 0 or source.coordinate.y < 0 or source.coordinate.x >= 8 or source.coordinate.y >= 8 or occupied.has(source.coordinate):
			return {"ok": false, "error": "Piece coordinates are invalid or overlapping."}
		var piece := ChessCorePiece.from_piece_state(source)
		if piece.piece_id.is_empty(): piece.piece_id = state.allocate_piece_id()
		_reserve_id(state, piece.piece_id)
		state.add_piece(piece)
		occupied[piece.coordinate] = true
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
	result.global_turn_number = state.global_turn_number
	result.active_ability_cooldowns_disabled = state.active_ability_cooldowns_disabled
	for piece in state.pieces: result.pieces.append(piece.to_piece_state())
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
	var ordered := state.pieces.duplicate()
	ordered.sort_custom(func(a: ChessCorePiece, b: ChessCorePiece):
		if a.coordinate.x != b.coordinate.x: return a.coordinate.x < b.coordinate.x
		return a.coordinate.y < b.coordinate.y
	)
	for piece: ChessCorePiece in ordered:
		if piece.color != color or piece.stunned or piece.current_hp <= 0:
			continue
		if piece.type_id == &"arakne_king":
			for path in _legal_paths(state, piece):
				var action := ChessCoreAction.new()
				action.piece_id = piece.piece_id
				action.color = piece.color
				action.from = piece.coordinate
				action.target = path.back()
				action.path.assign(path)
				result.append(action)
		else:
			for target in _legal_destinations(state, piece):
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
	return result


## Direct attack geometry used by tactical analysis. This intentionally excludes
## castling and pawn forward movement, matching ModelPiece's attack relationship
## rather than command legality.
static func directly_attacks_square(state: ChessCoreState, piece: ChessCorePiece, target: Vector2i) -> bool:
	if state == null or piece == null or piece.stunned or piece.current_hp <= 0 or not _in_bounds(target) or target == piece.coordinate:
		return false
	return directly_attacks_in_occupancy(piece, piece.coordinate, target, state.occupancy)


## Projected-board variant for AI and editor analysis. The occupancy values stay
## pure-data pieces; callers may cheaply move references between squares without
## cloning or resolving a turn.
static func directly_attacks_in_occupancy(piece: ChessCorePiece, origin: Vector2i, target: Vector2i, occupancy: Dictionary) -> bool:
	if piece == null or piece.stunned or piece.current_hp <= 0 or not _in_bounds(target) or target == origin:
		return false
	var delta := target - origin
	match piece.type_id:
		&"pawn", &"bone_pawn":
			var direction := -1 if piece.color == "white" else 1
			return delta.x == direction and absi(delta.y) == 1
		&"knight":
			return Vector2i(absi(delta.x), absi(delta.y)) in [Vector2i(1, 2), Vector2i(2, 1)]
		&"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king":
			return absi(delta.x) <= 1 and absi(delta.y) <= 1
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
	var legal_move := false
	if submitted.kind == ChessCoreAction.Kind.MOVE and not submitted.path.is_empty() and submitted.target == submitted.path.back():
		legal_move = submitted.path in _legal_paths(source, piece) if piece.type_id == &"arakne_king" else (submitted.path == [submitted.target] and submitted.target in _legal_destinations(source, piece))
	if not legal_move:
		return ChessCoreStepResult.rejected(source, "Action is not legal in this state.")
	var state := source.copy()
	var result := ChessCoreStepResult.new()
	result.state = state
	_append_event(result.events, emit_events, &"action_started", {"color": state.current_turn})
	state.consecutive_forced_passes = 0
	state.resolution_context = {"action_owner": state.current_turn}
	piece = state.piece_by_id(submitted.piece_id)
	var origin := piece.coordinate
	var target_piece := state.occupant(submitted.target)
	var is_en_passant := piece.type_id == &"pawn" and target_piece == null and origin.y != submitted.target.y and _en_passant_victim(state, piece, submitted.target) != null
	var is_castle := piece.is_king() and submitted.path.size() == 1 and absi(submitted.target.y - origin.y) == 2
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
	elif target_piece != null:
		if target_piece.current_hp <= piece.attack_power:
			_commit_capture(state, piece, target_piece, submitted.target, submitted.target, result.events, emit_events)
		else:
			_deal_damage(state, target_piece, piece.attack_power, result.events, emit_events)
	else:
		state.move_piece(piece, submitted.target)
		piece.has_moved = true
		_append_event(result.events, emit_events, &"piece_moved", {"piece_id": piece.piece_id, "from": origin, "to": submitted.target})
		_append_event(result.events, emit_events, &"piece_landed", {"piece_id": piece.piece_id, "from": origin, "to": submitted.target})
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
	state.resolution_context = {"action_owner": state.current_turn}
	var piece := state.piece_by_id(submitted.piece_id)
	var target := state.occupant(submitted.target)
	var effect: Dictionary = rules.active_effect(state, piece, target)
	_append_event(result.events, emit_events, &"ability_committed", {
		"piece_id": piece.piece_id,
		"ability_id": effect.get("ability_id", &""),
		"target": submitted.target,
		"target_piece_id": target.piece_id if target != null else "",
	})
	if effect.has("summon_type"):
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
	_complete_or_pause(state, result, emit_events)
	return result


static func resolve_forced_passes(source: ChessCoreState, emit_events := true) -> ChessCoreStepResult:
	if source == null or source.pending_choice != null:
		return ChessCoreStepResult.rejected(source, "A settled state is required.")
	var result := ChessCoreStepResult.new()
	result.state = source.copy()
	_resolve_forced_passes(result.state, result.events, emit_events)
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
		&"classic_king", &"arakne_king", &"necromancer_king", &"minotaur_king":
			var moves: Array[Vector2i] = []
			for row in range(8):
				for column in range(8):
					var target := Vector2i(row, column)
					var delta := target - piece.coordinate
					if target != piece.coordinate and absi(delta.x) <= 1 and absi(delta.y) <= 1 and _available(state, target, piece.color): moves.append(target)
			if not piece.has_moved:
				for target in [Vector2i(7 if piece.color == "white" else 0, 2), Vector2i(7 if piece.color == "white" else 0, 6)]:
					if _can_castle(state, piece, target): moves.append(target)
			return moves
	return []


static func _legal_paths(state: ChessCoreState, piece: ChessCorePiece) -> Array[Array]:
	var destinations := _legal_destinations(state, piece)
	if piece.type_id == &"arakne_king":
		return ArakneCoreRules.movement_paths(state, piece, destinations)
	var result: Array[Array] = []
	for destination in destinations:
		result.append([destination])
	return result


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
			result.status = ChessCoreStepResult.Status.COMPLETED
			return
		state.resolution_context.clear()
		_finish_action(state, result.events, emit_events)
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


static func _raise_dead_targets(state: ChessCoreState, death_square: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		var target: Vector2i = death_square + offset
		if _in_bounds(target) and state.occupant(target) == null: result.append(target)
	if _in_bounds(death_square) and state.occupant(death_square) == null: result.append(death_square)
	return result


static func _finish_action(state: ChessCoreState, events: Array[ChessCoreEvent], emit_events: bool) -> void:
	var completed_color := state.current_turn
	_switch_turn(state, events, emit_events)
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
	_append_event(events, emit_events, &"cooldown_scheduled", {"piece_id": piece.piece_id})


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
		piece.current_cooldown = ChessCoreKingRules.base_cooldown(piece.type_id)
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
		state.consecutive_forced_passes += 1
		_append_event(events, emit_events, &"turn_passed", {"color": state.current_turn, "count": state.consecutive_forced_passes})
		if state.consecutive_forced_passes >= MAX_CONSECUTIVE_FORCED_PASSES:
			state.battle_over = true
			state.battle_result = "draw"
			_append_event(events, emit_events, &"battle_finished", {"result": "draw"})
			return
		_switch_turn(state, events, emit_events)
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
