extends RefCounted
class_name ChessCoreState

var board_size := Vector2i(8, 8)
var board_type: StringName = &"default"
var pieces: Array[ChessCorePiece] = []
var occupancy: Dictionary = {}
var pieces_by_id: Dictionary = {}
var tile_effects: Array[ChessCoreTileEffect] = []
var effects_by_id: Dictionary = {}
var autonomous_entities: Array[ChessCoreAutonomousEntity] = []
var entities_by_id: Dictionary = {}
var current_turn := "white"
var last_move := {}
var battle_over := false
var battle_result := ""
var defeated_king_colors: Array[String] = []
var random_states := {}
var lunacy_by_color := {"white": 0, "black": 0}
var socratic_turns_by_color := {"white": 0, "black": 0}
var global_turn_number := 1
var consecutive_forced_passes := 0
var next_state_id := 1
var pending_choice: ChessCoreChoice
var reaction_queue: Array[ChessCoreReaction] = []
var next_reaction_sequence := 0
var resolution_context := {}
var active_ability_cooldowns_disabled := false
## Optional, non-authoritative instrumentation shared by descendants of one
## isolated search root. It is never serialized or consulted by game rules.
var performance_metrics: ChessCorePerformanceMetrics
## Non-authoritative, per-state analysis memoization. Copies intentionally begin
## empty because every copied state may be mutated into a different position.
var analysis_cache := {}
## Transient lifecycle marker used while an automatic Socratic move is being
## resolved. It is never exported as settled position state.
var socratic_resolution_color := ""


func copy() -> ChessCoreState:
	var copy_started := Time.get_ticks_usec()
	var result := ChessCoreState.new()
	result.performance_metrics = performance_metrics
	result.board_size = board_size
	result.board_type = board_type
	for piece in pieces:
		var cloned := piece.copy()
		result.pieces.append(cloned)
		result.occupancy[cloned.coordinate] = cloned
		result.pieces_by_id[cloned.piece_id] = cloned
	for effect in tile_effects:
		var cloned_effect := effect.copy()
		result.tile_effects.append(cloned_effect)
		result.effects_by_id[cloned_effect.effect_id] = cloned_effect
	for entity in autonomous_entities:
		var cloned_entity := entity.copy()
		result.autonomous_entities.append(cloned_entity)
		result.entities_by_id[cloned_entity.entity_id] = cloned_entity
	result.current_turn = current_turn
	result.last_move = last_move.duplicate(true)
	result.battle_over = battle_over
	result.battle_result = battle_result
	result.defeated_king_colors.assign(defeated_king_colors)
	result.random_states = random_states.duplicate(true)
	result.lunacy_by_color = lunacy_by_color.duplicate(true)
	result.socratic_turns_by_color = socratic_turns_by_color.duplicate(true)
	result.global_turn_number = global_turn_number
	result.consecutive_forced_passes = consecutive_forced_passes
	result.next_state_id = next_state_id
	result.pending_choice = pending_choice.copy() if pending_choice != null else null
	for reaction in reaction_queue: result.reaction_queue.append(reaction.copy())
	result.next_reaction_sequence = next_reaction_sequence
	result.resolution_context = resolution_context.duplicate(true)
	result.active_ability_cooldowns_disabled = active_ability_cooldowns_disabled
	result.socratic_resolution_color = socratic_resolution_color
	if performance_metrics != null:
		performance_metrics.record_state_copy(Time.get_ticks_usec() - copy_started)
	return result


func piece_by_id(id: String) -> ChessCorePiece:
	return pieces_by_id.get(id)


func occupant(coordinate: Vector2i) -> ChessCorePiece:
	return occupancy.get(coordinate)


func add_piece(piece: ChessCorePiece) -> void:
	analysis_cache.clear()
	pieces.append(piece)
	occupancy[piece.coordinate] = piece
	pieces_by_id[piece.piece_id] = piece


func move_piece(piece: ChessCorePiece, target: Vector2i) -> void:
	analysis_cache.clear()
	occupancy.erase(piece.coordinate)
	piece.coordinate = target
	occupancy[target] = piece


func remove_piece(piece: ChessCorePiece) -> void:
	analysis_cache.clear()
	occupancy.erase(piece.coordinate)
	pieces_by_id.erase(piece.piece_id)
	pieces.erase(piece)


func add_effect(effect: ChessCoreTileEffect) -> void:
	analysis_cache.clear()
	tile_effects.append(effect)
	effects_by_id[effect.effect_id] = effect


func remove_effect(effect: ChessCoreTileEffect) -> void:
	analysis_cache.clear()
	tile_effects.erase(effect)
	effects_by_id.erase(effect.effect_id)


func has_effect(type_id: StringName, coordinate: Vector2i, source_piece_id := "") -> bool:
	for effect in tile_effects:
		if effect.type_id == type_id and effect.coordinate == coordinate and (source_piece_id.is_empty() or effect.source_piece_id == source_piece_id):
			return true
	return false


func allocate_piece_id() -> String:
	return allocate_state_id("piece")


func allocate_state_id(prefix: String) -> String:
	var result := "%s_%d" % [prefix, next_state_id]
	next_state_id += 1
	return result


func add_entity(entity: ChessCoreAutonomousEntity) -> void:
	analysis_cache.clear()
	autonomous_entities.append(entity)
	entities_by_id[entity.entity_id] = entity


func remove_entity(entity: ChessCoreAutonomousEntity) -> void:
	analysis_cache.clear()
	autonomous_entities.erase(entity)
	entities_by_id.erase(entity.entity_id)
