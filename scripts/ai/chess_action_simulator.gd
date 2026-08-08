extends RefCounted
class_name ChessActionSimulator

## Isolated, headless command runner used by CPU evaluation.

const MAX_REACTION_SELECTIONS: int = 32


func clone_model(source: ChessBoardModel) -> Dictionary:
	var clone := ChessBoardModel.new()
	clone.initialize_battle()
	clone.suppress_diagnostics = true
	for row in clone.board:
		for piece in row:
			if piece != null:
				clone.unregister_piece(piece)
	clone.board.clear()
	for source_row in source.board:
		var clone_row: Array = []
		clone_row.resize(source_row.size())
		clone.board.append(clone_row)

	var piece_map: Dictionary = {}
	for row in source.board:
		for piece: ModelPiece in row:
			if piece == null:
				continue
			var copied: ModelPiece = piece.get_script().new(piece.color, piece.coordinate)
			_copy_piece_state(piece, copied)
			clone.add_piece(copied, copied.coordinate)
			piece_map[piece] = copied

	clone.current_turn = source.current_turn
	clone.battle_over = source.battle_over
	clone.battle_result = source.battle_result
	clone.defeated_king_colors.assign(source.defeated_king_colors)
	clone.action_in_progress = false
	clone.action_owner_color = ""
	clone.selection_queue.clear()
	clone.pending_reaction.clear()
	clone.selection_sequence = 0
	clone.last_move = {}
	if not source.last_move.is_empty():
		clone.last_move = {
			"from": source.last_move.get("from"),
			"to": source.last_move.get("to"),
			"piece": piece_map.get(source.last_move.get("piece")),
			"piece_type": source.last_move.get("piece_type", ""),
			"piece_color": source.last_move.get("piece_color", ""),
		}
	clone.last_destroyed_piece = piece_map.get(source.last_destroyed_piece)
	return {"model": clone, "piece_map": piece_map}


func submit_action(model: ChessBoardModel, action: ChessPrimaryAction) -> bool:
	var accepted := false
	if action.kind == ChessPrimaryAction.Kind.MOVE:
		accepted = await model.submit_move(action.piece, action.target)
	else:
		accepted = await model.submit_active_ability(action.piece as KingPiece, action.target)
	if not accepted:
		return false
	return await _resolve_reactions(model)


func map_action(action: ChessPrimaryAction, piece_map: Dictionary) -> ChessPrimaryAction:
	var copied_piece: ModelPiece = piece_map.get(action.piece)
	if copied_piece == null:
		return null
	return ChessPrimaryAction.new(action.kind, copied_piece, action.target)


func _resolve_reactions(model: ChessBoardModel) -> bool:
	var selections := 0
	while model.has_pending_reaction():
		if selections >= MAX_REACTION_SELECTIONS:
			return false
		var pending := model.get_pending_reaction()
		var targets: Array = pending.get("targets", [])
		if targets.is_empty():
			return false
		targets.sort_custom(func(a: Vector2i, b: Vector2i):
			return a.x < b.x or (a.x == b.x and a.y < b.y)
		)
		if not await model.submit_reaction_selection(targets[0]):
			return false
		selections += 1
	return model.battle_over or not model.action_in_progress


func _copy_piece_state(source: ModelPiece, target: ModelPiece) -> void:
	target.max_hp = source.max_hp
	target.current_hp = source.current_hp
	target.attack_power = source.attack_power
	target.has_moved = source.has_moved
	target.stunned = source.stunned
	target.stun_timer = source.stun_timer
	target.cooldown = source.cooldown
	if source is KingPiece and target is KingPiece:
		var source_king := source as KingPiece
		var target_king := target as KingPiece
		target_king.base_cooldown = source_king.base_cooldown
		target_king.current_cooldown = source_king.current_cooldown
