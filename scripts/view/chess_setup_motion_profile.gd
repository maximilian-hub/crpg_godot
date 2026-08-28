extends Resource
class_name ChessSetupMotionProfile

## Tunable motion shared by one setup hand. Handle offsets are authored in
## unscaled board pixels and are mirrored automatically for the left hand.

@export_range(0.0, 2.0, 0.01) var pickup_delay := 0.12
@export_range(0.01, 4.0, 0.01) var entry_duration := 0.42
@export var entry_departure_handle := Vector2(-90.0, -180.0)
@export var entry_arrival_handle := Vector2(70.0, 110.0)
@export_range(0.0, 2.0, 0.01) var placement_hold := 0.10
@export_range(0.0, 2.0, 0.01) var release_hold := 0.12
@export_range(0.01, 4.0, 0.01) var retreat_duration := 0.34
@export var retreat_departure_handle := Vector2(60.0, 100.0)
@export var retreat_arrival_handle := Vector2(-80.0, -170.0)

