extends Resource
class_name ChessSetupCue

enum HandSide { LEFT, RIGHT }

## Destination in player-facing display coordinates: row 7 is nearest.
@export var display_coordinate := Vector2i(7, 0)
@export var hand_side := HandSide.LEFT
@export_range(0.0, 10.0, 0.01) var gap_before := 0.08
## Null means inherit the selected hand's default motion profile.
@export var motion_override: ChessSetupMotionProfile


func label() -> String:
	return "%s %s" % ["Left" if hand_side == HandSide.LEFT else "Right", display_coordinate]

