extends RefCounted
class_name ChessLabRuntimePublisher

const KING_RUNTIME_PATH := "res://assets/chess_king_first_pass.tres"
const SETUP_RUNTIME_PATH := "res://assets/chess_setup_first_pass.tres"


static func publish_king_profile(
		aura_profile: ChessAuraProfile,
		aura_mode: int,
		activation_profile: ChessKingActivationProfile,
		target_path := KING_RUNTIME_PATH
	) -> Dictionary:
	if aura_profile == null or activation_profile == null:
		return _failure("Aura and activation profiles are required.")
	var target := ResourceLoader.load(target_path, "ChessKingPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessKingPresentationProfile
	if target == null:
		return _failure("Could not load a King presentation profile from %s." % target_path)
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
	var error := ResourceSaver.save(target, target_path)
	if error != OK:
		return _failure("Could not publish the setup presentation (error %d)." % error)
	return _success(target_path)


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


static func _success(path: String) -> Dictionary:
	return {"ok": true, "message": "Published shared game presentation to %s" % ProjectSettings.globalize_path(path)}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
