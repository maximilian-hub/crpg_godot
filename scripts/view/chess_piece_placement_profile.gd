extends Resource
class_name ChessPiecePlacementProfile

## Character/army-owned visual imprecision for pieces placed by a hand.
## Values use the same reference-pixel space as the board's other presentation
## tuning and are projected onto the physical file/rank axes at runtime.

@export var enabled := true
@export_range(0.0, 24.0, 0.25) var max_across_error := 3.0
@export_range(0.0, 24.0, 0.25) var max_depth_error := 2.0
@export_range(0.25, 4.0, 0.05) var center_bias := 1.5


func sample_reference_offset(random: RandomNumberGenerator, error_multiplier := 1.0) -> Vector2:
	if not enabled or random == null or error_multiplier <= 0.0:
		return Vector2.ZERO
	var angle := random.randf_range(0.0, TAU)
	# Values above one favor restrained, near-center placements while retaining
	# a firm maximum error for intentionally inaccurate characters later.
	var radius := pow(random.randf(), maxf(center_bias, 0.01)) * error_multiplier
	return Vector2(
		cos(angle) * max_across_error * radius,
		sin(angle) * max_depth_error * radius
	)
