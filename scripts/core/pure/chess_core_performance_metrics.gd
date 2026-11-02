extends RefCounted
class_name ChessCorePerformanceMetrics

var state_copy_count := 0
var state_copy_usec := 0
var maximum_state_copy_usec := 0
var silent_event_count := 0
var resolution_by_action_kind := {}
var resolution_by_king_type := {}


func record_state_copy(elapsed_usec: int) -> void:
	state_copy_count += 1
	state_copy_usec += elapsed_usec
	maximum_state_copy_usec = maxi(maximum_state_copy_usec, elapsed_usec)


func record_resolution(action_kind: int, king_type: StringName, elapsed_usec: int, emitted_events: int, emit_events: bool) -> void:
	_record_bucket(resolution_by_action_kind, str(action_kind), elapsed_usec)
	if king_type != &"":
		_record_bucket(resolution_by_king_type, String(king_type), elapsed_usec)
	if not emit_events:
		silent_event_count += emitted_events


func snapshot() -> Dictionary:
	return {
		"state_copy_count": state_copy_count,
		"state_copy_usec": state_copy_usec,
		"average_state_copy_usec": float(state_copy_usec) / float(state_copy_count) if state_copy_count > 0 else 0.0,
		"maximum_state_copy_usec": maximum_state_copy_usec,
		"silent_event_count": silent_event_count,
		"resolution_by_action_kind": resolution_by_action_kind.duplicate(true),
		"resolution_by_king_type": resolution_by_king_type.duplicate(true),
	}


func _record_bucket(buckets: Dictionary, key: String, elapsed_usec: int) -> void:
	var bucket: Dictionary = buckets.get(key, {"count": 0, "usec": 0, "maximum_usec": 0})
	bucket.count = int(bucket.count) + 1
	bucket.usec = int(bucket.usec) + elapsed_usec
	bucket.maximum_usec = maxi(int(bucket.maximum_usec), elapsed_usec)
	buckets[key] = bucket
