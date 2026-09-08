extends Node

const Catalog := preload("res://scripts/view/chess_ability_presentation_catalog.gd")
const Profile := preload("res://scripts/view/chess_special_move_presentation_profile.gd")
const ProjectileProfile := preload("res://scripts/view/chess_projectile_presentation_profile.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const LabScene := preload("res://tools/dev_chess_projectile/chess_projectile_lab.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var runtime := load("res://assets/chess_ability_presentations.tres") as ChessAbilityPresentationCatalog
	var spike := runtime.find_profile(&"arakne_king", &"spike_burst") as ChessSpecialMovePresentationProfile
	_check(spike != null and spike.projectile_count == 3 and spike.projectile_profile != null, "runtime Spike Burst resolves a three-projectile special-move profile")
	_check(spike.projectile_profile.projectile_frames != null and spike.projectile_profile.rotation_offset_degrees == 0.0, "Spike Burst retains its right-facing projectile frames as the zero-rotation baseline")
	_check(spike.projectile_profile.projectile_sound != null and spike.projectile_profile.projectile_sound.resource_path == "res://assets/audio/chess/interactions/special_moves/spike_throw.wav", "every Spike Burst launch uses the published spike-throw sound")
	_check(spike.projectile_profile.impact_sound != null and spike.projectile_profile.impact_sound.resource_path == "res://assets/audio/chess/interactions/special_moves/spike_hit.wav", "every Spike Burst impact uses the published spike-hit sound")

	var target_path := "user://special_move_publish_characterization.tres"
	ResourceSaver.save(Catalog.new(), target_path)
	var authored := Profile.new()
	authored.cry_duration = 0.91
	authored.projectile_count = 3
	authored.shot_interval = 0.27
	authored.volley_tangent_offset = 23.0
	authored.projectile_profile = ProjectileProfile.new()
	authored.projectile_profile.travel_speed = 777.0
	authored.projectile_profile.impact_scale = 1.75
	var result: Dictionary = RuntimePublisher.publish_special_move_profile(&"arakne_king", &"spike_burst", authored, target_path)
	var published_catalog := ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ChessAbilityPresentationCatalog
	var published := published_catalog.find_profile(&"arakne_king", &"spike_burst") as ChessSpecialMovePresentationProfile
	_check(result.ok and published != null and is_equal_approx(published.cry_duration, 0.91) and is_equal_approx(published.shot_interval, 0.27) and is_equal_approx(published.volley_tangent_offset, 23.0), "publishing preserves invocation, volley timing, and tangent spread")
	_check(is_equal_approx(published.projectile_profile.impact_scale, 1.75) and is_equal_approx(published.projectile_profile.travel_speed, 777.0), "publishing preserves nested procedural-impact and projectile tuning")
	_check(ChessSpecialMoveDirector.shot_tangent_offset(0, 3, 12.0) == -12.0 and ChessSpecialMoveDirector.shot_tangent_offset(1, 3, 12.0) == 12.0 and ChessSpecialMoveDirector.shot_tangent_offset(2, 3, 12.0) == 0.0, "three-shot volleys use deterministic opposite-side lanes followed by the true aim line")

	var lab := LabScene.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(lab.profile is ChessSpecialMovePresentationProfile and lab.source != null and lab.target != null, "Special Move Lab loads the published profile with an in-game-scale source and target")
	lab.profile.cry_duration = 0.0
	lab.profile.wiggle_blink_count = 0
	lab.profile.shot_interval = 0.0
	lab.profile.resolved_projectile_profile().travel_speed = 1.0
	lab._play()
	await get_tree().process_frame
	lab._reset_preview()
	await get_tree().process_frame
	_check(not lab.running and not is_instance_valid(lab.active_director) and lab.board.find_children("*", "ChessProjectileEffect", true, false).is_empty() and is_instance_valid(lab.source) and is_instance_valid(lab.target), "Special Move Lab reset cancels every overlapping flight and restores a ready preview")
	lab.queue_free()

	if failures.is_empty():
		print("CHESS SPECIAL MOVE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("CHESS SPECIAL MOVE CHARACTERIZATION: FAIL (", failures.size(), " failures)")
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
