extends RefCounted
class_name CompletionGate

## Coordinates a producer with zero or more asynchronous signal subscribers.
#
# The producer creates a gate, includes it in a synchronous signal emission, calls
# close() after every subscriber has had an opportunity to claim it, and then awaits
# wait_until_released(). A subscriber that needs to delay the producer must call
# hold() synchronously during signal handling, await its work, and call release().
# Multiple subscribers may hold the same gate; it completes only after close() and
# every hold has a matching release. With no holds, close() completes it immediately.
#
## A gate cannot be held after close(), and release() cannot be called without a
# matching hold. Every claimant must guarantee release or the producer will remain
# suspended indefinitely.

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
