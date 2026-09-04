extends Node

const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const AuraCatalog := preload("res://scripts/view/chess_king_aura_catalog.gd")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")
const PIECE_SCENE := preload("res://scenes/piece.tscn")
const LAB_SCENE := preload("res://tools/dev_chess_aura/chess_aura_lab.tscn")
const LabPreset := preload("res://tools/dev_chess_aura/chess_aura_lab_preset.gd")

var failures := 0


func _ready() -> void:
	var source := Sprite2D.new()
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(2, 1, 4, 6), Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	var original_material := CanvasItemMaterial.new()
	source.material = original_material
	add_child(source)
	var standard_white := PIECE_SCENE.instantiate() as PieceView
	standard_white.set_model(Pawn.new("white", Vector2i.ZERO))
	add_child(standard_white)
	var standard_white_material := standard_white.sprite.material
	var authored_white := PIECE_SCENE.instantiate() as PieceView
	authored_white.set_model(MinotaurKing.new("white", Vector2i.ZERO))
	add_child(authored_white)

	var profile := AuraProfile.new() as ChessAuraProfile
	profile.square_density = 500.0
	profile.square_lifetime = 1.0
	profile.random_seed = 42
	var aura := Aura.new() as ChessAura2D
	aura.profile = profile
	add_child(aura)
	aura.bind_targets([source, standard_white.sprite, authored_white.sprite])

	_check(source.material == original_material, "binding does not replace the source material")
	_check(standard_white.sprite.material == standard_white_material and standard_white_material is ShaderMaterial, "binding preserves the standard White palette shader")
	_check(authored_white.sprite.material == null, "binding preserves authored White art without adding a palette material")
	_check(aura.bindings.size() == 3, "one aura accepts multiple independently layered sprite targets")
	var binding: Dictionary = aura.bindings[0]
	var overlay := binding["overlay"] as Sprite2D
	var emitter := binding["emitter"] as ChessSquareEmitter2D
	_check(overlay.get_parent() == source and emitter.get_parent() == source, "overlay and square emitter inherit the source transform and depth band")
	_check(overlay.z_as_relative and overlay.z_index == 1, "single-sprite silhouettes render above stone and palette overlays")
	_check(overlay.texture == source.texture and overlay.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "overlay mirrors the source texture with nearest filtering")
	_check(not emitter.opaque_points.is_empty(), "square flame caches opaque silhouette pixels")

	aura.set_mode(Aura.AuraMode.SILHOUETTE)
	_check(overlay.visible and not emitter.enabled, "Silhouette mode enables only the shader overlay")
	aura.set_mode(Aura.AuraMode.SQUARE_FLAME)
	_check(not overlay.visible and emitter.enabled, "Square Flame mode enables only chess-square motes")
	aura.set_mode(Aura.AuraMode.HYBRID)
	_check(overlay.visible and emitter.enabled, "Hybrid mode combines both renderers")

	aura.set_power(1.0)
	await get_tree().create_timer(0.05).timeout
	_check(is_equal_approx(aura.power, 1.0) and aura.active_particle_count() > 0, "full power drives the shader and emits square motes")
	aura.set_silhouette_power(0.25)
	aura.set_particle_power(0.75)
	_check(is_equal_approx(aura.silhouette_power, 0.25) and is_equal_approx(aura.particle_power, 0.75), "silhouette and particle power can be controlled independently")
	aura.power_down(0.0)
	_check(is_zero_approx(aura.power), "zero-duration power-down reaches its exact terminal value")
	aura.reset_effect()
	_check(aura.active_particle_count() == 0, "reset clears residual motes")
	_check(source.material == original_material and source.texture != null, "power cycling leaves source presentation unchanged")

	var hand := preload("res://scenes/player_hand_rig.tscn").instantiate() as ChessHandRig
	add_child(hand)
	await get_tree().process_frame
	var hand_aura := Aura.new() as ChessAura2D
	hand_aura.profile = profile
	add_child(hand_aura)
	hand.bind_aura(hand_aura)
	_check(hand_aura.bindings.all(func(item): return not (item["overlay"] as Sprite2D).z_as_relative and (item["overlay"] as Sprite2D).z_index < ChessHandRig.GRIP_BACK_Z), "layered hand silhouettes share one absolute layer beneath the complete hand")
	_check(hand_aura.bindings.all(func(item): return not (item["emitter"] as Node2D).z_as_relative and (item["emitter"] as Node2D).z_index > ChessHandRig.ARM_FOREGROUND_Z), "layered hand particles remain on an independent upper effect layer")
	hand_aura.clear_targets()
	hand.queue_free()

	await _test_lab_presets_and_selectors()

	if failures == 0:
		print("CHESS AURA CHARACTERIZATION: PASS")
	else:
		printerr("CHESS AURA CHARACTERIZATION: FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	failures += 1
	printerr("FAIL: ", description)


func _test_lab_presets_and_selectors() -> void:
	_check(LabPreset.safe_file_stem("  My Soulfire!  ") == "my_soulfire", "preset names become stable filesystem-safe stems")
	_check(LabPreset.safe_file_stem("../../") == "", "path traversal cannot produce a writable preset stem")
	var preset: Resource = LabPreset.new()
	preset.display_name = "Round Trip"
	preset.aura_profile = AuraProfile.new()
	preset.aura_profile.rise_speed = 77.0
	preset.aura_profile.horizontal_spread = 31.0
	preset.aura_mode = Aura.AuraMode.SQUARE_FLAME
	preset.target_mode = 1
	preset.king_power = 0.25
	preset.hand_power = 0.75
	preset.component_powers_saved = true
	preset.king_silhouette_power = 0.2
	preset.king_particle_power = 0.4
	preset.hand_silhouette_power = 0.6
	preset.hand_particle_power = 0.8
	preset.hand_grip_y_offset = 123.0
	preset.hand_grip_x_offset = -87.0
	preset.king_type_id = &"necromancer_king"
	preset.army_color = "black"
	var round_trip_path := "user://chess_aura_preset_characterization.tres"
	_check(ResourceSaver.save(preset, round_trip_path) == OK, "aura lab presets serialize as Godot resources")
	var loaded: Resource = ResourceLoader.load(round_trip_path, "ChessAuraLabPreset", ResourceLoader.CACHE_MODE_IGNORE)
	_check(
		loaded != null
		and loaded.get_script() == LabPreset
		and loaded.is_supported()
		and loaded.display_name == "Round Trip"
		and is_equal_approx(loaded.aura_profile.rise_speed, 77.0)
		and is_equal_approx(loaded.aura_profile.horizontal_spread, 31.0)
		and loaded.king_type_id == &"necromancer_king"
		and loaded.army_color == "black",
		"named presets round-trip aura tuning and complete lab preview state"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(round_trip_path))

	var lab = LAB_SCENE.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(lab.king_selector.item_count == ChessPieceCatalog.get_palette_type_ids(&"king").size(), "King selector is populated from the catalog's king group")
	lab._apply_preset(loaded)
	await get_tree().process_frame
	_check(lab.preview_king.model.type == "necromancer_king" and lab.preview_king.model.color == "black", "loading selects the saved king and army variant")
	_check(lab.mode_selector.selected == Aura.AuraMode.SQUARE_FLAME and lab.target_selector.selected == 1, "loading restores treatment and target modes")
	_check(is_equal_approx(lab.king_aura.silhouette_power, 0.2) and is_equal_approx(lab.king_aura.particle_power, 0.4) and is_equal_approx(lab.hand_aura.silhouette_power, 0.6) and is_equal_approx(lab.hand_aura.particle_power, 0.8), "loading restores independent silhouette and particle power for both targets")
	_check(is_equal_approx(lab.preview_hand.position.y, lab.HAND_PREVIEW_GRIP_POSITION.y + 123.0), "loading restores the vertical hand-grip offset")
	_check(is_equal_approx(lab.preview_hand.position.x, lab.HAND_PREVIEW_GRIP_POSITION.x - 87.0), "loading restores the horizontal hand-grip offset")
	var runtime_path := "user://chess_aura_publish_characterization.tres"
	var runtime_catalog: Resource = AuraCatalog.new()
	var original_aura := AuraProfile.new()
	original_aura.square_density = 12.0
	runtime_catalog.upsert(&"minotaur_king", original_aura, Aura.AuraMode.SILHOUETTE)
	_check(ResourceSaver.save(runtime_catalog, runtime_path) == OK, "Aura publishing fixture saves")
	lab._select_king_type(&"necromancer_king")
	lab.aura_profile.square_density = 91.0
	lab.mode_selector.select(Aura.AuraMode.SQUARE_FLAME)
	var publish_result: Dictionary = lab._publish_aura(runtime_path)
	var published: Resource = ResourceLoader.load(runtime_path, "ChessKingAuraCatalog", ResourceLoader.CACHE_MODE_IGNORE)
	_check(publish_result.ok and published.find_entry(&"necromancer_king") != null and is_equal_approx(published.find_entry(&"necromancer_king").aura_profile.square_density, 91.0) and published.find_entry(&"necromancer_king").aura_mode == Aura.AuraMode.SQUARE_FLAME, "Aura Lab publishes the current look under the selected canonical King type")
	_check(published.find_entry(&"minotaur_king") != null and is_equal_approx(published.find_entry(&"minotaur_king").aura_profile.square_density, 12.0), "Publishing one King Aura preserves other King entries")
	lab.aura_profile.square_density = 47.0
	_check(lab._publish_aura(runtime_path).ok, "Republishing a King Aura succeeds")
	published = ResourceLoader.load(runtime_path, "ChessKingAuraCatalog", ResourceLoader.CACHE_MODE_IGNORE)
	_check(published.entries.size() == 2 and is_equal_approx(published.find_entry(&"necromancer_king").aura_profile.square_density, 47.0), "Republishing replaces by King type rather than appending by profile name")
	_check(not RuntimePublisher.publish_aura_profile(&"pawn", lab.aura_profile, Aura.AuraMode.HYBRID, runtime_path).ok, "Aura publishing rejects non-King piece types")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(runtime_path))
	var game_catalog: Resource = load(RuntimePublisher.AURA_RUNTIME_PATH)
	_check(game_catalog.entries.size() == 3 and game_catalog.find_entry(&"minotaur_king") != null and game_catalog.find_entry(&"necromancer_king") != null and game_catalog.find_entry(&"arakne_king") != null, "The game Aura catalog is seeded from Minotaur, Necromancer, and Arakne authoring profiles")
	_check(game_catalog.find_entry(&"minotaur_king").aura_profile.core_color.is_equal_approx(Color(0.945312, 0.363724, 0.0147705, 1)) and game_catalog.find_entry(&"necromancer_king").aura_mode == Aura.AuraMode.SILHOUETTE, "Seeded game entries preserve the authored Aura look and treatment")
	var saved_hand_channels := Vector2(lab.hand_aura.silhouette_power, lab.hand_aura.particle_power)
	lab.preview_context.seat = ChessHandRig.Seat.FAR
	lab.preview_context.loadout = lab.PreviewContext.Loadout.OPPONENT
	lab._apply_preview_context()
	_check(lab.preview_hand.seat == ChessHandRig.Seat.FAR and lab.preview_hand.hand_style.resource_path.ends_with("hood_hand_style.tres"), "Aura Lab previews a genuine far-seat Hood hand")
	_check(lab.preview_hand.visible, "Aura Lab keeps the real preview hand visible outside animation-driven shipping defaults")
	_check(Vector2(lab.hand_aura.silhouette_power, lab.hand_aura.particle_power) == saved_hand_channels and lab.hand_aura.bindings.size() == 3, "switching Aura Lab seats rebinds one hand treatment without losing channel powers")
	lab.queue_free()
