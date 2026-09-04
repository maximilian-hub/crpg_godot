extends Resource
class_name ChessMagicalMoveProfile

## Brief, repeatable choreography for a King that moves under its own power.
@export var hand_hover_offset := Vector2(150.0, -180.0)
@export_storage var gesture_corridor_clearance := 96.0 # Legacy field; the authored hover is now the universal lock point.
@export_range(0.0, 300.0, 1.0) var gesture_sweep_distance := 72.0
@export_range(0.0, 1.0, 0.01) var gesture_lock_duration := 0.06
@export_storage var gesture_curve_bend := 0.0 # Legacy serialized field; swipes are now deliberately straight.
@export_storage var gesture_exit_momentum := 110.0 # Legacy field; exit velocity is derived for a seamless join.
@export_range(0.01, 2.0, 0.01) var hand_approach_duration := 0.24
@export_storage var invocation_duration := 0.14 # Legacy split duration; replaced by gesture_duration.
@export_range(0.0, 1.0, 0.01) var settle_duration := 0.10
@export_storage var hand_retreat_duration := 0.24 # Legacy split duration; replaced by gesture_duration.
@export_range(0.02, 3.0, 0.01) var gesture_duration := 0.38
@export_range(0.0, 3.0, 0.01) var king_move_delay := 0.20
# Relative arc-length speed weights; duration controls absolute playback time.
# Runtime clamps turn speed to remain no greater than launch or exit speed.
@export_range(0.05, 8.0, 0.05) var gesture_launch_speed := 2.0
@export_range(0.05, 8.0, 0.05) var gesture_turn_speed := 0.35
@export_range(0.05, 8.0, 0.05) var gesture_exit_speed := 2.0
@export_storage var gesture_curve_forward_reach := 110.0 # Legacy Bezier handle; replaced by minimum turn radius.
@export_range(1.0, 600.0, 1.0) var gesture_minimum_turn_radius := 225.0
@export_range(0.01, 2.0, 0.01) var travel_duration := 0.30
@export_range(0.0, 160.0, 1.0) var lift_height := 34.0
@export_range(0.0, 1.0, 0.01) var hand_silhouette_power := 0.45
@export_range(0.0, 1.0, 0.01) var hand_particle_power := 0.20
@export_range(0.0, 1.0, 0.01) var king_silhouette_power := 0.65
@export_range(0.0, 1.0, 0.01) var king_particle_power := 0.35
@export_range(0.01, 2.0, 0.01) var attack_rebound_duration := 0.24
@export_storage var knockoff_duration := 0.58 # Legacy endpoint-authored flight duration.
@export_range(0.1, 0.95, 0.01) var capture_impact_fraction := 0.70
@export_storage var knockoff_arc_height := 180.0 # Legacy endpoint-authored parabola height.
@export_storage var knockoff_side_margin := 180.0 # Legacy endpoint margin.
@export_storage var knockoff_spin_degrees := 900.0 # Legacy total rotation.
@export_range(1.0, 2000.0, 1.0) var knockoff_horizontal_speed := 650.0
@export_range(0.0, 2000.0, 1.0) var knockoff_upward_speed := 480.0
@export_range(1.0, 5000.0, 1.0) var knockoff_gravity := 1200.0
@export_range(0.0, 3600.0, 1.0) var knockoff_angular_speed := 1200.0
