extends Resource
class_name ChessScreenShakeProfile

## A position-only impact rendered in whole logical pixels. Rotation and
## interpolation are deliberately absent so nearest-neighbor artwork stays crisp.

@export var enabled := true
@export_range(0.01, 3.0, 0.01) var duration := 0.40
@export_range(0, 64, 1) var horizontal_pixels := 6
@export_range(0, 64, 1) var vertical_pixels := 4
@export_range(0.25, 4.0, 0.05) var initial_kick_multiplier := 1.5
@export_range(0.01, 0.25, 0.005) var step_interval := 0.04
## Higher values concentrate the shake near the initial impact.
@export_range(0.1, 8.0, 0.1) var falloff_exponent := 1.8
@export var random_seed := 7319

