extends Resource
class_name ChessHandStyle

## Character-specific artwork for a layered hand pose. Names describe render
## roles rather than anatomy, so hands approaching from either side of the board
## may place different fingers in the same depth slot.

@export var open_grip_back: Texture2D
@export var open_grip_front: Texture2D
@export var open_arm_foreground: Texture2D
@export var closed_grip_back: Texture2D
@export var closed_grip_front: Texture2D
@export var closed_arm_foreground: Texture2D
@export var sounds: ChessHandSoundSet
@export_group("Art Geometry")
@export var grip_anchor_pixels := Vector2(11.0, 29.0)
@export var connection_anchor_pixels := Vector2(23.0, 24.0)
@export_range(0.25, 8.0, 0.05) var art_scale_multiplier := 3.5
## When true, GripFront shares the active board row's depth band and can pass
## behind pieces in rows toward the viewer. Disable for foreground fingers that
## should remain above ordinary board pieces, as on the far Hood hand.
@export var grip_front_follows_board_depth := true
@export_group("Choreography")
@export var motion_profile: ChessHandMotionProfile = ChessHandMotionProfile.new()
@export_group("")


func is_complete() -> bool:
	return (
		open_grip_back != null
		and open_grip_front != null
		and open_arm_foreground != null
		and closed_grip_back != null
		and closed_grip_front != null
		and closed_arm_foreground != null
		and motion_profile != null
	)


func texture_size_warning() -> String:
	var expected := Vector2i.ZERO
	for texture in [open_grip_back, open_grip_front, open_arm_foreground, closed_grip_back, closed_grip_front, closed_arm_foreground]:
		if texture == null:
			continue
		var size := Vector2i(texture.get_size())
		if expected == Vector2i.ZERO:
			expected = size
		elif size != expected:
			return "Layer canvases differ; shared anchor coordinates must still use one aligned source space."
	return ""
