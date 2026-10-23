extends SceneTree

## Development-time second validation layer for generated orthodox theory.
## Every accepted line is replayed through the authoritative ChessBoardModel.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		printerr("Usage: validate_openings.gd -- <candidate.json> <result.json>")
		quit(2)
		return
	var candidate_path: String = arguments[0]
	var result_path: String = arguments[1]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
	if not parsed is Dictionary or not parsed.has("lines"):
		printerr("Opening candidate file is invalid: ", candidate_path)
		quit(2)
		return
	var accepted: Array[String] = []
	var rejections: Array[Dictionary] = []
	var line_number := 0
	for line_value in parsed.lines:
		line_number += 1
		var line: Dictionary = line_value
		var result := await _validate_line(line)
		if result.is_empty():
			accepted.append(String(line.line_id))
		else:
			rejections.append(result)
		if line_number % 100 == 0:
			await process_frame
	var output := {
		"accepted_line_ids": accepted,
		"rejections": rejections,
	}
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file == null:
		printerr("Unable to write validation result: ", result_path)
		quit(2)
		return
	file.store_string(JSON.stringify(output, "  ", false) + "\n")
	file.close()
	print("AUTHORITATIVE OPENING VALIDATION: accepted=", accepted.size(), " rejected=", rejections.size())
	quit(0)


func _validate_line(line: Dictionary) -> Dictionary:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	root.add_child(model)
	var position := model.capture_position()
	for state in position.pieces:
		if String(state.type_id).contains("king"):
			state.type_id = &"classic_king"
	position.current_turn = "white"
	position.global_turn_number = 1
	model.load_position(position)
	var ply := 0
	for descriptor_value in line.moves:
		ply += 1
		var descriptor: Dictionary = descriptor_value
		var matching := _matching_action(model, descriptor)
		if matching == null:
			var rejection := _rejection(line, ply, "no_exact_authoritative_action", descriptor)
			model.queue_free()
			return rejection
		var accepted: bool
		if matching.path.size() > 1:
			accepted = await model.submit_move_path(matching.piece, matching.path)
		else:
			accepted = await model.submit_move(matching.piece, matching.target)
		if not accepted or not model.is_settled():
			var rejection := _rejection(line, ply, "authoritative_execution_failed", descriptor)
			model.queue_free()
			return rejection
	model.queue_free()
	return {}


func _matching_action(model: ChessBoardModel, descriptor: Dictionary) -> ChessPrimaryAction:
	var expected_from := _vector(descriptor["from"])
	var expected_to := _vector(descriptor["to"])
	var expected_path: Array[Vector2i] = []
	for coordinate in descriptor.get("path", [descriptor["to"]]):
		expected_path.append(_vector(coordinate))
	for action in model.get_legal_primary_actions(model.current_turn):
		if action.kind != int(descriptor["kind"]):
			continue
		if action.piece.color != String(descriptor["color"]):
			continue
		if action.piece.get_position_type_id() != StringName(descriptor["piece"]):
			continue
		if action.piece.coordinate != expected_from or action.target != expected_to:
			continue
		if action.path != expected_path:
			continue
		return action
	return null


func _vector(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


func _rejection(line: Dictionary, ply: int, reason: String, descriptor: Dictionary) -> Dictionary:
	return {
		"line_id": String(line.line_id),
		"family_id": String(line.family_id),
		"name": String(line.name),
		"ply": ply,
		"uci": String(descriptor.get("uci", "")),
		"reason": reason,
	}
