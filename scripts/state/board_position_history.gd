extends RefCounted
class_name BoardPositionHistory

signal changed(can_undo: bool, can_redo: bool)

var entries: Array[ChessPosition] = []
var labels: Array[String] = []
var cursor := -1
var baseline: ChessPosition

func establish_baseline(position: ChessPosition, label := "Baseline") -> void:
	baseline = position.copy()
	entries.assign([baseline.copy()])
	labels.assign([label])
	cursor = 0
	_emit_changed()

func push(position: ChessPosition, label := "") -> void:
	while entries.size() > cursor + 1:
		entries.pop_back()
		labels.pop_back()
	entries.append(position.copy())
	labels.append(label)
	cursor = entries.size() - 1
	_emit_changed()

func can_undo() -> bool:
	return cursor > 0

func can_redo() -> bool:
	return cursor >= 0 and cursor < entries.size() - 1

func undo() -> ChessPosition:
	if not can_undo(): return null
	cursor -= 1
	_emit_changed()
	return entries[cursor].copy()

func redo() -> ChessPosition:
	if not can_redo(): return null
	cursor += 1
	_emit_changed()
	return entries[cursor].copy()

func get_baseline() -> ChessPosition:
	return baseline.copy() if baseline != null else null

func _emit_changed() -> void:
	changed.emit(can_undo(), can_redo())
