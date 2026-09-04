extends Node

const LAB_SCENE := preload("res://tools/dev_chess_activation/king_activation_lab.tscn")
const AuraLabPreset := preload("res://tools/dev_chess_aura/chess_aura_lab_preset.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const AuraCatalog := preload("res://scripts/view/chess_king_aura_catalog.gd")
const ActivationPreset := preload("res://tools/dev_chess_activation/chess_activation_lab_preset.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")

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
	_check(not lab.preview_hand.visible and lab.preview_hand.position == lab.sequence.hand_rest_position, "Activation reset hides the hand at its off-board rest position")
	_check(lab.preview_hand is ChessHandRig and lab.hand_connection_anchor.position == lab.preview_hand.get_connection_anchor_position(), "Activation Lab uses the real hand rig and its shared source-art palm anchor")
	_check(lab.preview_hand.arm_foreground_sprite.position == Vector2(lab.preview_hand.arm_foreground_sprite.texture.get_size()) * 0.5 - lab.preview_hand.grip_anchor_pixels, "Activation Lab hand artwork uses the live rig's canonical grip origin")
	var near_hover: Vector2 = lab.sequence.base_hand_position
	lab.preview_context.seat = ChessHandRig.Seat.FAR
	lab.preview_context.loadout = lab.PreviewContext.Loadout.OPPONENT
	lab._apply_preview_context()
	_check(lab.preview_hand.seat == ChessHandRig.Seat.FAR and lab.preview_hand.hand_style.resource_path.ends_with("hood_hand_style.tres"), "Activation Lab previews the production far-seat Hood rig")
	var expected_far_hover: Vector2 = lab.preview_king.position + Vector2(-lab.activation_profile.hand_hover_offset.x, lab.activation_profile.hand_hover_offset.y)
	_check(lab.sequence.base_hand_position == expected_far_hover and lab.sequence.base_hand_position != near_hover, "Activation Lab mirrors the far hover horizontally while preserving screen-up elevation")
	_check(lab.sequence.hand_rest_position.x < 0.0 and lab.sequence.hand_rest_position.y < 0.0 and lab.sequence.mirror_hand_motion, "far activation rests upper-left and uses seat-aware motion handles")
	lab.preview_context.seat = ChessHandRig.Seat.NEAR
	lab.preview_context.loadout = lab.PreviewContext.Loadout.PLAYER
	lab._apply_preview_context()
	_check(lab.activation_selector.selected == 0 and lab.activation_selector.get_item_text(0) == "Unsaved defaults", "Ritual selector explicitly distinguishes defaults from saved profiles")
	var default_activation: Resource = lab.activation_profile.duplicate(true)
	lab.choreography_selector.select(1)
	lab._select_choreography(1)
	var hood_runtime := ResourceLoader.load(RuntimePublisher.HOOD_KING_RUNTIME_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	_check(lab.choreography_selector.get_item_text(1) == "Decisive" and lab.sequence.get_script().resource_path == "res://scripts/view/chess_hood_activation_sequence.gd" and is_equal_approx(lab.activation_profile.buildup_duration, hood_runtime.activation_profile.buildup_duration), "Decisive selector loads and previews the actual tuned runtime choreography")
	_check(lab.preview_hand.hand_style.resource_path.ends_with("hood_hand_style.tres"), "Hood choreography selection also presents the Hood hand identity")
	var decisive_cues: Array[StringName] = []
	lab.sequence.audio_cue.connect(func(cue: StringName): decisive_cues.append(cue))
	lab.sequence.restart(false)
	lab.sequence._enter_phase(lab.sequence.Phase.RESPONSE)
	_check(&"crackle" not in decisive_cues and lab.sequence.crackle_hand_started_at < 0.0 and &"king_hum" in decisive_cues, "Decisive begins its sympathetic charge without a response-opening crackle")
	var decisive_boundaries: PackedFloat32Array = lab.sequence._phase_boundaries()
	lab.sequence.elapsed = decisive_boundaries[1] + lab.activation_profile.invocation_duration * 0.5
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.particle_power > 0.0 and is_equal_approx(lab.hand_aura.particle_power, lab.hand_aura.silhouette_power), "Decisive hand particles rise with its silhouette immediately after lock-in")
	lab.sequence.elapsed = lerpf(decisive_boundaries[2], decisive_boundaries[4], 0.75)
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.speed_multiplier > 1.0 and is_equal_approx(lab.hand_aura.speed_multiplier, lab.king_aura.speed_multiplier) and is_equal_approx(lab.king_aura.particle_power, lab.king_aura.silhouette_power), "Decisive accelerates the hand and King auras sympathetically toward climax")
	lab.choreography_selector.select(0)
	lab._copy_properties(default_activation, lab.activation_profile)
	lab.preview_context.loadout = lab.PreviewContext.Loadout.PLAYER
	lab.loadout_selector.select(0)
	lab.preview_context.apply_to_hand(lab.preview_hand)
	lab._rebuild_sequence()
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

	var ritual_boundaries: PackedFloat32Array = lab.sequence._phase_boundaries()
	lab.sequence.current_phase = lab.sequence.Phase.APPROACH
	lab.sequence.elapsed = lab.activation_profile.approach_duration * 0.5
	lab.sequence._update_hand_motion()
	lab.sequence._apply_visual_state()
	_check(lab.preview_hand.position != lab.sequence.hand_rest_position and lab.preview_hand.position != lab.sequence.base_hand_position and is_zero_approx(lab.hand_aura.power), "Approach moves between rest and hover without activating the Aura")
	lab.sequence.elapsed = ritual_boundaries[1] - lab.activation_profile.approach_settle_duration * 0.5
	lab.sequence._update_hand_motion()
	_check(lab.preview_hand.position == lab.sequence.base_hand_position, "Approach settle holds the exact authored hover position")
	lab.sequence.elapsed = ritual_boundaries[1] + lab.activation_profile.invocation_duration * 0.5
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.silhouette_power > 0.0 and is_zero_approx(lab.hand_aura.particle_power), "Initial hand hover activates only the silhouette channel")
	lab.sequence.elapsed = ritual_boundaries[2] + lab.activation_profile.response_duration * 0.5
	lab.sequence._apply_visual_state()
	_check(lab.hand_aura.particle_power > 0.0, "Hand particles begin ramping after the initial crackle")
	_check(lab.king_aura.silhouette_fill > 0.0 and lab.preview_king.sprite.self_modulate.a == 0.0, "King whitening begins during response while the authored color remains dormant")
	lab.sequence.elapsed = ritual_boundaries[4] - 0.001
	lab.sequence._apply_visual_state()
	_check(lab.king_aura.silhouette_fill > 0.99 and lab.stone_sprite.visible, "King reaches white before the climax begins dissolving its stone shell")
	var king_overlay := lab.king_aura.bindings[0]["overlay"] as Sprite2D
	_check(king_overlay.z_as_relative and king_overlay.z_index > lab.stone_sprite.z_index, "white activation overlay renders above the inert stone sprite in lab and runtime")

	lab.sequence.restart(false)
	var hover_position: Vector2 = lab.sequence.base_hand_position
	lab.preview_hand.position = hover_position
	lab.preview_hand.visible = true
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
	lab.sequence.elapsed = tremor_boundaries[4]
	lab.sequence.tremor_offset = Vector2(2.0, 1.0)
	lab.sequence.last_tremor_tick = int(floor((lab.sequence.elapsed - tremor_boundaries[3]) / lab.activation_profile.tremor_interval))
	lab.sequence._update_tremor()
	lab.sequence._update_hand_motion()
	var trembling_climax_position: Vector2 = lab.preview_hand.position
	lab.sequence._show_climax_beam(2)
	lab.sequence._update_hand_motion()
	_check(lab.sequence.tremor_offset == Vector2(2.0, 1.0) and lab.preview_hand.position == trembling_climax_position, "Climax sustains additive tremor across successive beam redraws")
	lab.sequence.current_phase = lab.sequence.Phase.AFTERIMAGE
	lab.sequence._update_tremor()
	_check(lab.sequence.tremor_offset == Vector2.ZERO, "Afterimage entry clears climax tremor before the slower hand return")
	lab.sequence.elapsed = tremor_boundaries[5] + lab.activation_profile.climax_hand_return_duration
	lab.sequence._update_hand_motion()
	_check(lab.preview_hand.position == hover_position, "Existing climax recovery returns fully to hover before retreat timing begins")
	lab.sequence.elapsed += lab.activation_profile.post_climax_retreat_delay * 0.5
	lab.sequence._update_hand_motion()
	_check(lab.preview_hand.position == hover_position, "Post-climax retreat delay holds the hand at hover")
	lab.sequence.elapsed = tremor_boundaries[5] + lab.activation_profile.climax_hand_return_duration + lab.activation_profile.post_climax_retreat_delay + lab.activation_profile.retreat_duration * 0.5
	lab.sequence._update_hand_motion()
	_check(lab.preview_hand.position != hover_position and lab.preview_hand.position != lab.sequence.hand_rest_position, "Retreat follows its authored curve only after recovery and delay")
	lab.sequence.elapsed += lab.activation_profile.retreat_duration * 0.5
	lab.sequence._update_hand_motion()
	_check(lab.preview_hand.position == lab.sequence.hand_rest_position and not lab.preview_hand.visible, "Hand hides as soon as its retreat reaches the off-board rest point")
	lab.sequence.restart(false)

	for property_name in ["approach_duration", "approach_settle_duration", "invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "aura_release_duration", "climax_hand_return_duration", "post_climax_retreat_delay", "retreat_duration", "resolve_duration"]:
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
	for expected_phase in [lab.sequence.Phase.APPROACH, lab.sequence.Phase.INVOCATION, lab.sequence.Phase.RESPONSE, lab.sequence.Phase.BUILDUP, lab.sequence.Phase.CLIMAX, lab.sequence.Phase.AFTERIMAGE, lab.sequence.Phase.COMPLETE]:
		_check(expected_phase in phases, "Activation ritual enters phase %s" % lab.sequence.Phase.keys()[expected_phase])
	_check(&"hand_hum" in cues and &"king_hum" in cues and &"crackle" in cues and &"beam" in cues and &"resolve" in cues, "Activation ritual exposes every planned audio hook")
	_check(cues.count(&"crackle") == 3, "Response crackle and in-range authored buildup crackles fire while overflow timing remains stored and silent")
	_check(is_equal_approx(lab.preview_king.sprite.self_modulate.a, 1.0) and not lab.stone_sprite.visible, "Completion leaves the authored army-colored king revealed")
	_check(is_equal_approx(lab.king_aura.silhouette_power, lab.activation_profile.resting_aura_power) and is_equal_approx(lab.king_aura.particle_power, lab.activation_profile.resting_particle_power) and is_zero_approx(lab.hand_aura.power) and lab.lightning.points.is_empty(), "Completion retains the King's independently configured resting aura channels")
	_check(lab.preview_hand.position == lab.sequence.hand_rest_position and not lab.preview_hand.visible, "Completion clears tremor and hides the hand at its off-board rest position")

	lab.sequence.restart(false)
	_check(is_zero_approx(lab.preview_king.sprite.self_modulate.a) and lab.stone_sprite.visible and not lab.preview_hand.visible, "Restart returns exactly to inert stone with its hand off-board")
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
	activation_resource.activation_profile.hand_hover_offset = Vector2(-64.0, 210.0)
	activation_resource.activation_profile.approach_duration = 0.37
	activation_resource.activation_profile.post_climax_retreat_delay = 0.29
	var activation_path := "user://chess_activation_characterization.tres"
	_check(ResourceSaver.save(activation_resource, activation_path) == OK, "Activation profile serializes with an embedded Aura fallback")
	var loaded: Resource = ResourceLoader.load(activation_path, "ChessActivationLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.get_script() == ActivationPreset and loaded.is_supported() and loaded.aura_snapshot != null and loaded.king_type_id == &"necromancer_king" and loaded.activation_profile.hand_hover_offset == Vector2(-64.0, 210.0) and is_equal_approx(loaded.activation_profile.approach_duration, 0.37) and is_equal_approx(loaded.activation_profile.post_climax_retreat_delay, 0.29) and _times_equal(loaded.activation_profile.buildup_crackle_times, PackedFloat32Array([0.02, 0.04, 0.20])), "Activation profile round-trips hand paths, authored crackle timing, king-relative hover, Aura reference, and fallback state")
	loaded.schema_version = 1
	_check(loaded.is_supported(), "Version-one activation presets remain supported after the hand-path schema addition")

	var runtime_path := "user://chess_king_publish_characterization.tres"
	var runtime_seed := ChessKingPresentationProfile.new()
	runtime_seed.ensure_defaults()
	runtime_seed.movement_profile.travel_duration = 9.25
	_check(ResourceSaver.save(runtime_seed, runtime_path) == OK, "King publishing fixture saves")
	var aura_runtime_path := "user://chess_king_aura_publish_characterization.tres"
	var aura_runtime: Resource = AuraCatalog.new()
	var preserved_aura := ChessAuraProfile.new()
	preserved_aura.square_density = 33.0
	aura_runtime.upsert(&"minotaur_king", preserved_aura, ChessAura2D.AuraMode.SILHOUETTE)
	_check(ResourceSaver.save(aura_runtime, aura_runtime_path) == OK, "King Aura publishing fixture saves")
	var publish_activation := ChessKingActivationProfile.new()
	publish_activation.hand_hover_offset = Vector2(77.0, -123.0)
	publish_activation.buildup_crackle_times = PackedFloat32Array([0.11, 0.44, 0.88])
	lab._copy_properties(publish_activation, lab.activation_profile)
	lab.publish_aura_checkbox.button_pressed = false
	var publish_result: Dictionary = lab._publish_activation(runtime_path, aura_runtime_path)
	var published_runtime := ResourceLoader.load(runtime_path, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	var published_auras: Resource = ResourceLoader.load(aura_runtime_path, "ChessKingAuraCatalog", ResourceLoader.CACHE_MODE_IGNORE)
	_check(publish_result.ok and published_runtime != null and published_runtime.activation_profile.hand_hover_offset == Vector2(77.0, -123.0) and _times_equal(published_runtime.activation_profile.buildup_crackle_times, PackedFloat32Array([0.11, 0.44, 0.88])), "Publishing round-trips every nested ritual value")
	_check(is_equal_approx(published_runtime.movement_profile.travel_duration, 9.25), "Publishing a ritual preserves the existing magical movement profile")
	_check(published_auras.entries.size() == 1 and is_equal_approx(published_auras.find_entry(&"minotaur_king").aura_profile.square_density, 33.0), "Ritual-only publishing leaves the King Aura catalog unchanged")
	lab._select_king(&"necromancer_king")
	lab.aura_profile.square_density = 91.0
	lab.selected_aura_mode = ChessAura2D.AuraMode.SQUARE_FLAME
	lab.publish_aura_checkbox.button_pressed = true
	publish_result = lab._publish_activation(runtime_path, aura_runtime_path)
	published_auras = ResourceLoader.load(aura_runtime_path, "ChessKingAuraCatalog", ResourceLoader.CACHE_MODE_IGNORE)
	_check(publish_result.ok and published_auras.entries.size() == 2 and is_equal_approx(published_auras.find_entry(&"necromancer_king").aura_profile.square_density, 91.0), "Opt-in activation publishing also publishes the selected King type's universal Aura")
	_check(is_equal_approx(published_auras.find_entry(&"minotaur_king").aura_profile.square_density, 33.0), "Opt-in activation publishing preserves unrelated King Auras")
	var player_presentation := load("res://assets/player_army_presentation.tres") as ChessArmyPresentationProfile
	var opponent_presentation := load("res://assets/opponent_army_presentation.tres") as ChessArmyPresentationProfile
	var player_runtime := ResourceLoader.load(RuntimePublisher.PLAYER_KING_RUNTIME_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	hood_runtime = ResourceLoader.load(RuntimePublisher.HOOD_KING_RUNTIME_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	_check(player_presentation.king_presentation.resource_path == RuntimePublisher.PLAYER_KING_RUNTIME_PATH and player_runtime.activation_choreography == ChessKingPresentationProfile.ActivationChoreography.STANDARD_RITUAL, "player loadout consumes the independently published standard ritual")
	_check(opponent_presentation.king_presentation.resource_path == RuntimePublisher.HOOD_KING_RUNTIME_PATH and hood_runtime.activation_choreography == ChessKingPresentationProfile.ActivationChoreography.HOOD_DECISIVE, "Hood loadout consumes its decisive choreography regardless of King identity")
	_check(player_runtime.aura_catalog.resource_path == RuntimePublisher.AURA_RUNTIME_PATH and hood_runtime.aura_catalog.resource_path == RuntimePublisher.AURA_RUNTIME_PATH, "both ritual targets retain the universal King Aura catalog")

	lab.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aura_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(activation_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(runtime_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(aura_runtime_path))
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
