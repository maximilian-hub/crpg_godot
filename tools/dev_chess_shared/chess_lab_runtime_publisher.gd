extends RefCounted
class_name ChessLabRuntimePublisher

const AuraCatalog := preload("res://scripts/view/chess_king_aura_catalog.gd")

const KING_RUNTIME_PATH := "res://assets/chess_king_first_pass.tres"
const PLAYER_KING_RUNTIME_PATH := KING_RUNTIME_PATH
const HOOD_KING_RUNTIME_PATH := "res://assets/chess_king_hood.tres"
const KING_DEATH_RUNTIME_PATH := "res://assets/chess_king_death.tres"
const AURA_RUNTIME_PATH := "res://assets/chess_king_auras.tres"
const SETUP_RUNTIME_PATH := "res://assets/chess_setup_first_pass.tres"
const PLAYER_SETUP_RUNTIME_PATH := "res://assets/chess_setup_player_early.tres"
const HOOD_SETUP_RUNTIME_PATH := "res://assets/chess_setup_hood.tres"
const BOARD_RUNTIME_PATH := "res://assets/boards/presentations/burgundy_marble_board.tres"
const ENVIRONMENT_RUNTIME_PATH := "res://assets/boards/presentations/portable_walnut_environment.tres"


static func publish_activation_profile(
		activation_profile: ChessKingActivationProfile,
		target_path := KING_RUNTIME_PATH,
		choreography := -1
	) -> Dictionary:
	if activation_profile == null:
		return _failure("An activation profile is required.")
	var target := ResourceLoader.load(target_path, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	if target == null:
		return _failure("Could not load a King presentation profile from %s." % target_path)
	if target.movement_profile == null:
		return _failure("The runtime King profile has no magical movement profile to preserve.")
	target.activation_profile = activation_profile.duplicate(true) as ChessKingActivationProfile
	if choreography >= 0:
		target.activation_choreography = choreography
	var error := ResourceSaver.save(target, target_path)
	if error != OK:
		return _failure("Could not publish the King presentation (error %d)." % error)
	return _success(target_path, "activation ritual")


static func publish_death_profile(death_profile: Resource, target_path := KING_DEATH_RUNTIME_PATH) -> Dictionary:
	if death_profile == null:
		return _failure("A King death profile is required.")
	var published_profile: Resource = death_profile.duplicate(true)
	# Keep imported audio as an external project asset rather than embedding its
	# byte stream into the runtime .tres.
	published_profile.death_sound = death_profile.death_sound
	var error := ResourceSaver.save(published_profile, target_path)
	if error != OK:
		return _failure("Could not publish the King death profile (error %d)." % error)
	return _success(target_path, "King death profile")


static func publish_universal_movement_profile(movement_profile: Resource) -> Dictionary:
	if movement_profile == null:
		return _failure("A magical King movement profile is required.")
	var targets: Array[ChessKingPresentationProfile] = []
	for path in [PLAYER_KING_RUNTIME_PATH, HOOD_KING_RUNTIME_PATH]:
		var target := ResourceLoader.load(path, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
		if target == null:
			return _failure("Could not load a King presentation profile from %s." % path)
		targets.append(target)
	for index in range(targets.size()):
		targets[index].movement_profile = movement_profile.duplicate(true)
		var path: String = [PLAYER_KING_RUNTIME_PATH, HOOD_KING_RUNTIME_PATH][index]
		var error := ResourceSaver.save(targets[index], path)
		if error != OK:
			return _failure("Could not publish universal King movement to %s (error %d)." % [path, error])
	return {
		"ok": true,
		"message": "Published universal King movement to Player Standard and Decisive runtime assets.",
	}


static func publish_aura_profile(
		king_type_id: StringName,
		aura_profile: ChessAuraProfile,
		aura_mode: int,
		target_path := AURA_RUNTIME_PATH
	) -> Dictionary:
	var validation_error := validate_aura_profile(king_type_id, aura_profile)
	if not validation_error.is_empty():
		return _failure(validation_error)
	var target := ResourceLoader.load(target_path, "ChessKingAuraCatalog", ResourceLoader.CACHE_MODE_IGNORE)
	if target == null or target.get_script() != AuraCatalog:
		return _failure("Could not load a King aura catalog from %s." % target_path)
	var normalized := ChessPieceCatalog.normalize_type_id(king_type_id)
	target.upsert(normalized, aura_profile, aura_mode)
	var error := ResourceSaver.save(target, target_path)
	if error != OK:
		return _failure("Could not publish the %s aura (error %d)." % [normalized, error])
	return _success(target_path, "%s aura" % normalized)


static func publish_king_profile(
		aura_profile: ChessAuraProfile,
		aura_mode: int,
		activation_profile: ChessKingActivationProfile,
		target_path := KING_RUNTIME_PATH
	) -> Dictionary:
	# Compatibility helper for older callers. New lab code publishes activation
	# and type-owned auras independently.
	if aura_profile == null:
		return _failure("An Aura profile is required.")
	var target := ResourceLoader.load(target_path, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	if target == null:
		return _failure("Could not load a King presentation profile from %s." % target_path)
	if activation_profile == null:
		return _failure("An activation profile is required.")
	if target.movement_profile == null:
		return _failure("The runtime King profile has no magical movement profile to preserve.")
	target.aura_profile = aura_profile.duplicate(true) as ChessAuraProfile
	target.aura_mode = clampi(aura_mode, ChessAura2D.AuraMode.SILHOUETTE, ChessAura2D.AuraMode.HYBRID)
	target.activation_profile = activation_profile.duplicate(true) as ChessKingActivationProfile
	var error := ResourceSaver.save(target, target_path)
	if error != OK:
		return _failure("Could not publish the King presentation (error %d)." % error)
	return _success(target_path)


static func publish_setup_profile(
		setup_profile: ChessArmySetupProfile,
		target_path := SETUP_RUNTIME_PATH
	) -> Dictionary:
	var validation_error := validate_setup_profile(setup_profile)
	if not validation_error.is_empty():
		return _failure(validation_error)
	var target := ResourceLoader.load(target_path, "ChessArmySetupProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessArmySetupProfile
	if target == null:
		return _failure("Could not load an army setup profile from %s." % target_path)
	target.left_motion = setup_profile.left_motion.duplicate(true) as ChessSetupMotionProfile
	target.right_motion = setup_profile.right_motion.duplicate(true) as ChessSetupMotionProfile
	target.cues.assign(setup_profile.cues.map(func(cue: ChessSetupCue): return cue.duplicate(true)))
	target.activating_hand = setup_profile.activating_hand
	target.order_mode = setup_profile.order_mode
	var error := ResourceSaver.save(target, target_path)
	if error != OK:
		return _failure("Could not publish the setup presentation (error %d)." % error)
	return _success(target_path)


static func publish_battle_presentation(
		board_style: ChessBoardVisualStyle,
		environment_style: ChessEnvironmentVisualStyle,
		board_target_path := BOARD_RUNTIME_PATH,
		environment_target_path := ENVIRONMENT_RUNTIME_PATH
	) -> Dictionary:
	var validation_error := validate_battle_presentation(board_style, environment_style)
	if not validation_error.is_empty():
		return _failure(validation_error)
	var board_target: ChessBoardVisualStyle
	if ResourceLoader.exists(board_target_path):
		board_target = ResourceLoader.load(board_target_path, "ChessBoardVisualStyle", ResourceLoader.CACHE_MODE_IGNORE) as ChessBoardVisualStyle
	if board_target == null:
		board_target = ChessBoardVisualStyle.new()
	# Board sound authoring lives outside this lab. Preserve the runtime sound set
	# rather than bundling a duplicated AudioStream graph into the .tres.
	_copy_storage_properties(board_style, board_target, [&"interaction_sounds"])
	var environment_target: ChessEnvironmentVisualStyle
	if ResourceLoader.exists(environment_target_path):
		environment_target = ResourceLoader.load(environment_target_path, "ChessEnvironmentVisualStyle", ResourceLoader.CACHE_MODE_IGNORE) as ChessEnvironmentVisualStyle
	if environment_target == null:
		environment_target = ChessEnvironmentVisualStyle.new()
	_copy_storage_properties(environment_style, environment_target)
	var board_error := ResourceSaver.save(board_target, board_target_path)
	if board_error != OK:
		return _failure("Could not publish the board style (error %d)." % board_error)
	var environment_error := ResourceSaver.save(environment_target, environment_target_path)
	if environment_error != OK:
		return _failure("Published the board style, but could not publish the environment style (error %d)." % environment_error)
	return {
		"ok": true,
		"message": "Published board to %s\nand environment to %s" % [
			ProjectSettings.globalize_path(board_target_path),
			ProjectSettings.globalize_path(environment_target_path),
		],
		"board_path": board_target_path,
		"environment_path": environment_target_path,
	}


static func validate_battle_presentation(board_style: ChessBoardVisualStyle, environment_style: ChessEnvironmentVisualStyle) -> String:
	if board_style == null or environment_style == null:
		return "Both board and environment styles are required."
	if board_style.material_surface_enabled and (board_style.light_square_texture == null or board_style.dark_square_texture == null):
		return "The material board requires both light and dark square textures."
	if board_style.frame_material_enabled and (board_style.frame_top_texture == null or board_style.frame_edge_texture == null):
		return "The material frame requires both top and edge textures."
	if environment_style.texture_enabled and environment_style.surface_texture == null:
		return "The textured environment requires a surface texture."
	return ""


static func _copy_storage_properties(source: Resource, target: Resource, excluded: Array[StringName] = []) -> void:
	for property in source.get_property_list():
		var property_name: StringName = property.name
		if property_name in [&"script", &"resource_path", &"resource_name", &"resource_local_to_scene"] or property_name in excluded:
			continue
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0:
			var value: Variant = source.get(property_name)
			# Imported project assets must remain external references. A pathless
			# nested resource here usually means an older lab instance deep-cloned it.
			if value is Resource and (value as Resource).resource_path.is_empty():
				continue
			target.set(property_name, value)


static func validate_setup_profile(profile: ChessArmySetupProfile) -> String:
	if profile == null or profile.left_motion == null or profile.right_motion == null:
		return "Both setup hand motion profiles are required."
	if profile.cues.size() != 16:
		return "Setup publishing requires exactly 16 placement cues."
	var coordinates := {}
	for cue in profile.cues:
		if cue == null:
			return "Setup publishing cannot include an empty cue."
		var coordinate: Vector2i = cue.display_coordinate
		if coordinate.x not in [6, 7] or coordinate.y < 0 or coordinate.y > 7:
			return "Every setup cue must target a legal starting square on display rows 6 or 7."
		if coordinates.has(coordinate):
			return "Setup publishing requires 16 unique starting squares."
		coordinates[coordinate] = true
	return ""


static func validate_aura_profile(king_type_id: StringName, aura_profile: ChessAuraProfile) -> String:
	if aura_profile == null:
		return "An Aura profile is required."
	var normalized := ChessPieceCatalog.normalize_type_id(king_type_id)
	if normalized not in ChessPieceCatalog.get_palette_type_ids(&"king"):
		return "'%s' is not a publishable King type." % king_type_id
	return ""


static func _success(path: String, subject := "shared game presentation") -> Dictionary:
	return {"ok": true, "message": "Published %s to %s" % [subject, ProjectSettings.globalize_path(path)]}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
