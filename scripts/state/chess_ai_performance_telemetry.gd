extends RefCounted
class_name ChessAiPerformanceTelemetry

const VERSION := 1

const COUNTER_KEYS: Array[StringName] = [
	&"root_action_count", &"prepared_root_candidates", &"exact_root_candidates",
	&"pruned_root_candidates", &"incomplete_root_candidates", &"invalid_root_candidates",
	&"evaluated_reply_count", &"total_available_replies", &"legal_action_generation_count",
	&"state_copy_count", &"core_resolution_count", &"evaluation_count", &"yield_count",
	&"silent_event_count", &"policy_reactions_resolved",
]
const TIME_KEYS: Array[StringName] = [
	&"thinking_usec", &"legal_action_generation_usec", &"state_copy_usec",
	&"core_resolution_usec", &"evaluation_usec", &"tactical_map_build_usec",
	&"tactical_projection_usec", &"policy_ranking_usec", &"candidate_selection_usec",
	&"maximum_uninterrupted_usec", &"maximum_state_copy_usec",
	&"maximum_action_execution_usec", &"maximum_legal_action_generation_usec",
]


static func from_search_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return {}
	var result := {
		"version": VERSION,
		"budget_usec": int(profile.get("budget_usec", 0)),
		"book_hit": bool(profile.get("opening_book_hit", false)),
		"book_override": bool(profile.get("opening_book_override", false)),
		"backend": String(profile.get("simulation_backend", "")),
		"danger": String(profile.get("danger_class", "")),
		"selected_status": String(profile.get("selected_status", "")),
		"selected_reason": String(profile.get("selected_candidate_reason", "")),
		"fallback_used": bool(profile.get("fallback_used", false)),
		"unverified": bool(profile.get("unverified_selection", false)),
		"fallback_risk": int(profile.get("selected_fallback_risk", -1)),
		"forcing_coverage_complete": bool(profile.get("selected_forcing_coverage_complete", false)),
	}
	for key in COUNTER_KEYS:
		result[String(key)] = int(profile.get(key, 0))
	for key in TIME_KEYS:
		result[String(key)] = int(profile.get(key, 0))
	var resolution_by_kind = profile.get("resolution_by_action_kind", {})
	if resolution_by_kind is Dictionary and not resolution_by_kind.is_empty():
		result["resolution_by_action_kind"] = _compact_numeric_dictionary(resolution_by_kind)
	var resolution_by_king = profile.get("resolution_by_king_type", {})
	if resolution_by_king is Dictionary and not resolution_by_king.is_empty():
		result["resolution_by_king_type"] = _compact_numeric_dictionary(resolution_by_king)
	return result


static func summarize_frames(frames: Array) -> Dictionary:
	var turns := 0
	var total_thinking_usec := 0
	var total_replies := 0
	var search_turns := 0
	var search_thinking_usec := 0
	var search_replies := 0
	var exact := 0
	var incomplete := 0
	var fallbacks := 0
	var unverified := 0
	var maximum_uninterrupted_usec := 0
	var component_usec := {"state_copy": 0, "resolution": 0, "legal_generation": 0, "evaluation": 0, "tactical": 0, "policy": 0}
	var worst: Array[Dictionary] = []
	for index in range(frames.size()):
		var ai: Dictionary = frames[index].get("ai", {})
		var telemetry: Dictionary = ai.get("performance", {})
		if telemetry.is_empty():
			telemetry = from_search_profile(ai.get("search_profile", {}))
		if telemetry.is_empty():
			continue
		turns += 1
		var thinking := int(telemetry.get("thinking_usec", 0))
		var replies := int(telemetry.get("evaluated_reply_count", 0))
		total_thinking_usec += thinking
		total_replies += replies
		var book_hit := bool(telemetry.get("book_hit", false))
		if not book_hit:
			search_turns += 1
			search_thinking_usec += thinking
			search_replies += replies
		exact += int(telemetry.get("exact_root_candidates", 0))
		incomplete += int(telemetry.get("incomplete_root_candidates", 0))
		fallbacks += int(bool(telemetry.get("fallback_used", false)))
		unverified += int(bool(telemetry.get("unverified", false)))
		maximum_uninterrupted_usec = maxi(maximum_uninterrupted_usec, int(telemetry.get("maximum_uninterrupted_usec", 0)))
		component_usec.state_copy += int(telemetry.get("state_copy_usec", 0))
		component_usec.resolution += int(telemetry.get("core_resolution_usec", 0))
		component_usec.legal_generation += int(telemetry.get("legal_action_generation_usec", 0))
		component_usec.evaluation += int(telemetry.get("evaluation_usec", 0))
		component_usec.tactical += int(telemetry.get("tactical_map_build_usec", 0)) + int(telemetry.get("tactical_projection_usec", 0))
		component_usec.policy += int(telemetry.get("policy_ranking_usec", 0)) + int(telemetry.get("candidate_selection_usec", 0))
		if not book_hit:
			worst.append({"frame": index, "thinking_usec": thinking, "replies": replies, "replies_per_second": _rate(replies, thinking), "uninterrupted_usec": int(telemetry.get("maximum_uninterrupted_usec", 0))})
	worst.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.replies_per_second) < float(b.replies_per_second))
	if worst.size() > 8:
		worst.resize(8)
	return {
		"version": VERSION, "turns": turns, "total_thinking_usec": total_thinking_usec,
		"average_thinking_usec": int(total_thinking_usec / maxi(1, turns)),
		"evaluated_replies": total_replies, "search_turns": search_turns,
		"search_thinking_usec": search_thinking_usec, "search_replies": search_replies,
		"replies_per_second": _rate(search_replies, search_thinking_usec),
		"exact_roots": exact, "incomplete_roots": incomplete, "fallback_turns": fallbacks,
		"unverified_turns": unverified, "maximum_uninterrupted_usec": maximum_uninterrupted_usec,
		"component_usec": component_usec, "lowest_throughput_frames": worst,
	}


static func _rate(count: int, usec: int) -> float:
	return float(count) * 1000000.0 / float(usec) if usec > 0 else 0.0


static func _compact_numeric_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		var value = source[key]
		if value is int or value is float:
			result[String(key)] = value
		elif value is Dictionary:
			result[String(key)] = _compact_numeric_dictionary(value)
	return result
