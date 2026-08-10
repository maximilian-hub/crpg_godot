extends Node

const OVERWORLD := preload("res://scenes/overworld/overworld.tscn")
const MAIN := preload("res://scenes/main.tscn")

var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	await _test_overworld_scene()
	await _test_main_starts_in_overworld()
	if failures.is_empty():
		print("OVERWORLD CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("OVERWORLD FAILURE: ", failure)
		get_tree().quit(1)

func _test_overworld_scene() -> void:
	var overworld: Overworld = OVERWORLD.instantiate()
	overworld.configure(Vector2i(1, 1), Vector2i.LEFT, "initial", "")
	add_child(overworld)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(overworld.collision_grid.is_cell_blocked(Vector2i(0, 1)), "border cell is blocked")
	_check(not overworld.collision_grid.is_cell_blocked(Vector2i(1, 2)), "open cell is traversable")
	_check(overworld.collision_grid.tile_set.get_physics_layers_count() == 1, "collision grid has a physics layer")
	var tile_data := overworld.collision_grid.get_cell_tile_data(Vector2i(0, 1))
	_check(tile_data != null and tile_data.get_collision_polygons_count(0) == 1, "blocked tile has a physics polygon")

	var player := overworld.player
	_check(player is CharacterBody2D, "player uses CharacterBody2D")
	_check(player.position == Vector2(24, 24), "player starts at configured cell center")
	_check(player.test_move(player.global_transform, Vector2.LEFT * 16.0), "blocked tile contributes live physics geometry")
	_check(not player._try_begin_step(Vector2i.LEFT), "grid check rejects blocked destination")
	_check(player.facing == Vector2i.LEFT, "blocked direction still changes facing")

	var open_run := _find_open_horizontal_run(overworld)
	_check(not open_run.is_empty(), "painted collision map contains an open three-cell movement route")
	if open_run.is_empty():
		overworld.queue_free()
		return
	player.configure(overworld.collision_grid, overworld.npc, open_run[0], Vector2i.RIGHT)
	player.step_duration = 0.01
	_check(player._try_begin_step(Vector2i.RIGHT), "open grid step begins")
	player.queued_direction = Vector2i.UP
	player.queued_direction = Vector2i.RIGHT
	for index in range(8):
		await get_tree().physics_frame
	_check(player.grid_cell == open_run[2], "latest queued direction replaces the previous direction")
	_check(player.position == player.cell_center(open_run[2]), "completed movement snaps exactly to cell center")

	player.configure(overworld.collision_grid, overworld.npc, Vector2i(6, 6), Vector2i.UP)
	_check(overworld._can_talk_to_npc(), "idle adjacent player facing NPC can interact")
	overworld._begin_challenge_dialogue()
	_check(overworld.dialogue_mode == Overworld.DialogueMode.PAGES, "challenge opens page dialogue")
	overworld._advance_page()
	_check(overworld.dialogue_mode == Overworld.DialogueMode.CHOICE, "challenge pages lead to yes/no choice")
	overworld._decline_challenge()
	_check(overworld.dialogue_mode == Overworld.DialogueMode.PAGES, "decline shows configured response")
	overworld._advance_page()
	_check(overworld.dialogue_mode == Overworld.DialogueMode.CLOSED, "decline response returns to exploration")

	overworld.queue_free()
	await get_tree().process_frame

func _test_main_starts_in_overworld() -> void:
	var main: GameFlow = MAIN.instantiate()
	main.transition_duration = 0.0
	add_child(main)
	await get_tree().process_frame
	_check(main.active_overworld != null, "main starts with an overworld instance")
	_check(main.active_battle == null, "main does not start directly in battle")
	_check(main.active_overworld.get_player_cell() == Vector2i(6, 7), "main applies the scene-marker default player position")
	var movement_event := InputEventAction.new()
	movement_event.action = "move_left"
	movement_event.pressed = true
	Input.parse_input_event(movement_event)
	for index in range(10):
		await get_tree().physics_frame
	movement_event.pressed = false
	Input.parse_input_event(movement_event)
	await get_tree().physics_frame
	_check(main.active_overworld.get_player_cell().x < 6, "embedded overworld receives configured movement input")

	main.player_cell = Vector2i(5, 7)
	main.player_facing = Vector2i.LEFT
	await main._transition_to_battle()
	_check(main.active_overworld == null, "battle transition removes the overworld")
	_check(main.active_battle != null, "battle transition creates a chess game")
	_check(main.active_battle.control_mode == ChessGame.ControlMode.PLAYER_VS_CPU, "NPC battle uses player-vs-CPU mode")
	_check(main.active_battle.ai_color == "black", "NPC controls Black")

	var exit_results: Array[String] = []
	main.active_battle.battle_exit_requested.connect(func(result: String): exit_results.append(result))
	main.active_battle._on_battle_finished("white")
	_check(main.active_battle.completed_player_result == "win", "battle maps White victory to player win")
	main.active_battle._on_result_confirmed()
	for index in range(4):
		await get_tree().process_frame
	_check(exit_results == ["win"], "confirmed battle exit carries the player result")
	_check(main.active_overworld != null and main.active_battle == null, "confirmed result returns to a fresh overworld")
	_check(main.active_overworld.get_player_cell() == Vector2i(5, 7), "return restores saved player cell")
	_check(main.active_overworld.get_player_facing() == Vector2i.LEFT, "return restores saved facing")
	_check(main.active_overworld.dialogue_mode == Overworld.DialogueMode.PAGES, "result dialogue opens automatically after return")
	main.queue_free()
	await get_tree().process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _find_open_horizontal_run(overworld: Overworld) -> Array[Vector2i]:
	for y in range(OverworldCollisionGrid.GRID_SIZE.y):
		for x in range(OverworldCollisionGrid.GRID_SIZE.x - 2):
			var cells: Array[Vector2i] = [
				Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y),
			]
			var traversable := true
			for cell in cells:
				if overworld.collision_grid.is_cell_blocked(cell) or overworld.npc.grid_cell == cell:
					traversable = false
					break
			if traversable:
				return cells
	return []
