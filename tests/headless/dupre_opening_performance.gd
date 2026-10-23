extends Node

var failures: Array[String] = []


func _ready() -> void:
	DupreOpeningBook.clear_cache_for_tests()
	var book := await _benchmark(true)
	var warm_book := await _benchmark(true)
	var standard := await _benchmark(false)
	print("DUPRE OPENING PERFORMANCE: ", JSON.stringify({"book_cold": book, "book_warm": warm_book, "standard_dupre": standard}))
	if int(book.model_construction_count) != 0 or int(book.evaluated_reply_count) != 0: failures.append("ordinary book decision performed authoritative simulations")
	if int(book.legal_action_generation_passes_including_root) >= int(standard.legal_action_generation_passes_including_root): failures.append("book decision did not reduce legal-action generation")
	if int(book.elapsed_usec) >= int(standard.elapsed_usec): failures.append("book decision was not faster than standard Dupre")
	if int(warm_book.elapsed_usec) >= int(standard.elapsed_usec): failures.append("warm imported-book decision was not faster than standard Dupre")
	if int(warm_book.model_construction_count) != 0 or int(warm_book.evaluated_reply_count) != 0: failures.append("warm imported-book decision performed simulations")
	if not bool(book.opening_book_hit) or book.selected_status != &"book_fast_path": failures.append("book benchmark did not use the fast path")
	if failures.is_empty():
		print("DUPRE OPENING PERFORMANCE: PASS")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _benchmark(book_enabled: bool) -> Dictionary:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	add_child(model)
	var position := model.capture_position()
	for state in position.pieces:
		if String(state.type_id).contains("king"): state.type_id = &"classic_king"
	model.load_position(position)
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(8128)
	(cpu.brain as DupreAiBrain).max_book_moves = 7 if book_enabled else 0
	var started := Time.get_ticks_usec()
	var thought = await cpu.think()
	var elapsed := Time.get_ticks_usec() - started
	var profile: Dictionary = cpu.brain.get_last_profile()
	profile["elapsed_usec"] = elapsed
	profile["legal_action_generation_passes_including_root"] = int(profile.legal_action_generation_count) + 1
	if thought == null: failures.append("benchmark produced no action")
	cpu.queue_free(); model.queue_free()
	await get_tree().process_frame
	return profile
