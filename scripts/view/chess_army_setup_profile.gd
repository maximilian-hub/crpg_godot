extends Resource
class_name ChessArmySetupProfile

enum ActivatingHand { LEFT, RIGHT }

@export var left_motion: ChessSetupMotionProfile = ChessSetupMotionProfile.new()
@export var right_motion: ChessSetupMotionProfile = ChessSetupMotionProfile.new()
@export var cues: Array[ChessSetupCue] = []
@export var activating_hand := ActivatingHand.RIGHT


func motion_for(cue: ChessSetupCue) -> ChessSetupMotionProfile:
	if cue.motion_override != null:
		return cue.motion_override
	return left_motion if cue.hand_side == ChessSetupCue.HandSide.LEFT else right_motion


func ensure_standard_cues() -> void:
	if not cues.is_empty():
		return
	# Back rank first, then pawns. The king closes the right-hand performance.
	for coordinate in [Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3)]:
		cues.append(_cue(coordinate, ChessSetupCue.HandSide.LEFT))
	for coordinate in [Vector2i(7, 7), Vector2i(7, 6), Vector2i(7, 5), Vector2i(6, 7), Vector2i(6, 6), Vector2i(6, 5), Vector2i(6, 4), Vector2i(7, 4)]:
		cues.append(_cue(coordinate, ChessSetupCue.HandSide.RIGHT))


func _cue(coordinate: Vector2i, side: int) -> ChessSetupCue:
	var cue := ChessSetupCue.new()
	cue.display_coordinate = coordinate
	cue.hand_side = side
	return cue

