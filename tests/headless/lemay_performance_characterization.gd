extends Node

var failures: Array[String] = []


func _ready() -> void:
	var classic := await _benchmark(&"lemay_classic", &"classic_king", ChessCpuPlayer.BrainKind.LEMAY)
	var arakne := await _benchmark(&"lemay_arakne", &"arakne_king", ChessCpuPlayer.BrainKind.LEMAY)
	var dupre_classic := await _benchmark(&"dupre_classic", &"classic_king", ChessCpuPlayer.BrainKind.DUPRE)
	var dupre_arakne := await _benchmark(&"dupre_arakne", &"arakne_king", ChessCpuPlayer.BrainKind.DUPRE)
	print("TACTICAL AI PERFORMANCE: ", JSON.stringify({"lemay_classic": classic, "lemay_arakne": arakne, "dupre_classic": dupre_classic, "dupre_arakne": dupre_arakne}))
	if failures.is_empty():
		print("LEMAY PERFORMANCE CHARACTERIZATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _benchmark(label: StringName, white_king_type: StringName, brain_kind: ChessCpuPlayer.BrainKind) -> Dictionary:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	add_child(model)
	var position := model.capture_position()
	for state in position.pieces:
		if state.color == "white" and String(state.type_id).contains("king"):
			state.type_id = white_king_type
		elif state.color == "black" and String(state.type_id).contains("king"):
			state.type_id = &"classic_king"
	position.current_turn = "white"
	model.load_position(position)
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(brain_kind)
	cpu.set_random_seed(8128)
	var thought = await cpu.think()
	var profile: Dictionary = cpu.brain.get_last_profile()
	if thought == null:
		failures.append("%s benchmark produced no thought" % label)
	if profile.position_load_count != profile.model_construction_count:
		failures.append("%s benchmark did not keep a one-load-per-model invariant" % label)
	if profile.legal_action_generation_count > profile.root_action_count + profile.evaluated_reply_count * 2:
		failures.append("%s benchmark regenerated legal actions during evaluation" % label)
	if profile.selected_status not in [&"exact", &"fallback", &"verified", &"policy_fallback", &"book_fast_path"]:
		failures.append("%s benchmark selected an invalid search status" % label)
	cpu.queue_free()
	model.free()
	await get_tree().process_frame
	return profile
