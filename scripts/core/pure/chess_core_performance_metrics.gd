extends RefCounted
class_name ChessCorePerformanceMetrics

## Fine-grained timers add Time calls inside hot loops, so normal gameplay keeps
## them off. Performance harnesses explicitly enable them.
var detailed_analysis_enabled := false
var state_copy_count := 0
var state_copy_usec := 0
var maximum_state_copy_usec := 0
var silent_event_count := 0
var analysis_action_query_count := 0
var analysis_action_cache_hit_count := 0
var analysis_action_generation_count := 0
var analysis_action_count := 0
var analysis_action_usec := 0
var maximum_analysis_action_usec := 0
var ordered_piece_query_count := 0
var ordered_piece_cache_hit_count := 0
var ordered_piece_sort_usec := 0
var tactical_attacker_query_count := 0
var tactical_attacker_cache_hit_count := 0
var tactical_attacker_scan_count := 0
var tactical_attacker_usec := 0
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


func record_analysis_actions(elapsed_usec: int, action_count: int, cache_hit: bool) -> void:
	if not detailed_analysis_enabled: return
	analysis_action_query_count += 1
	if cache_hit:
		analysis_action_cache_hit_count += 1
		return
	analysis_action_generation_count += 1
	analysis_action_count += action_count
	analysis_action_usec += elapsed_usec
	maximum_analysis_action_usec = maxi(maximum_analysis_action_usec, elapsed_usec)


func record_tactical_attackers(elapsed_usec: int, cache_hit: bool) -> void:
	if not detailed_analysis_enabled: return
	tactical_attacker_query_count += 1
	if cache_hit:
		tactical_attacker_cache_hit_count += 1
		return
	tactical_attacker_scan_count += 1
	tactical_attacker_usec += elapsed_usec


func record_ordered_pieces(elapsed_usec: int, cache_hit: bool) -> void:
	if not detailed_analysis_enabled: return
	ordered_piece_query_count += 1
	if cache_hit:
		ordered_piece_cache_hit_count += 1
	else:
		ordered_piece_sort_usec += elapsed_usec


func snapshot() -> Dictionary:
	return {
		"state_copy_count": state_copy_count,
		"state_copy_usec": state_copy_usec,
		"average_state_copy_usec": float(state_copy_usec) / float(state_copy_count) if state_copy_count > 0 else 0.0,
		"maximum_state_copy_usec": maximum_state_copy_usec,
		"silent_event_count": silent_event_count,
		"analysis_action_query_count": analysis_action_query_count,
		"analysis_action_cache_hit_count": analysis_action_cache_hit_count,
		"analysis_action_generation_count": analysis_action_generation_count,
		"analysis_action_count": analysis_action_count,
		"analysis_action_usec": analysis_action_usec,
		"maximum_analysis_action_usec": maximum_analysis_action_usec,
		"ordered_piece_query_count": ordered_piece_query_count,
		"ordered_piece_cache_hit_count": ordered_piece_cache_hit_count,
		"ordered_piece_sort_usec": ordered_piece_sort_usec,
		"tactical_attacker_query_count": tactical_attacker_query_count,
		"tactical_attacker_cache_hit_count": tactical_attacker_cache_hit_count,
		"tactical_attacker_scan_count": tactical_attacker_scan_count,
		"tactical_attacker_usec": tactical_attacker_usec,
		"resolution_by_action_kind": resolution_by_action_kind.duplicate(true),
		"resolution_by_king_type": resolution_by_king_type.duplicate(true),
	}


func _record_bucket(buckets: Dictionary, key: String, elapsed_usec: int) -> void:
	var bucket: Dictionary = buckets.get(key, {"count": 0, "usec": 0, "maximum_usec": 0})
	bucket.count = int(bucket.count) + 1
	bucket.usec = int(bucket.usec) + elapsed_usec
	bucket.maximum_usec = maxi(int(bucket.maximum_usec), elapsed_usec)
	buckets[key] = bucket
