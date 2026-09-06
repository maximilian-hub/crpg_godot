extends Node

const ScreenShake := preload("res://scripts/view/chess_screen_shake.gd")
const ScreenShakeProfile := preload("res://scripts/view/chess_screen_shake_profile.gd")
const DeathProfile := preload("res://scripts/view/chess_king_death_profile.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const DeathLabScene := preload("res://tools/dev_chess_king_death/chess_king_death_lab.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.offset = Vector2(3, 5)
	add_child(layer)
	var item := Node2D.new()
	item.position = Vector2(10, 20)
	add_child(item)
	var shake := ScreenShake.new()
	add_child(shake)
	shake.configure([layer], [item])

	var profile := ScreenShakeProfile.new()
	profile.duration = 1.0
	profile.horizontal_pixels = 6
	profile.vertical_pixels = 4
	profile.initial_kick_multiplier = 2.0
	profile.step_interval = 0.1
	profile.falloff_exponent = 2.0
	profile.random_seed = 44
	shake.play(profile)
	var initial := shake.current_offset
	_check(initial == initial.round() and initial != Vector2.ZERO, "impact begins with a nonzero whole-pixel kick")
	_check(layer.offset == Vector2(3, 5) + initial and item.position == Vector2(10, 20) + initial, "one logical offset moves every configured battle target together")

	var second := ScreenShake.new()
	add_child(second)
	second.configure([], [])
	second.play(profile)
	_check(second.current_offset == initial, "a profile seed reproduces the same first request")
	shake._process(0.8)
	_check(absf(shake.current_offset.x) <= 1.0 and absf(shake.current_offset.y) <= 1.0, "jitter amplitude decays inside the configured falloff envelope")
	shake._process(0.2)
	_check(shake.current_offset == Vector2.ZERO and layer.offset == Vector2(3, 5) and item.position == Vector2(10, 20), "shake completion restores exact target baselines")

	shake.maximum_combined_offset = Vector2i(3, 2)
	shake.play(profile, Vector2.RIGHT)
	shake.play(profile, Vector2.RIGHT)
	_check(shake.current_offset == Vector2(3, 0), "overlapping requests accumulate and clamp to the configured safe maximum")
	shake.cancel_all()
	_check(shake.current_offset == Vector2.ZERO and layer.offset == Vector2(3, 5), "cancelling active requests immediately restores the presentation")

	var death_profile := DeathProfile.new()
	death_profile.death_sound = null
	death_profile.screen_shake.duration = 0.73
	death_profile.screen_shake.horizontal_pixels = 11
	death_profile.screen_shake.enabled = false
	var publish_path := "user://chess_screen_shake_death_publish_test.tres"
	var publish_result: Dictionary = RuntimePublisher.publish_death_profile(death_profile, publish_path)
	var published := ResourceLoader.load(publish_path, "ChessKingDeathProfile", ResourceLoader.CACHE_MODE_IGNORE)
	_check(publish_result.ok and published != null and not published.screen_shake.enabled and is_equal_approx(published.screen_shake.duration, 0.73) and published.screen_shake.horizontal_pixels == 11, "King Death Lab publishing preserves its nested shake tuning")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(publish_path))

	var lab := DeathLabScene.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(lab.board_style.resource_path == RuntimePublisher.BOARD_RUNTIME_PATH and lab.environment_style.resource_path == RuntimePublisher.ENVIRONMENT_RUNTIME_PATH, "King Death Lab previews the currently published board and table presentation")
	var board_surface := lab.board_body.get_node("MaterialSurface") as MeshInstance2D
	_check(lab.fallback_background.z_index < lab.environment_surface.z_index and lab.environment_surface.visible and lab.environment_surface.mesh != null, "King Death Lab fallback renders beneath its visible overscanned environment")
	_check(board_surface.visible and board_surface.mesh != null and board_surface.z_index > lab.environment_surface.z_index, "King Death Lab generates a visible marble board surface above the environment")
	_check(lab.projection.rows == 8 and lab.projection.columns == 8 and lab.preview_piece.coordinate == lab.PREVIEW_KING_COORDINATE, "King Death Lab presents one selected King on an 8x8 board")
	var expected_anchor: Vector2 = lab.projection.get_piece_ground_anchor(lab.PREVIEW_KING_COORDINATE, lab.board_style.piece_forward_bias)
	_check(lab.preview_piece.position == expected_anchor and lab.preview_piece.scale == Vector2.ONE * lab._in_game_world_scale(), "King Death Lab uses the live projected ground anchor and in-game piece scale")
	var controls := lab.find_children("*", "PanelContainer", true, false)[0] as Control
	var controls_origin := controls.position
	var fallback_origin: Vector2 = lab.fallback_background.position
	lab.screen_shake._apply_offset(Vector2(5, -3))
	_check(lab.preview_world.position == Vector2(5, -3) and controls.position == controls_origin and lab.fallback_background.position == fallback_origin, "Death Lab shake moves its environment, board, King, and VFX world while fallback and controls remain stationary")
	lab.screen_shake.cancel_all()
	lab.queue_free()

	if failures.is_empty():
		print("CHESS SCREEN SHAKE CHARACTERIZATION: PASS (%d checks)" % checks)
		get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		print("CHESS SCREEN SHAKE CHARACTERIZATION: FAIL (%d/%d checks)" % [failures.size(), checks])
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
