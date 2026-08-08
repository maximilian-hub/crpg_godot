extends RefCounted
class_name CompletionGate

signal completed

var _holds: int = 0
var _closed: bool = false
var _completed: bool = false


func hold() -> void:
	assert(not _closed, "CompletionGate cannot be held after emission closes.")
	_holds += 1


func release() -> void:
	assert(_holds > 0, "CompletionGate release called without a matching hold.")
	_holds -= 1
	_try_complete()


func close() -> void:
	_closed = true
	_try_complete()


func wait_until_released() -> void:
	if _completed:
		return
	await completed


func is_completed() -> bool:
	return _completed


func _try_complete() -> void:
	if _closed and _holds == 0 and not _completed:
		_completed = true
		completed.emit()
