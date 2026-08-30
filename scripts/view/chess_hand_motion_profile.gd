extends Resource
class_name ChessHandMotionProfile

## Character-specific timing and choreography for ordinary board interaction.

@export_group("Approach")
@export_range(0.01, 2.0, 0.01) var approach_duration := 0.24
@export_range(0.0, 1.0, 0.01) var approach_departure_progress := 0.45
@export_range(0.0, 256.0, 1.0) var approach_departure_lift := 96.0
@export var approach_arrival_handle := Vector2(32.0, -96.0)
@export_group("Carry")
@export_range(0.0, 1.0, 0.01) var grasp_hold_duration := 0.18
@export_range(0.01, 2.0, 0.01) var carry_duration := 0.24
@export_range(0.0, 128.0, 1.0) var jump_arc_height := 32.0
@export_range(0.01, 2.0, 0.01) var jump_carry_duration := 0.36
@export_group("Attack")
@export_range(0.01, 2.0, 0.01) var attack_slam_duration := 0.16
@export_range(0.01, 2.0, 0.01) var attack_rebound_duration := 0.28
@export_group("Capture")
@export_range(0.0, 64.0, 1.0) var capture_approach_offset := 18.0
@export_range(0.0, 128.0, 1.0) var capture_approach_arc_height := 32.0
@export_range(0.01, 2.0, 0.01) var capture_approach_duration := 0.18
@export_range(0.0, 128.0, 1.0) var capture_swipe_distance := 36.0
@export_range(0.01, 2.0, 0.01) var capture_swipe_duration := 0.18
@export var captured_piece_grip_offset := Vector2.ZERO
@export_range(-180.0, 180.0, 1.0) var captured_piece_rotation_degrees := -20.0
@export_range(0.0, 128.0, 1.0) var capture_placement_arc_height := 32.0
@export_range(0.01, 2.0, 0.01) var capture_placement_duration := 0.30
@export_group("Release")
@export_range(0.0, 1.0, 0.01) var release_hold_duration := 0.35
@export_range(0.01, 2.0, 0.01) var retreat_duration := 0.24
@export_range(0.0, 128.0, 1.0) var offscreen_margin := 8.0
@export_group("")
