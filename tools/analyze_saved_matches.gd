extends SceneTree

const RecordCodec := preload("res://scripts/state/chess_game_record_codec.gd")
const PositionCodec := preload("res://scripts/state/chess_position_codec.gd")
const Telemetry := preload("res://scripts/state/chess_ai_performance_telemetry.gd")


func _initialize() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var corpus := String(options.get("corpus", "res://saved_matches"))
	var reports := _analyze_corpus(corpus, String(options.get("compact-dir", "")))
	if options.has("extract"):
		_extract_fixed_work_fixture(String(options.extract), String(options.get("output", "/private/tmp/dupre_fixed_work_fixture.json")), int(options.get("candidates", 10)), int(options.get("replies", 100)))
	if options.has("json"):
		var file := FileAccess.open(String(options.json), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"schema": "crpg_dupre_corpus_report", "version": 1, "matches": reports}, "  "))
	_print_reports(reports)
	quit(0)


func _analyze_corpus(path: String, compact_directory: String = "") -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if not compact_directory.is_empty(): DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(compact_directory))
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".crpggame"): continue
		var full_path := path.path_join(filename)
		var decoded := RecordCodec.load_file(full_path)
		if decoded.record == null:
			printerr("SKIP ", filename, ": ", "; ".join(decoded.errors))
			continue
		var summary := Telemetry.summarize_frames(decoded.record.frames)
		var original_bytes := FileAccess.get_file_as_bytes(full_path).size()
		var compact_bytes := 0
		if not compact_directory.is_empty():
			_compact_record(decoded.record)
			var compact_path := compact_directory.path_join(filename)
			RecordCodec.save_file(decoded.record, compact_path)
			compact_bytes = FileAccess.get_file_as_bytes(compact_path).size()
		reports.append({"file": filename, "path": full_path, "bytes": original_bytes, "compact_bytes": compact_bytes, "frames": decoded.record.frames.size(), "summary": summary})
	reports.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.summary.get("turns", 0)) > int(b.summary.get("turns", 0)))
	return reports


func _print_reports(reports: Array[Dictionary]) -> void:
	print("DUPRE REPLAY PERFORMANCE CORPUS")
	for report in reports:
		var summary: Dictionary = report.summary
		print("%s | %.1f KiB | %d frames | %d AI turns | %.1f replies/s | %d fallback | %d unverified | %.2f ms max slice" % [
			report.file, float(report.bytes) / 1024.0, int(report.frames), int(summary.get("turns", 0)),
			float(summary.get("replies_per_second", 0.0)), int(summary.get("fallback_turns", 0)),
			int(summary.get("unverified_turns", 0)), float(summary.get("maximum_uninterrupted_usec", 0)) / 1000.0,
		])
		if int(report.get("compact_bytes", 0)) > 0:
			print("  compact: %.1f KiB (%.1f%% smaller)" % [float(report.compact_bytes) / 1024.0, 100.0 * (1.0 - float(report.compact_bytes) / maxf(1.0, float(report.bytes)))])
		for worst in summary.get("lowest_throughput_frames", []).slice(0, 3):
			print("  frame %d: %.1f replies/s, %d replies, %.2f ms max slice" % [int(worst.frame) + 1, float(worst.replies_per_second), int(worst.replies), float(worst.uninterrupted_usec) / 1000.0])


func _compact_record(record) -> void:
	for frame in record.frames:
		var context: Dictionary = frame.get("context", {})
		for color in ["white", "black"]:
			var cpu: Dictionary = context.get(color, {})
			cpu.erase("brain_state")
		var ai: Dictionary = frame.get("ai", {})
		if ai.is_empty(): continue
		if ai.get("performance", {}).is_empty(): ai.performance = Telemetry.from_search_profile(ai.get("search_profile", {}))
		ai.erase("search_profile")
		ai.erase("candidates")
		var pre: Dictionary = ai.get("pre_decision_context", {})
		pre.erase("brain_state")


func _extract_fixed_work_fixture(specification: String, output_path: String, candidates: int, replies: int) -> void:
	var separator := specification.rfind(":")
	if separator < 0:
		printerr("--extract requires path:frame")
		return
	var path := specification.substr(0, separator)
	var frame_index := int(specification.substr(separator + 1))
	var decoded := RecordCodec.load_file(path)
	if decoded.record == null or frame_index <= 0 or frame_index >= decoded.record.frames.size():
		printerr("Cannot extract fixed-work fixture ", specification)
		return
	var frame: Dictionary = decoded.record.frames[frame_index]
	var previous: Dictionary = decoded.record.frames[frame_index - 1]
	var fixture := {
		"schema": "crpg_dupre_fixed_work_fixture", "version": 1,
		"source": {"record": path, "frame": frame_index},
		"position": PositionCodec.to_dictionary(previous.position),
		"expected_selected": frame.get("ai", {}).get("selected", {}),
		"fixed_work": {"candidate_limit": maxi(1, candidates), "max_reply_leaves": maxi(1, replies), "think_budget_msec": 60000},
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write ", output_path)
		return
	file.store_string(JSON.stringify(fixture, "  "))
	print("Extracted fixed-work fixture: ", output_path)


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument in arguments:
		if not argument.begins_with("--"): continue
		var body := argument.substr(2)
		var separator := body.find("=")
		if separator < 0: result[body] = true
		else: result[body.substr(0, separator)] = body.substr(separator + 1)
	return result
