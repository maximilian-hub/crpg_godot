extends RefCounted
class_name ChessCoreState

var board_size := Vector2i(8, 8)
var board_type: StringName = &"default"
var pieces: Array[ChessCorePiece] = []
var occupancy: Dictionary = {}
var pieces_by_id: Dictionary = {}
var current_turn := "white"
var last_move := {}
var battle_over := false
var battle_result := ""
var defeated_king_colors: Array[String] = []
var random_states := {}
var global_turn_number := 1
var consecutive_forced_passes := 0
var next_state_id := 1
var pending_choice: ChessCoreChoice
var reaction_queue: Array[ChessCoreReaction] = []
var next_reaction_sequence := 0
var resolution_context := {}
var active_ability_cooldowns_disabled := false


func copy() -> ChessCoreState:
	var result := ChessCoreState.new()
	result.board_size = board_size
	result.board_type = board_type
	for piece in pieces:
		var cloned := piece.copy()
		result.pieces.append(cloned)
		result.occupancy[cloned.coordinate] = cloned
		result.pieces_by_id[cloned.piece_id] = cloned
	result.current_turn = current_turn
	result.last_move = last_move.duplicate(true)
	result.battle_over = battle_over
	result.battle_result = battle_result
	result.defeated_king_colors.assign(defeated_king_colors)
	result.random_states = random_states.duplicate(true)
	result.global_turn_number = global_turn_number
	result.consecutive_forced_passes = consecutive_forced_passes
	result.next_state_id = next_state_id
	result.pending_choice = pending_choice.copy() if pending_choice != null else null
	for reaction in reaction_queue: result.reaction_queue.append(reaction.copy())
	result.next_reaction_sequence = next_reaction_sequence
	result.resolution_context = resolution_context.duplicate(true)
	result.active_ability_cooldowns_disabled = active_ability_cooldowns_disabled
	return result


func piece_by_id(id: String) -> ChessCorePiece:
	return pieces_by_id.get(id)


func occupant(coordinate: Vector2i) -> ChessCorePiece:
	return occupancy.get(coordinate)


func add_piece(piece: ChessCorePiece) -> void:
	pieces.append(piece)
	occupancy[piece.coordinate] = piece
	pieces_by_id[piece.piece_id] = piece


func move_piece(piece: ChessCorePiece, target: Vector2i) -> void:
	occupancy.erase(piece.coordinate)
	piece.coordinate = target
	occupancy[target] = piece


func remove_piece(piece: ChessCorePiece) -> void:
	occupancy.erase(piece.coordinate)
	pieces_by_id.erase(piece.piece_id)
	pieces.erase(piece)


func allocate_piece_id() -> String:
	var result := "piece_%d" % next_state_id
	next_state_id += 1
	return result
