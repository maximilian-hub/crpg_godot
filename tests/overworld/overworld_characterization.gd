extends Node

const OVERWORLD := preload("res://scenes/overworld/overworld.tscn")
const MAIN := preload("res://scenes/main.tscn")
const MOBILE_CONTROLS := preload("res://scenes/ui/mobile_game_controls.tscn")
const SQUARE := preload("res://scenes/square.tscn")

var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	await _test_overworld_scene()
	await _test_mobile_controls()
	await _test_chess_square_touch()
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
	overworld.configure(Vector2i(1, 1), Vector2i.LEFT, "initial")
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
	var npc_body := overworld.npc.get_node("Body") as Sprite2D
	_check(npc_body.position == Vector2(0, -4), "NPC artwork has the visual-only vertical offset")
	_check(overworld.npc.get_node("CollisionShape2D").position == Vector2.ZERO, "NPC collision remains rooted at the gameplay position")
	_check(npc_body.texture.resource_path.ends_with("hood_down_0001.png") and not npc_body.flip_h, "NPC starts in its authored down-facing pose")
	_check(overworld.npc.encounter_profile != null and overworld.npc.encounter_profile.encounter_id == &"forest_challenger", "forest NPC owns its encounter profile")
	_check(overworld.npc.encounter_profile.opponent_hand_style.resource_path.ends_with("hood_hand_style.tres"), "forest encounter owns the Hood hand style")
	_check(overworld.npc.encounter_profile.opponent_presentation != null and overworld.npc.encounter_profile.opponent_presentation.hand_style == overworld.npc.encounter_profile.opponent_hand_style, "forest encounter owns a complete opponent presentation loadout")
	var requested_profiles: Array[ChessEncounterProfile] = []
	overworld.challenge_requested.connect(func(profile: ChessEncounterProfile): requested_profiles.append(profile))
	overworld._begin_challenge_dialogue()
	_check(requested_profiles == [overworld.npc.encounter_profile], "challenge passes the NPC encounter profile without reducing it to a global ID")
	overworld.player.set_input_enabled(true)
	var npc_cell := overworld.npc.grid_cell
	overworld.npc.face_toward(npc_cell + Vector2i.UP)
	_check(overworld.npc.facing == Vector2i.UP and npc_body.texture.resource_path.ends_with("hood_up_0001.png") and not npc_body.flip_h, "NPC uses its up-facing sprite")
	overworld.npc.face_toward(npc_cell + Vector2i.RIGHT)
	_check(overworld.npc.facing == Vector2i.RIGHT and npc_body.texture.resource_path.ends_with("hood_right_0001.png") and not npc_body.flip_h, "NPC uses its unmirrored right-facing sprite")
	overworld.npc.face_toward(npc_cell + Vector2i.LEFT)
	_check(overworld.npc.facing == Vector2i.LEFT and npc_body.texture.resource_path.ends_with("hood_right_0001.png") and npc_body.flip_h, "NPC mirrors its right-facing sprite when looking left")
	overworld.npc.face_toward(npc_cell)
	_check(overworld.npc.facing == Vector2i.LEFT and npc_body.flip_h, "NPC ignores a request to face its own cell")
	var camera := player.get_node("Camera2D") as Camera2D
	_check(camera != null and camera.enabled, "player camera is active")
	_check(camera.position == Vector2.ZERO, "camera follows the authoritative player root without an artwork offset")
	var background_layer := overworld.get_node("BackgroundLayer") as CanvasLayer
	_check(background_layer.layer < 0 and not background_layer.follow_viewport_enabled, "dark background is viewport-fixed behind the world")
	_check(player.test_move(player.global_transform, Vector2.LEFT * 16.0), "blocked tile contributes live physics geometry")
	_check(not player._try_begin_step(Vector2i.LEFT), "grid check rejects blocked destination")
	_check(player.facing == Vector2i.LEFT, "blocked direction still changes facing")
	_check(player_body.animation == &"walk_left" and player_body.frame == 0 and not player_body.is_playing(), "blocked movement remains in the facing neutral pose")
	var bump_sound := player.get_node("BumpSound") as AudioStreamPlayer
	_check(bump_sound != null and bump_sound.stream.resource_path.ends_with("bump.wav") and bump_sound.bus == &"SFX", "blocked movement uses the authored bump sound on the SFX bus")
	_check(player.blocked_walk_active and bump_sound.playing, "an initial blocked attempt immediately starts bump feedback")

	player.configure(overworld.collision_grid, overworld.npc, Vector2i(1, 1), Vector2i.LEFT)
	Input.action_press("move_left")
	_check(not player._try_begin_step(Vector2i.LEFT), "holding toward a wall starts the stationary walk cycle")
	var blocked_phase_duration := (
		player.walking_distance_per_gait_phase
		/ (float(player.CELL_SIZE) / player.step_duration)
		/ player.blocked_walk_speed_scale
	)
	player._process_blocked_walk(blocked_phase_duration * 0.99)
	_check(player_body.frame == 0 and player.position == player.cell_center(Vector2i(1, 1)), "blocked gait waits for its half-speed frame interval without translating")
	player._process_blocked_walk(blocked_phase_duration * 0.02)
	_check(player_body.frame == 1 and not player.skip_next_blocked_bump, "the first blocked frame cue is consumed by the immediate bump instead of replaying")
	player._process_blocked_walk(blocked_phase_duration)
	_check(player_body.frame == 2 and player.position == player.cell_center(Vector2i(1, 1)), "blocked frame 0003 advances without movement")
	player._process_blocked_walk(blocked_phase_duration)
	_check(player_body.frame == 3 and bump_sound.playing, "entering blocked frame 0004 replays the bump cue at an even interval")
	Input.action_release("move_left")
	player._process_blocked_walk(0.01)
	_check(not player.blocked_walk_active and player_body.frame == 0, "releasing blocked movement settles on the next neutral gait frame")

	var npc_approach_cell := overworld.npc.grid_cell + Vector2i.DOWN
	player.configure(overworld.collision_grid, overworld.npc, npc_approach_cell, Vector2i.UP)
	Input.action_press("move_up")
	_check(not player._try_begin_step(Vector2i.UP) and player.blocked_walk_active, "blocking NPCs use the same bump feedback as walls")
	Input.action_release("move_up")
	player._process_blocked_walk(0.01)
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
	await get_tree().process_frame
	_check(camera.get_screen_center_position().is_equal_approx(player.global_position), "camera remains centered on the player after movement")
	player.configure(overworld.collision_grid, overworld.npc, Vector2i(1, 1), Vector2i.RIGHT)
	await get_tree().process_frame
	_check(camera.get_screen_center_position().is_equal_approx(player.global_position), "camera does not clamp at the map edge")

	player.configure(overworld.collision_grid, overworld.npc, Vector2i(6, 6), Vector2i.UP)
	_check(overworld._can_talk_to_npc(), "idle adjacent player facing NPC can interact")
	requested_profiles.clear()
	overworld._begin_challenge_dialogue()
	_check(requested_profiles == [overworld.npc.encounter_profile], "initial challenge delegates authored pre-battle dialogue to the game flow")
	_check(overworld.player.movement_state == overworld.player.MovementState.INPUT_LOCKED, "initial challenge locks overworld movement while the shared presenter runs")
	_check(overworld.npc.facing == Vector2i.DOWN and npc_body.texture.resource_path.ends_with("hood_down_0001.png") and not npc_body.flip_h, "challenge dialogue turns the NPC toward the player")
	overworld.encounter_state = "rematchable"
	overworld.player.set_input_enabled(true)
	overworld._begin_challenge_dialogue()
	_check(requested_profiles == [overworld.npc.encounter_profile, overworld.npc.encounter_profile], "rematch also delegates authored dialogue and choice handling to the game flow")
	_check(overworld.player.movement_state == overworld.player.MovementState.INPUT_LOCKED, "rematch interaction remains locked while the shared presenter runs")
	_check(overworld.npc.facing == Vector2i.DOWN and npc_body.texture.resource_path.ends_with("hood_down_0001.png"), "NPC keeps its last facing after dialogue closes")

	overworld.queue_free()
	await get_tree().process_frame


func _test_mobile_controls() -> void:
	var controls := MOBILE_CONTROLS.instantiate() as MobileGameControls
	add_child(controls)
	controls.set_force_visible_for_testing(true)
	controls.set_gameplay_controls_requested(true)
	await get_tree().process_frame
	_check(controls.visible, "mobile controls can be forced visible for desktop verification")

	var safe_rect := Rect2(Vector2(32, 24), Vector2(1856, 1032))
	var layout := MobileGameControls.calculate_layout(Vector2(1920, 1080), safe_rect)
	var radius: float = layout.button_radius
	for action: StringName in layout.regions:
		var center: Vector2 = layout.regions[action]
		_check(safe_rect.grow(-radius).has_point(center), "mobile %s control remains inside the display safe area" % action)

	var left_center: Vector2 = controls.action_regions[&"move_left"]
	var interact_center: Vector2 = controls.action_regions[&"interact"]
	var left_touch := InputEventScreenTouch.new()
	left_touch.index = 3
	left_touch.position = left_center
	left_touch.pressed = true
	controls._input(left_touch)
	await get_tree().process_frame
	_check(Input.is_action_pressed("move_left"), "touching the mobile D-pad emits the existing movement action")
	var interact_touch := InputEventScreenTouch.new()
	interact_touch.index = 4
	interact_touch.position = interact_center
	interact_touch.pressed = true
	controls._input(interact_touch)
	await get_tree().process_frame
	_check(Input.is_action_pressed("move_left") and Input.is_action_pressed("interact"), "mobile controls preserve simultaneous direction and A-button input")
	left_touch.pressed = false
	controls._input(left_touch)
	interact_touch.pressed = false
	controls._input(interact_touch)
	await get_tree().process_frame
	_check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("interact"), "releasing touch pointers releases their mapped actions")

	left_touch.pressed = true
	controls._input(left_touch)
	await get_tree().process_frame
	controls.set_gameplay_controls_requested(false)
	controls.set_dialogue_controls_requested(false)
	await get_tree().process_frame
	_check(not controls.visible and not Input.is_action_pressed("move_left"), "hiding mobile controls safely releases held actions")
	controls.queue_free()
	await get_tree().process_frame


func _test_chess_square_touch() -> void:
	var square := SQUARE.instantiate() as SquareView
	add_child(square)
	square.coordinate = Vector2i(3, 4)
	var selected_coordinates: Array[Vector2i] = []
	square.square_clicked.connect(func(coord: Vector2i): selected_coordinates.append(coord))
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	square._on_input_event(get_viewport(), touch, 0)
	_check(selected_coordinates == [Vector2i(3, 4)], "chess squares accept a direct screen touch without mouse emulation")
	square.queue_free()
	await get_tree().process_frame

func _test_main_starts_in_overworld() -> void:
	var main: GameFlow = MAIN.instantiate()
	main.transition_duration = 0.0
	add_child(main)
	await get_tree().process_frame
	_check(main.active_overworld != null, "main starts with an overworld instance")
	_check(main.active_battle == null, "main does not start directly in battle")
	_check(main.music_controller.current_track == &"overworld", "persistent music controller starts the overworld BGM")
	var initial_music_stream := main.music_controller.player.stream as AudioStreamWAV
	_check(initial_music_stream != null and initial_music_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and initial_music_stream.loop_end > initial_music_stream.loop_begin, "overworld BGM has a valid forward loop range")
	_check(main.dialogue_presenter.get_parent() == main.get_node("DialoguePresentationLayer"), "Main owns one persistent shared dialogue presenter outside active gameplay content")
	_check(main.battle_spiral_transition.get_parent() == main, "Main owns one persistent battle-transition presenter outside active gameplay content")
	_check((main.dialogue_presenter.get_parent() as CanvasLayer).layer < (main.get_node("TransitionLayer") as CanvasLayer).layer, "shared dialogue renders above gameplay and below the transition fade")
	_check(main.active_overworld.get_player_cell() == Vector2i(6, 7), "main applies the scene-marker default player position")
	var frame := main.active_content.get_node("OverworldFrame") as SubViewportContainer
	var viewport := frame.get_node("OverworldViewport") as SubViewport
	var window_size := Vector2i(main.get_viewport().get_visible_rect().size)
	var expected_scale := maxi(1, floori(float(window_size.y) / GameFlow.TARGET_OVERWORLD_LOGICAL_SIDE)) + 2
	var expected_logical_side := maxi(1, floori(float(window_size.y) / expected_scale))
	var expected_frame_side := expected_logical_side * expected_scale
	_check(frame.position.y == floori((window_size.y - expected_frame_side) * 0.5), "overworld minimizes vertical remainder")
	_check(frame.position.x == floori((window_size.x - expected_frame_side) * 0.5), "overworld centers its side letterboxing")
	_check(frame.size == Vector2(expected_frame_side, expected_frame_side), "overworld frame remains square")
	_check(frame.stretch_shrink == expected_scale, "overworld selects an integer presentation scale")
	_check(viewport.size == Vector2i(expected_logical_side, expected_logical_side), "overworld logical view adapts to the window height")
	_check(viewport.snap_2d_transforms_to_pixel, "overworld viewport snaps rendered transforms to logical pixels")
	_check(not main.active_overworld.has_node("DialogueLayer"), "overworld no longer carries the placeholder dialogue panel")
	var embedded_background := main.active_overworld.get_node("BackgroundLayer/Background") as ColorRect
	_check(embedded_background.size == Vector2(expected_logical_side, expected_logical_side), "viewport-fixed background fills the logical viewport")
	var fullscreen_layout := GameFlow.calculate_overworld_layout(Vector2i(2560, 1600))
	_check(fullscreen_layout.position == Vector2(480, 0), "2560x1600 fullscreen uses side-only letterboxing")
	_check(fullscreen_layout.frame_side == 1600, "2560x1600 fullscreen fills the complete display height")
	_check(fullscreen_layout.integer_scale == 10 and fullscreen_layout.logical_side == 160, "2560x1600 fullscreen renders a 160x160 view at 10x")
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

	var forest_profile := main.active_overworld.npc.encounter_profile
	_check(forest_profile.pre_battle_dialogue_path == "res://content/dialogue/hood_greeting.dialog", "forest encounter owns the authored Hood introduction")
	main.active_overworld.player.configure(main.active_overworld.collision_grid, main.active_overworld.npc, Vector2i(5, 5), Vector2i.RIGHT)
	main.dialogue_presenter.session_runner.set_instant_text(true)
	main.active_overworld._begin_challenge_dialogue()
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_greeting", "initial Hood interaction opens the authored conversation in the shared presenter")
	_check(main.active_battle == null and main.active_overworld.player.movement_state == main.active_overworld.player.MovementState.INPUT_LOCKED, "battle waits for dialogue completion while overworld input remains locked")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	var dialogue_transition_timeout := 60
	while main.active_battle == null and dialogue_transition_timeout > 0:
		await get_tree().process_frame
		dialogue_transition_timeout -= 1
	_check(dialogue_transition_timeout > 0, "completing Hood's conversation releases the battle transition")
	if main.active_battle.opening_in_progress:
		main.active_battle.opening_director.finish_immediately()
		await get_tree().process_frame
	_check(main.active_overworld == null, "battle transition removes the overworld")
	_check(main.active_battle != null, "battle transition creates a chess game")
	_check(main.music_controller.current_track == &"battle", "battle BGM starts when the staged battle is revealed")
	_check(is_zero_approx(main.fade_overlay.modulate.a), "battle reveal removes the black cover as a hard cut")
	_check(is_instance_valid(main.dialogue_presenter) and main.dialogue_presenter.get_parent() == main.get_node("DialoguePresentationLayer"), "shared presenter survives the transition and remains available over chess")
	var battle_environment := main.active_content.get_node("BattleEnvironment") as ChessEnvironmentSurface
	var environment_quad := battle_environment.mesh as QuadMesh
	_check(environment_quad != null and environment_quad.size == main.get_viewport().get_visible_rect().size + Vector2(48, 36), "battle environment overscans native window space for maximum screen shake")
	_check(main.get_node("Background").z_index < battle_environment.z_index, "battle environment renders above Main's emergency flat background")
	_check(main.active_battle.battle_presentation == GameFlow.DEFAULT_BATTLE_PRESENTATION and battle_board_style(main).material_surface_enabled, "battles without an override use the promoted marble-and-walnut presentation")
	_check(main.battle_frame == null and main.battle_viewport == null, "fluid battle does not create a fixed-resolution frame")
	_check(main.active_battle.get_parent() == main.active_content, "fluid chess game renders directly in native window space")
	var battle_board := main.active_battle.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	_check(battle_board.scale_world_with_projection, "fluid battle scales its pieces and physical effects with the projected board")
	_check(is_equal_approx(battle_board.viewport_height_width_ratio, 1.0), "fluid board inherits the battle scene's large safe height profile")
	_check(is_equal_approx(battle_board.viewport_width_cap_ratio, 0.72), "fluid board inherits the battle scene's side clearance")
	var white_ui := main.active_battle.get_node("UI/WhitePlayerUIContainer") as MarginContainer
	var black_ui := main.active_battle.get_node("UI/BlackPlayerUIContainer") as MarginContainer
	_check(white_ui.anchor_right == 1.0 and white_ui.anchor_bottom == 1.0, "white battle UI uses viewport anchors")
	_check(black_ui.anchor_right == 1.0 and black_ui.anchor_top == 0.0, "black battle UI uses viewport anchors")
	_check(main.active_battle.control_mode == ChessGame.ControlMode.PLAYER_VS_CPU, "NPC battle uses player-vs-CPU mode")
	_check(main.active_battle.player_color == "white", "current NPC battle assigns the player to White")
	_check(not main.active_battle.white_cpu_player.is_enabled and main.active_battle.black_cpu_player.is_enabled, "current NPC battle assigns the CPU to Black")
	_check(main.active_battle.opponent_hand_style == forest_profile.opponent_hand_style, "NPC encounter applies its opponent hand before battle startup")
	_check(main.active_battle.opponent_presentation == forest_profile.opponent_presentation, "NPC encounter applies its opponent setup, activation, and king-magic loadout")
	var battle_canvas := main.active_battle.get_node("CanvasLayer") as CanvasLayer
	var battle_ui_root := main.active_battle.get_node("UI") as Control
	main.active_battle.screen_shake._apply_offset(Vector2(4, -3))
	_check(battle_canvas.offset == Vector2(4, -3) and battle_ui_root.position == Vector2(4, -3) and battle_environment.position == main.get_viewport().get_visible_rect().size * 0.5 + Vector2(4, -3), "fluid battle shake keeps environment, board layers, and combat UI locked to one whole-pixel offset")
	main.active_battle.screen_shake.cancel_all()
	_check(battle_board.far_hand_rig.seat == ChessHandRig.Seat.FAR and battle_board.far_hand_rig.hand_style == forest_profile.opponent_hand_style, "forest challenger uses the animated Hood rig in the far seat")
	_check(battle_board.far_hand_rig.can_animate(), "forest challenger does not fall back to piece-only sliding")
	var controller := main.active_battle.get_node("ChessController") as ChessBoardController
	var model := main.active_battle.get_node("ChessModel") as ChessBoardModel
	var click_position := battle_board.grid_to_screen(6, 0)
	var click_event := InputEventMouseButton.new()
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.position = click_position
	click_event.global_position = click_position
	click_event.pressed = true
	Input.parse_input_event(click_event)
	await get_tree().physics_frame
	click_event.pressed = false
	Input.parse_input_event(click_event)
	await get_tree().physics_frame
	_check(controller.selected_piece == model.board[6][0], "fluid native viewport routes pointer selection to projected square collision")
	controller.deselect_piece()
	var touch_event := InputEventScreenTouch.new()
	touch_event.index = 0
	touch_event.position = click_position
	touch_event.pressed = true
	Input.parse_input_event(touch_event)
	await get_tree().physics_frame
	touch_event.pressed = false
	Input.parse_input_event(touch_event)
	await get_tree().physics_frame
	_check(controller.selected_piece == model.board[6][0], "fluid native battle routes direct screen touches without mouse emulation")

	var exit_results: Array[String] = []
	var completed_battle := main.active_battle
	completed_battle.battle_exit_requested.connect(func(result: String): exit_results.append(result))
	completed_battle.automatic_exit_delay = 0.0
	completed_battle._on_battle_finished("white")
	_check(completed_battle.completed_player_result == "win", "battle maps White victory to player win")
	for index in range(4):
		await get_tree().process_frame
	_check(exit_results == ["win"], "automatic battle exit carries the player result")
	_check(main.active_overworld != null and main.active_battle == null, "completed battle returns to a fresh overworld")
	_check(main.music_controller.current_track == &"overworld", "returning beneath black restarts the overworld BGM")
	_check(main.active_overworld.get_player_cell() == Vector2i(5, 5), "return restores saved player cell")
	_check(main.active_overworld.get_player_facing() == Vector2i.RIGHT, "return restores saved facing")
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_player_win", "authored result dialogue opens automatically after return")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	main.queue_free()
	await get_tree().process_frame

	var fixed_main: GameFlow = MAIN.instantiate()
	fixed_main.transition_duration = 0.0
	fixed_main.battle_presentation_mode = GameFlow.BattlePresentationMode.FIXED_LOGICAL
	add_child(fixed_main)
	await get_tree().process_frame
	await fixed_main._transition_to_battle()
	if fixed_main.active_battle.opening_in_progress:
		fixed_main.active_battle.opening_director.finish_immediately()
		await get_tree().process_frame
	var fixed_frame := fixed_main.active_content.get_node("BattleFrame") as SubViewportContainer
	var fixed_viewport := fixed_frame.get_node("BattleViewport") as SubViewport
	var fixed_board := fixed_main.active_battle.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	_check(fixed_main.active_battle.get_parent() == fixed_viewport, "fixed comparison mode retains the logical battle viewport")
	var fixed_environment_quad := fixed_main.battle_environment.mesh as QuadMesh
	_check(fixed_environment_quad != null and fixed_environment_quad.size == fixed_main.get_viewport().get_visible_rect().size + Vector2(48, 36), "fixed comparison mode keeps an overscanned environment outside the logical battle viewport")
	fixed_main.active_battle.screen_shake._apply_offset(Vector2(2, -1))
	_check(fixed_main.battle_environment.position == fixed_main.get_viewport().get_visible_rect().size * 0.5 + Vector2(2, -1) * fixed_frame.stretch_shrink, "fixed-logical shake scales the external environment offset with the presented viewport")
	fixed_main.active_battle.screen_shake.cancel_all()
	_check(fixed_viewport.physics_object_picking, "fixed comparison viewport retains square picking")
	_check(not fixed_board.scale_world_with_projection, "fixed comparison mode leaves world assets at logical 1x")
	_check(fixed_main.active_battle.opponent_presentation != null and fixed_board.far_hand_rig.can_animate(), "battle without an encounter profile uses the scene's default opponent presentation")
	var fixed_controller := fixed_main.active_battle.get_node("ChessController") as ChessBoardController
	var fixed_model := fixed_main.active_battle.get_node("ChessModel") as ChessBoardModel
	var fixed_touch := InputEventScreenTouch.new()
	fixed_touch.index = 1
	fixed_touch.position = fixed_frame.position + fixed_board.grid_to_screen(6, 0) * float(fixed_frame.stretch_shrink)
	fixed_touch.pressed = true
	Input.parse_input_event(fixed_touch)
	await get_tree().physics_frame
	fixed_touch.pressed = false
	Input.parse_input_event(fixed_touch)
	await get_tree().physics_frame
	_check(fixed_controller.selected_piece == fixed_model.board[6][0], "fixed logical battle maps direct screen touches through its scaled SubViewport")
	var override_profile := load("res://assets/boards/presentations/legacy_flat_battle_presentation.tres") as ChessBattlePresentationProfile
	var override_encounter := ChessEncounterProfile.new()
	override_encounter.battle_presentation = override_profile
	_check(fixed_main._resolve_battle_presentation(override_encounter) == override_profile and not override_profile.board_style.material_surface_enabled and override_profile.environment_style.surface_texture.resource_path.ends_with("woodtile.png"), "encounters can select the preserved legacy presentation without changing chess rules")
	fixed_main.queue_free()
	await get_tree().process_frame


func battle_board_style(main: GameFlow) -> ChessBoardVisualStyle:
	var board := main.active_battle.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	return board.visual_style as ChessBoardVisualStyle

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
	var matched_test_boundaries := 0
	var generated_barriers := grid.get_node("GeneratedEdgeBarriers")
	for edge in [grid.Edge.NORTH, grid.Edge.EAST]:
		var expected_segment: Dictionary = grid._boundary_segment(edge_cell, edge)
		for child in generated_barriers.get_children():
			var shape := (child as CollisionShape2D).shape as SegmentShape2D
			if shape != null and shape.a == expected_segment.start and shape.b == expected_segment.end:
				matched_test_boundaries += 1
				break
	_check(matched_test_boundaries == 2, "combined edge mask emits one physical segment per boundary")

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
