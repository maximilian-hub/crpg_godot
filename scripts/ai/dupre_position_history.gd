extends RefCounted
class_name DuprePositionHistory

const DEFAULT_CAPACITY := 12

var capacity := DEFAULT_CAPACITY
var _ordered_signatures: Array[String] = []
var _counts := {}


func _init(p_capacity := DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, p_capacity)


func clear() -> void:
	_ordered_signatures.clear()
	_counts.clear()


func observe_position(position: ChessPosition) -> String:
	if position == null:
		return ""
	var signature := signature_for_position(position)
	_ordered_signatures.append(signature)
	_counts[signature] = int(_counts.get(signature, 0)) + 1
	while _ordered_signatures.size() > capacity:
		var removed: String = _ordered_signatures.pop_front()
		var remaining := int(_counts.get(removed, 0)) - 1
		if remaining <= 0: _counts.erase(removed)
		else: _counts[removed] = remaining
	return signature


func count_position(position: ChessPosition) -> int:
	if position == null:
		return 0
	return int(_counts.get(signature_for_position(position), 0))


func count_core_state(state: ChessCoreState) -> int:
	return count_position(ClassicChessCore.export_position(state))


func snapshot() -> Dictionary:
	return {"capacity": capacity, "size": _ordered_signatures.size(), "counts": _counts.duplicate(true)}


static func signature_for_position(position: ChessPosition) -> String:
	var data := ChessPositionCodec.to_dictionary(position)
	# These values affect reproducibility and pacing, but not whether returning to
	# the visible tactical position constitutes a playing cycle.
	data.erase("global_turn_number")
	data.erase("random_states")
	if not _last_move_enables_en_passant(position):
		data["last_move"] = null
	return JSON.stringify(data)


static func _last_move_enables_en_passant(position: ChessPosition) -> bool:
	var last := position.last_move
	if last == null or not last.is_present or last.piece_type_id != &"pawn" or absi(last.from.x - last.to.x) != 2:
		return false
	for piece in position.pieces:
		if piece.type_id == &"pawn" and piece.color != last.piece_color and piece.coordinate.x == last.to.x and absi(piece.coordinate.y - last.to.y) == 1:
			return true
	return false
