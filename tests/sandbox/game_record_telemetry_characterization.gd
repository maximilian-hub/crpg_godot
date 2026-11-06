extends Node

const RecordCodec := preload("res://scripts/state/chess_game_record_codec.gd")
const Telemetry := preload("res://scripts/state/chess_ai_performance_telemetry.gd")


func _ready() -> void:
	var failures: Array[String] = []
	var profile := {
		"budget_usec": 5000000, "thinking_usec": 4980000, "root_action_count": 30,
		"prepared_root_candidates": 10, "exact_root_candidates": 3, "pruned_root_candidates": 2,
		"incomplete_root_candidates": 5, "invalid_root_candidates": 0,
		"evaluated_reply_count": 120, "total_available_replies": 300,
		"legal_action_generation_count": 44, "legal_action_generation_usec": 410000,
		"state_copy_count": 130, "state_copy_usec": 520000, "maximum_state_copy_usec": 9000,
		"core_resolution_count": 120, "core_resolution_usec": 1200000,
		"evaluation_count": 120, "evaluation_usec": 800000,
		"tactical_map_build_usec": 100000, "tactical_projection_usec": 180000,
		"policy_ranking_usec": 90000, "candidate_selection_usec": 50000,
		"maximum_uninterrupted_usec": 7200, "yield_count": 81,
		"fallback_used": true, "unverified_selection": true,
		"selected_status": &"breadth_fallback", "selected_candidate_reason": &"material_obligation",
		"selected_fallback_risk": 1, "simulation_backend": &"classic_core",
		"large_debug_payload": PackedStringArray(Array(range(200)).map(func(index): return "diagnostic-%d" % index)),
	}
	var compact := Telemetry.from_search_profile(profile)
	_check(compact.version == 1 and compact.budget_usec == 5000000 and compact.evaluated_reply_count == 120, "compact telemetry preserves stable budget and throughput counters", failures)
	_check(compact.unverified and compact.selected_status == "breadth_fallback" and not compact.has("large_debug_payload"), "compact telemetry retains correctness status without arbitrary diagnostics", failures)
	var telemetry_started := Time.get_ticks_usec()
	for _iteration in range(1000): Telemetry.from_search_profile(profile)
	var telemetry_usec := Time.get_ticks_usec() - telemetry_started
	print("TELEMETRY EXTRACTION: %.2f usec/turn" % (float(telemetry_usec) / 1000.0))
	_check(telemetry_usec < 500000, "compact telemetry extraction remains negligible relative to an AI turn", failures)
	var frames: Array = [{"ai": {"performance": compact}}, {"ai": {"performance": compact}}]
	var summary := Telemetry.summarize_frames(frames)
	_check(summary.turns == 2 and summary.search_turns == 2 and summary.evaluated_replies == 240 and summary.fallback_turns == 2 and summary.unverified_turns == 2, "record summary aggregates compact AI turns", failures)
	_check(is_equal_approx(float(summary.replies_per_second), 240.0 * 1000000.0 / 9960000.0), "record summary reports fixed-budget search throughput", failures)

	var model := ChessBoardModel.new()
	model.initialize_battle()
	var record := ChessGameRecord.new()
	record.frames = [{"position": model.capture_position(), "label": "baseline", "kind": &"baseline", "action": {}, "selections": [], "ai": {"performance": compact}, "context": {}}]
	var encoded := RecordCodec.to_dictionary(record)
	_check(int(encoded.version) == 2 and encoded.performance_summary.turns == 1, "record schema v2 embeds a derived match performance summary", failures)
	var legacy := encoded.duplicate(true)
	legacy.version = 1
	legacy.erase("performance_summary")
	var decoded := RecordCodec.from_dictionary(legacy)
	_check(decoded.record != null and decoded.record.frames.size() == 1, "schema-v1 recordings remain importable", failures)
	model.free()

	if failures.is_empty():
		print("GAME RECORD TELEMETRY CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		printerr("GAME RECORD TELEMETRY CHARACTERIZATION: FAIL")
		for failure in failures: printerr(" - ", failure)
		get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
