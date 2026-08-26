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
	var aura_index := _find_metadata(lab.aura_selector, aura_path)
	_check(aura_index > 0, "Activation Lab discovers saved Aura Lab profiles")
	lab.aura_selector.select(aura_index)
	lab._load_selected_aura(aura_index)
	_check(is_equal_approx(lab.aura_profile.rise_speed, 73.0) and lab.king_aura.mode == ChessAura2D.AuraMode.SQUARE_FLAME, "Activation Lab applies the saved aura look and treatment")

	for property_name in ["invocation_duration", "response_duration", "buildup_duration", "climax_duration", "afterimage_duration", "resolve_duration"]:
		lab.activation_profile.set(property_name, 0.06)
	lab.activation_profile.secondary_crackle_count = 2
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
	_check(is_equal_approx(lab.preview_king.sprite.self_modulate.a, 1.0) and not lab.stone_sprite.visible, "Completion leaves the authored army-colored king revealed")
	_check(is_zero_approx(lab.king_aura.power) and is_zero_approx(lab.hand_aura.power) and lab.lightning.points.is_empty(), "Completion clears continuous aura emission and lightning")
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
	var activation_path := "user://chess_activation_characterization.tres"
	_check(ResourceSaver.save(activation_resource, activation_path) == OK, "Activation profile serializes with an embedded Aura fallback")
	var loaded: Resource = ResourceLoader.load(activation_path, "ChessActivationLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded.get_script() == ActivationPreset and loaded.is_supported() and loaded.aura_snapshot != null and loaded.king_type_id == &"necromancer_king", "Activation profile round-trips ritual, preview, Aura reference, and fallback state")

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


func _check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	printerr("FAIL: ", description)

