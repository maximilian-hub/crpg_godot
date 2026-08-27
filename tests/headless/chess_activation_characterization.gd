extends Node

const LAB_SCENE := preload("res://tools/dev_chess_activation/king_activation_lab.tscn")
const AuraLabPreset := preload("res://tools/dev_chess_aura/chess_aura_lab_preset.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const ActivationPreset := preload("res://tools/dev_chess_activation/chess_activation_lab_preset.gd")

var failures := 0


func _ready() -> void:
	var aura_directory := "res://.cache/chess_aura_presets"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(aura_directory))
	var aura_path := "%s/__activation_characterization__.tres" % aura_directory
	if FileAccess.file_exists(aura_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(aura_path))
	var saved_aura: Resource = AuraLabPreset.new()
	saved_aura.display_name = "Activation Characterization Aura"
	saved_aura.aura_profile = AuraProfile.new()
	saved_aura.aura_profile.rise_speed = 73.0
	saved_aura.aura_mode = ChessAura2D.AuraMode.SQUARE_FLAME
	_check(ResourceSaver.save(saved_aura, aura_path) == OK, "Aura Lab preset fixture saves")

	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(not lab.sequence.running and lab.sequence.current_phase == lab.sequence.Phase.RESET and is_zero_approx(lab.sequence.elapsed), "Activation Lab opens paused on the inert reset frame")
	_check(lab.activation_selector.selected == 0 and lab.activation_selector.get_item_text(0) == "Unsaved defaults", "Ritual selector explicitly distinguishes defaults from saved profiles")
	_check(lab.activation_profile.climax_hand_return_duration > lab.activation_profile.crackle_hand_return_duration, "Post-climax hand return defaults slower than ordinary crackle recovery")
	var curve_rng := RandomNumberGenerator.new()
	curve_rng.seed = 123
	var curved_path: PackedVector2Array = lab.lightning._make_path(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, 0.0, curve_rng, 30.0)
	var curve_midpoint := int(curved_path.size() / 2.0)
	_check(curved_path[0] == Vector2.ZERO and curved_path[curved_path.size() - 1] == Vector2(100.0, 0.0) and is_equal_approx(curved_path[curve_midpoint].y, 30.0), "Smooth lightning curve preserves endpoints and peaks at the path midpoint")
	curve_rng.seed = 123
	var straight_path: PackedVector2Array = lab.lightning._make_path(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, 0.0, curve_rng, 0.0)
	_check(is_zero_approx(straight_path[int(straight_path.size() / 2.0)].y), "Zero base curve restores a straight pre-jagged baseline")
	_check(_times_equal(lab.activation_profile.buildup_crackle_times, PackedFloat32Array([0.30, 0.78, 0.90])), "Buildup crackles default to an authored ending double-strike rhythm")
	var original_seed: int = lab.activation_profile.random_seed
	lab.sequence.restart(false)
	var schedule_before_seed_change: PackedFloat32Array = lab.sequence.crackle_schedule.duplicate()
	lab.activation_profile.random_seed += 99
	lab.sequence.restart(false)
	_check(_times_equal(lab.sequence.crackle_schedule, schedule_before_seed_change), "Random seed no longer changes authored buildup timing")
	lab.activation_profile.random_seed = original_seed
	lab.activation_profile.buildup_crackle_times = PackedFloat32Array()
	lab._refresh_crackle_editor(0)
	lab._add_buildup_crackle()
	lab._add_buildup_crackle()
	_check(_times_equal(lab.activation_profile.buildup_crackle_times, PackedFloat32Array([0.30, 0.42])), "Timeline editor adds an arbitrary sequence using the documented spacing")
	lab.crackle_time.value = 0.10
	_check(_times_equal(lab.activation_profile.buildup_crackle_times, PackedFloat32Array([0.10, 0.30])), "Editing a crackle time resorts the authored timeline")
	lab._remove_selected_crackle()
	_check(lab.activation_profile.buildup_crackle_times.size() == 1, "Timeline editor removes only the selected crackle")
	lab._remove_selected_crackle()
	_check(lab.activation_profile.buildup_crackle_times.is_empty() and lab.crackle_selector.disabled, "Removing the final crackle leaves a valid empty timeline")
	lab.activation_profile.buildup_crackle_times = PackedFloat32Array([0.30, 1.40])
	lab._refresh_crackle_editor(1)
	_check("outside buildup" in lab.crackle_selector.get_item_text(1) and "remain saved" in lab.crackle_warning.text, "Out-of-range crackles remain authored and are clearly warned about")
	lab.activation_profile.buildup_crackle_times = PackedFloat32Array([0.30, 0.78, 0.90])
	lab._refresh_crackle_editor(0)
	var aura_index := _find_metadata(lab.aura_selector, aura_path)
	_check(aura_index > 0, "Activation Lab discovers saved Aura Lab profiles")
	lab.aura_selector.select(aura_index)
	lab._load_selected_aura(aura_index)
	_check(is_equal_approx(lab.aura_profile.rise_speed, 73.0) and lab.king_aura.mode == ChessAura2D.AuraMode.SQUARE_FLAME, "Activation Lab applies the saved aura look and treatment")

	lab.sequence.elapsed = lab.activation_profile.invocation_duration * 0.5
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.silhouette_power > 0.0 and is_zero_approx(lab.hand_aura.particle_power), "Initial hand hover activates only the silhouette channel")
	lab.sequence.elapsed = lab.activation_profile.invocation_duration + lab.activation_profile.response_duration * 0.5
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.particle_power > 0.0, "Hand particles begin ramping after the initial crackle")

	lab.sequence.restart(false)
	var hover_position: Vector2 = lab.sequence.base_hand_position
	lab.sequence._fire_crackle(0)
	var fixed_king_target: Vector2 = lab.lightning.to_local(lab.preview_king.sprite.global_position)
	_check(lab.lightning.points[lab.lightning.points.size() - 1] == fixed_king_target, "Response-opening crackle uses the original fixed King target")
	lab.sequence._fire_crackle(99)
	var crackle_position: Vector2 = lab.preview_hand.position
	_check(crackle_position != hover_position, "A crackle blinks the hand toward the King Piece")
	_check(crackle_position == crackle_position.round(), "Lightning hand motion remains pixel-aligned")
	var sampled_target_a: Vector2 = lab.sequence._king_target_for_seed(1234)
	var sampled_target_b: Vector2 = lab.sequence._king_target_for_seed(1235)
	_check(not lab.sequence.king_target_points.is_empty() and sampled_target_a == lab.sequence._king_target_for_seed(1234), "King impact targets sample opaque pixels deterministically")
	_check(sampled_target_a != sampled_target_b, "Independent crackle seeds can target different parts of the King Piece")
	_check(not lab.lightning.main_rift_segments.is_empty() and lab.lightning.main_rift_segments[0].size() == 4, "Lightning builds triangulation-safe jagged rift strips")
	_check(lab.lightning.rift_material.shader.resource_path == "res://effects/chess_lightning_rift.gdshader", "Lightning rifts use the stationary checkerboard shader")
	_check(lab.lightning.impact_paths.size() == lab.activation_profile.impact_bolt_count, "Every strike creates the configured number of radial hit bolts")
	var impact_origin: Vector2 = lab.lightning.points[lab.lightning.points.size() - 1]
	var impact_radii_valid := true
	var impact_tapers_valid := true
	for impact_index in range(lab.lightning.impact_paths.size()):
		var impact_path: PackedVector2Array = lab.lightning.impact_paths[impact_index]
		var radius := impact_path[impact_path.size() - 1].distance_to(impact_origin)
		impact_radii_valid = impact_radii_valid and impact_path[0] == impact_origin and radius >= lab.activation_profile.impact_radius_min and radius <= lab.activation_profile.impact_radius_max
		var impact_segments: Array = lab.lightning.impact_rift_segments[impact_index]
		var final_strip: PackedVector2Array = impact_segments[impact_segments.size() - 1]
		impact_tapers_valid = impact_tapers_valid and final_strip[1].distance_to(final_strip[2]) <= 2.5
	_check(impact_radii_valid, "Radial hit bolts originate at impact and respect configured minimum/maximum radii")
	_check(impact_tapers_valid, "Radial hit bolts taper to pixel-sized outer points")
	lab.sequence._enter_phase(lab.sequence.Phase.CLIMAX)
	var first_beam_position: Vector2 = lab.preview_hand.position
	var first_beam_target: Vector2 = lab.lightning.points[lab.lightning.points.size() - 1]
	lab.sequence._show_climax_beam(1)
	_check(first_beam_position != hover_position and lab.preview_hand.position == first_beam_position, "Only the first climax beam shifts the hand; later beam shapes retain it")
	_check(first_beam_target == fixed_king_target and lab.lightning.points[lab.lightning.points.size() - 1] == fixed_king_target, "All climax redraws use the original fixed King target")
	_check(lab.lightning.branch_rift_segments.size() == lab.activation_profile.beam_branch_count, "Climax branches use the same checker-filled rift geometry")
	var tremor_boundaries: PackedFloat32Array = lab.sequence._phase_boundaries()
	lab.sequence.elapsed = tremor_boundaries[3]
	lab.sequence.tremor_offset = Vector2(2.0, 1.0)
	lab.sequence.last_tremor_tick = int(floor((lab.sequence.elapsed - tremor_boundaries[2]) / lab.activation_profile.tremor_interval))
	lab.sequence._update_tremor()
	lab.sequence._update_hand_motion()
	var trembling_climax_position: Vector2 = lab.preview_hand.position
	lab.sequence._show_climax_beam(2)
	lab.sequence._update_hand_motion()
	_check(lab.sequence.tremor_offset == Vector2(2.0, 1.0) and lab.preview_hand.position == trembling_climax_position, "Climax sustains additive tremor across successive beam redraws")
	lab.sequence.current_phase = lab.sequence.Phase.AFTERIMAGE
	lab.sequence._update_tremor()
	_check(lab.sequence.tremor_offset == Vector2.ZERO, "Afterimage entry clears climax tremor before the slower hand return")
	lab.sequence.restart(false)

	for property_name in ["invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "resolve_duration"]:
		lab.activation_profile.set(property_name, 0.06)
	lab.activation_profile.buildup_crackle_times = PackedFloat32Array([0.02, 0.04, 0.20])
	lab.activation_profile.crackle_duration = 0.02
	var phases: Array[int] = []
	var cues: Array[StringName] = []
	lab.sequence.phase_changed.connect(func(phase: int): phases.append(phase))
	lab.sequence.audio_cue.connect(func(cue: StringName): cues.append(cue))
	lab.sequence.restart(false)
	lab.sequence.set_playback_speed(4.0)
	lab.sequence.play()
	var timeout := 2.0
	while lab.sequence.current_phase != lab.sequence.Phase.COMPLETE and timeout > 0.0:
		await get_tree().process_frame
		timeout -= get_process_delta_time()
	_check(timeout > 0.0, "Activation ritual reaches completion")
	for expected_phase in [lab.sequence.Phase.INVOCATION, lab.sequence.Phase.RESPONSE, lab.sequence.Phase.BUILDUP, lab.sequence.Phase.CLIMAX, lab.sequence.Phase.AFTERIMAGE, lab.sequence.Phase.COMPLETE]:
		_check(expected_phase in phases, "Activation ritual enters phase %s" % lab.sequence.Phase.keys()[expected_phase])
	_check(&"hand_hum" in cues and &"king_hum" in cues and &"crackle" in cues and &"beam" in cues and &"resolve" in cues, "Activation ritual exposes every planned audio hook")
	_check(cues.count(&"crackle") == 3, "Response crackle and in-range authored buildup crackles fire while overflow timing remains stored and silent")
	_check(is_equal_approx(lab.preview_king.sprite.self_modulate.a, 1.0) and not lab.stone_sprite.visible, "Completion leaves the authored army-colored king revealed")
	_check(is_equal_approx(lab.king_aura.silhouette_power, lab.activation_profile.resting_aura_power) and is_equal_approx(lab.king_aura.particle_power, lab.activation_profile.resting_particle_power) and is_zero_approx(lab.hand_aura.power) and lab.lightning.points.is_empty(), "Completion retains the King's independently configured resting aura channels")
	_check(lab.preview_hand.position == lab.sequence.base_hand_position, "Completion clears integer-pixel hand tremor")

	lab.sequence.restart(false)
	_check(is_zero_approx(lab.preview_king.sprite.self_modulate.a) and lab.stone_sprite.visible, "Restart returns exactly to inert stone")
	lab.sequence.play()
	await get_tree().create_timer(0.03).timeout
	lab.sequence.pause()
	var paused_time: float = lab.sequence.elapsed
	var paused_particles: int = lab.hand_aura.active_particle_count() + lab.king_aura.active_particle_count()
	await get_tree().create_timer(0.06).timeout
	_check(is_equal_approx(lab.sequence.elapsed, paused_time), "Pause freezes ritual time")
	_check(lab.hand_aura.active_particle_count() + lab.king_aura.active_particle_count() == paused_particles, "Pause freezes aura particles")

	var activation_resource: Resource = ActivationPreset.new()
	activation_resource.display_name = "Round Trip Ritual"
	activation_resource.activation_profile = lab.activation_profile.duplicate(true)
	activation_resource.aura_preset_path = aura_path
	activation_resource.aura_preset_name = saved_aura.display_name
	activation_resource.aura_snapshot = lab.aura_profile.duplicate(true)
	activation_resource.king_type_id = &"necromancer_king"
	activation_resource.army_color = "black"
	activation_resource.hand_grip_x_offset = -64.0
	var activation_path := "user://chess_activation_characterization.tres"
	_check(ResourceSaver.save(activation_resource, activation_path) == OK, "Activation profile serializes with an embedded Aura fallback")
	var loaded: Resource = ResourceLoader.load(activation_path, "ChessActivationLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.get_script() == ActivationPreset and loaded.is_supported() and loaded.aura_snapshot != null and loaded.king_type_id == &"necromancer_king" and is_equal_approx(loaded.hand_grip_x_offset, -64.0) and _times_equal(loaded.activation_profile.buildup_crackle_times, PackedFloat32Array([0.02, 0.04, 0.20])), "Activation profile round-trips authored crackle timing, preview offsets, Aura reference, and fallback state")

	lab.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aura_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activation_path))
	if failures == 0:
		print("CHESS ACTIVATION CHARACTERIZATION: PASS")
	else:
		printerr("CHESS ACTIVATION CHARACTERIZATION: FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _find_metadata(option: OptionButton, value: Variant) -> int:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value: return index
	return -1


func _times_equal(left: PackedFloat32Array, right: PackedFloat32Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not is_equal_approx(left[index], right[index]):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	printerr("FAIL: ", description)
