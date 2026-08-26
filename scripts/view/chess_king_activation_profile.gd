extends Resource
class_name ChessKingActivationProfile

## Timing and intensity for one King Piece awakening ritual.

@export_range(0.05, 3.0, 0.01) var invocation_duration := 0.75
@export_range(0.05, 2.0, 0.01) var response_duration := 0.45
@export_range(0.1, 5.0, 0.01) var buildup_duration := 1.25
@export_range(0.05, 2.0, 0.01) var climax_duration := 0.25
@export_range(0.05, 4.0, 0.01) var afterimage_duration := 0.90
@export_range(0.0, 2.0, 0.01) var resolve_duration := 0.20
@export_range(0.0, 1.0, 0.01) var invocation_hand_power := 0.35
@export_range(0.0, 1.0, 0.01) var response_king_power := 0.25
@export_range(0.0, 4.0, 0.05) var final_density_multiplier := 2.0
@export_range(0.0, 4.0, 0.05) var final_speed_multiplier := 2.25
@export_range(0.0, 8.0, 0.1) var burst_multiplier := 2.5
@export_range(0, 8, 1) var secondary_crackle_count := 3
@export_range(0.02, 0.5, 0.01) var crackle_duration := 0.09
@export_range(1.0, 20.0, 0.5) var crackle_width := 4.0
@export_range(1.0, 40.0, 0.5) var beam_width := 13.0
@export_range(1, 12, 1) var climax_beam_count := 4
@export_range(2.0, 32.0, 1.0) var lightning_segment_length := 10.0
@export_range(0.0, 80.0, 1.0) var lightning_displacement := 18.0
@export_range(0, 8, 1) var beam_branch_count := 3
@export_range(0.02, 0.5, 0.01) var tremor_interval := 0.07
@export_range(0, 8, 1) var tremor_max_pixels := 2
@export_range(0.0, 1.0, 0.01) var tremor_start_fraction := 0.12
@export_range(0.0, 2.0, 0.01) var hand_fade_duration := 0.22
@export var random_seed := 2808


func total_duration() -> float:
	return invocation_duration + response_duration + buildup_duration + climax_duration + afterimage_duration + resolve_duration
