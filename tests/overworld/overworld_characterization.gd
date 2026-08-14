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
	var player_body := player.get_node("Body") as AnimatedSprite2D
	_check(player_body != null, "player artwork uses AnimatedSprite2D")
	_check(player_body.position == Vector2(0, -4), "player artwork has the visual-only vertical offset")
	for animation_name in [&"idle_up", &"idle_down", &"idle_left", &"idle_right", &"walk_up", &"walk_down", &"walk_left", &"walk_right"]:
		_check(player_body.sprite_frames.has_animation(animation_name), "player has %s animation" % animation_name)
	_check(player_body.animation == &"walk_left" and player_body.frame == 0 and player_body.flip_h, "configured left facing explicitly selects neutral 0001")
	for phase in range(4):
		var texture_path := player_body.sprite_frames.get_frame_texture(&"walk_down", phase).resource_path
		_check(texture_path.ends_with("000%d.png" % (phase + 1)), "gait phase %d maps to sprite 000%d" % [phase, phase + 1])
	_check(player.get_node("CollisionShape2D").position == Vector2.ZERO, "player collision remains rooted at the gameplay position")
	_check(overworld.npc.get_node("Body").position == Vector2(0, -4), "NPC artwork has the visual-only vertical offset")
	_check(overworld.npc.get_node("CollisionShape2D").position == Vector2.ZERO, "NPC collision remains rooted at the gameplay position")
	var camera := player.get_node("Camera2D") as Camera2D
	_check(camera != null and camera.enabled, "player camera is active")
	_check(camera.position == Vector2.ZERO, "camera follows the authoritative player root without an artwork offset")
	var background_layer := overworld.get_node("BackgroundLayer") as CanvasLayer
	_check(background_layer.layer < 0 and not background_layer.follow_viewport_enabled, "dark background is viewport-fixed behind the world")
	_check(player.test_move(player.global_transform, Vector2.LEFT * 16.0), "blocked tile contributes live physics geometry")
	_check(not player._try_begin_step(Vector2i.LEFT), "grid check rejects blocked destination")
	_check(player.facing == Vector2i.LEFT, "blocked direction still changes facing")
	_check(player_body.animation == &"walk_left" and player_body.frame == 0 and not player_body.is_playing(), "blocked movement remains in the facing neutral pose")
	await _test_edge_barriers(overworld, player)

	var open_run := _find_open_horizontal_run(overworld)
	_check(not open_run.is_empty(), "painted collision map contains an open three-cell movement route")
	if open_run.is_empty():
		overworld.queue_free()
		return
	player.configure(overworld.collision_grid, overworld.npc, open_run[0], Vector2i.RIGHT)
	player.step_duration = 0.01
	var landing_frames: Array[int] = []
	player.step_finished.connect(func(_cell: Vector2i): landing_frames.append(player_body.frame))
	_check(player._try_begin_step(Vector2i.RIGHT), "open grid step begins")
	_check(player_body.animation == &"walk_right" and not player_body.is_playing() and not player_body.flip_h, "right step uses explicitly selected unmirrored gait frames")
	var mid_step_tap := InputEventAction.new()
	mid_step_tap.action = "move_up"
	mid_step_tap.pressed = true
	player._unhandled_input(mid_step_tap)
	_check(player.facing == Vector2i.RIGHT and player_body.animation == &"walk_right", "mid-step direction tap does not change facing or animation")
	for index in range(8):
		await get_tree().physics_frame
	_check(player.grid_cell == open_run[1] and player.is_grid_idle(), "released mid-step tap does not queue another step")
	_check(player.position == player.cell_center(open_run[1]), "completed movement lands exactly at its original destination")
	_check(landing_frames == [2], "single movement lands on persistent neutral 0003")

	var open_cross := _find_open_cross(overworld)
	player.configure(overworld.collision_grid, overworld.npc, open_cross + Vector2i.LEFT, Vector2i.RIGHT)
	player.step_duration = 0.01
	_check(player._try_begin_step(Vector2i.RIGHT), "step toward held-direction test boundary begins")
	Input.action_press("move_up")
	for index in range(8):
		await get_tree().physics_frame
		if player.grid_cell == open_cross:
			break
	Input.action_release("move_up")
	_check(player.grid_cell == open_cross and player.target_cell == open_cross + Vector2i.UP, "direction held at landing begins the next step")
	_check(player.facing == Vector2i.UP and player_body.animation == &"walk_up", "held direction changes facing only at the step boundary")

	player.configure(overworld.collision_grid, overworld.npc, open_run[0], Vector2i.RIGHT)
	player._advance_gait_from_displacement(8.25)
	_check(player.gait_phase == 1 and is_equal_approx(player.walking_distance_accumulator, 0.25), "actual displacement advances gait and preserves threshold remainder")
	player._settle_gait_to_neutral()
	_check(player.gait_phase == 2 and player_body.frame == 1, "stride A settles logically to neutral B before the next sprite sync")
	player._sync_animation()
	_check(player_body.frame == 2, "neutral B displays 0003 without resetting gait continuity")
	player._advance_gait_from_displacement(0.0)
	_check(player.gait_phase == 2, "zero collision displacement does not advance gait")
	player._advance_gait_from_displacement(8.0)
	_check(player.gait_phase == 3, "movement after neutral B advances to the opposite stride")
	player._settle_gait_to_neutral()
	player._sync_animation()
	_check(player.gait_phase == 0 and player_body.frame == 0, "stride B settles to persistent neutral A")

	player.configure(overworld.collision_grid, overworld.npc, open_run[0], Vector2i.DOWN)
	var turn_origin := player.position
	player._begin_turn(Vector2i.RIGHT)
	_check(player.movement_state == player.MovementState.TURNING and player.position == turn_origin, "new standstill direction enters TURNING without translation")
	_check(player.facing == Vector2i.RIGHT and player_body.frame == 1, "turn-in-place visibly uses the upcoming stride frame")
	player._finish_turn()
	_check(player.is_grid_idle() and player.position == turn_origin and player_body.frame == 0, "direction tap settles stationary in the new facing neutral")
	_check(camera.get_screen_center_position().is_equal_approx(player.global_position), "camera remains centered on the player after movement")
	player.configure(overworld.collision_grid, overworld.npc, Vector2i(1, 1), Vector2i.RIGHT)
	await get_tree().process_frame
	_check(camera.get_screen_center_position().is_equal_approx(player.global_position), "camera does not clamp at the map edge")

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
	var frame := main.active_content.get_node("OverworldFrame") as SubViewportContainer
	var viewport := frame.get_node("OverworldViewport") as SubViewport
	var window_size := Vector2i(main.get_viewport().get_visible_rect().size)
	var expected_scale := maxi(1, floori(float(window_size.y) / GameFlow.TARGET_OVERWORLD_LOGICAL_SIDE))
	var expected_logical_side := maxi(1, floori(float(window_size.y) / expected_scale))
	var expected_frame_side := expected_logical_side * expected_scale
	_check(frame.position.y == floori((window_size.y - expected_frame_side) * 0.5), "overworld minimizes vertical remainder")
	_check(frame.position.x == floori((window_size.x - expected_frame_side) * 0.5), "overworld centers its side letterboxing")
	_check(frame.size == Vector2(expected_frame_side, expected_frame_side), "overworld frame remains square")
	_check(frame.stretch_shrink == expected_scale, "overworld selects an integer presentation scale")
	_check(viewport.size == Vector2i(expected_logical_side, expected_logical_side), "overworld logical view adapts to the window height")
	_check(viewport.snap_2d_transforms_to_pixel, "overworld viewport snaps rendered transforms to logical pixels")
	var embedded_background := main.active_overworld.get_node("BackgroundLayer/Background") as ColorRect
	_check(embedded_background.size == Vector2(expected_logical_side, expected_logical_side), "viewport-fixed background fills the logical viewport")
	var fullscreen_layout := GameFlow.calculate_overworld_layout(Vector2i(2560, 1600))
	_check(fullscreen_layout.position == Vector2(480, 0), "2560x1600 fullscreen uses side-only letterboxing")
	_check(fullscreen_layout.frame_side == 1600, "2560x1600 fullscreen fills the complete display height")
	_check(fullscreen_layout.integer_scale == 8 and fullscreen_layout.logical_side == 200, "2560x1600 fullscreen renders a 200x200 view at 8x")
	var movement_event := InputEventAction.new()
	movement_event.action = "move_left"
	movement_event.pressed = true
	Input.parse_input_event(movement_event)
	for index in range(60):
		await get_tree().physics_frame
		if main.active_overworld.get_player_cell().x < 6:
			break
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

func _test_edge_barriers(overworld: Overworld, player: OverworldPlayer) -> void:
	var grid := overworld.collision_grid
	var edge_cell := _find_open_cross(overworld)
	_check(edge_cell != Vector2i(-1, -1), "collision map contains an open area for edge-barrier characterization")
	if edge_cell == Vector2i(-1, -1):
		return

	var north := edge_cell + Vector2i.UP
	var east := edge_cell + Vector2i.RIGHT
	var south := edge_cell + Vector2i.DOWN
	var west := edge_cell + Vector2i.LEFT
	grid.set_cell(edge_cell, grid.EDGE_SOURCE_ID, grid.atlas_coords_for_edge_mask(grid.Edge.SOUTH))
	grid.rebuild_edge_collision_geometry()
	await get_tree().physics_frame

	_check(not grid.is_cell_blocked(edge_cell), "edge-authored cell is not treated as fully blocked")
	_check(not grid.is_boundary_blocked(north, edge_cell), "south-edge-only tile can be entered from the north")
	_check(not grid.is_boundary_blocked(west, edge_cell), "south-edge-only tile can be entered laterally")
	_check(not grid.is_boundary_blocked(edge_cell, east), "south-edge-only tile can be exited laterally")
	_check(grid.is_boundary_blocked(edge_cell, south), "south edge blocks crossing from its owning cell")
	_check(grid.is_boundary_blocked(south, edge_cell), "south edge blocks the same boundary from below")
	_check(not grid.is_boundary_blocked(edge_cell, north), "other edges on a south-edge-only tile remain traversable")

	player.configure(grid, overworld.npc, north, Vector2i.DOWN)
	_check(player._try_begin_step(Vector2i.DOWN), "grid movement can enter a south-edge-only tile from above")
	player.configure(grid, overworld.npc, west, Vector2i.RIGHT)
	_check(player._try_begin_step(Vector2i.RIGHT), "grid movement can enter a south-edge-only tile laterally")
	player.configure(grid, overworld.npc, edge_cell, Vector2i.DOWN)
	_check(not player._try_begin_step(Vector2i.DOWN), "grid movement cannot cross the authored south boundary")
	_check(player.test_move(player.global_transform, Vector2.DOWN * 16.0), "south edge creates live map-space physics from above")
	player.configure(grid, overworld.npc, south, Vector2i.UP)
	_check(not player._try_begin_step(Vector2i.UP), "grid movement cannot cross the south boundary from below")
	_check(player.test_move(player.global_transform, Vector2.UP * 16.0), "south edge creates live two-sided physics from below")

	var combined_mask := grid.Edge.NORTH | grid.Edge.EAST
	grid.set_cell(edge_cell, grid.EDGE_SOURCE_ID, grid.atlas_coords_for_edge_mask(combined_mask))
	grid.rebuild_edge_collision_geometry()
	_check(grid.is_boundary_blocked(edge_cell, north), "multiple-edge tile blocks its north edge")
	_check(grid.is_boundary_blocked(east, edge_cell), "multiple-edge tile blocks its east edge from either side")
	_check(not grid.is_boundary_blocked(edge_cell, south), "multiple-edge tile leaves its unflagged south edge open")
	_check(not grid.is_boundary_blocked(edge_cell, west), "multiple-edge tile leaves its unflagged west edge open")
	_check(grid.get_node("GeneratedEdgeBarriers").get_child_count() == 2, "combined edge mask emits one physical segment per boundary")

	grid.erase_cell(edge_cell)
	grid.rebuild_edge_collision_geometry()

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

func _find_open_cross(overworld: Overworld) -> Vector2i:
	for y in range(1, OverworldCollisionGrid.GRID_SIZE.y - 1):
		for x in range(1, OverworldCollisionGrid.GRID_SIZE.x - 1):
			var center := Vector2i(x, y)
			var cells := [center, center + Vector2i.UP, center + Vector2i.RIGHT, center + Vector2i.DOWN, center + Vector2i.LEFT]
			var is_open := true
			for cell in cells:
				if overworld.collision_grid.is_cell_blocked(cell) or overworld.npc.grid_cell == cell:
					is_open = false
					break
			if is_open:
				return center
	return Vector2i(-1, -1)
