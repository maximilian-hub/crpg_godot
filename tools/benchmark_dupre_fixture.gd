extends SceneTree

const PositionCodec := preload("res://scripts/state/chess_position_codec.gd")


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var fixture_path := String(options.get("fixture", ""))
	if fixture_path.is_empty():
		printerr("Usage: --script res://tools/benchmark_dupre_fixture.gd -- --fixture=/path/to/fixture.json")
		quit(2)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	if not parsed is Dictionary or parsed.get("schema", "") != "crpg_dupre_fixed_work_fixture":
		printerr("Invalid fixed-work fixture: ", fixture_path)
		quit(2)
		return
	var decoded := PositionCodec.from_dictionary(parsed.get("position", {}))
	if decoded.position == null:
		printerr("Invalid fixture position: ", "; ".join(decoded.errors))
		quit(2)
		return
	var model := ChessBoardModel.new()
	get_root().add_child(model)
	if not model.load_position(decoded.position):
		printerr("Could not load fixture position")
		quit(2)
		return
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	get_root().add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, model.current_turn)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	var fixed: Dictionary = parsed.get("fixed_work", {})
	cpu.brain.max_book_moves = 0
	cpu.brain.candidate_limit = int(fixed.get("candidate_limit", 10))
	cpu.brain.max_reply_leaves = int(fixed.get("max_reply_leaves", 100))
	cpu.brain.think_budget_msec = int(fixed.get("think_budget_msec", 60000))
	var started := Time.get_ticks_usec()
	var thought = await cpu.think()
	var elapsed := Time.get_ticks_usec() - started
	if thought == null:
		printerr("Dupre produced no decision")
		quit(1)
		return
	print(JSON.stringify({
		"schema": "crpg_dupre_fixed_work_result", "version": 1,
		"source": parsed.get("source", {}), "elapsed_usec": elapsed,
		"selected": thought.to_dictionary().selected,
		"performance": thought.to_dictionary().performance,
	}, "  "))
	cpu.queue_free()
	model.queue_free()
	quit(0)


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument in arguments:
		if not argument.begins_with("--"): continue
		var body := argument.substr(2)
		var separator := body.find("=")
		if separator >= 0: result[body.substr(0, separator)] = body.substr(separator + 1)
	return result
