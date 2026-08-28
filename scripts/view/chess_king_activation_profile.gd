extends Resource
class_name ChessKingActivationProfile

## Timing and intensity for one King Piece awakening ritual.

@export_group("Hand Entrance")
## Hover location relative to the displayed king's ground-contact origin.
## X is mirrored when the opposite hand approaches from the other side.
@export var hand_hover_offset := Vector2(180.0, 120.0)
@export_range(0.01, 4.0, 0.01) var approach_duration := 0.55
@export_range(0.0, 2.0, 0.01) var approach_settle_duration := 0.10
@export var approach_departure_handle := Vector2(-140.0, -180.0)
@export var approach_arrival_handle := Vector2(120.0, 180.0)
@export_group("Ritual")
@export_range(0.05, 3.0, 0.01) var invocation_duration := 0.75
@export_range(0.05, 2.0, 0.01) var response_duration := 0.45
@export_range(0.1, 5.0, 0.01) var buildup_duration := 1.25
@export_range(0.05, 2.0, 0.01) var climax_duration := 0.25
@export_range(0.05, 4.0, 0.01) var afterimage_duration := 0.90
@export_range(0.05, 8.0, 0.01) var aura_release_duration := 3.0
@export_range(0.0, 2.0, 0.01) var resolve_duration := 0.20
@export_range(0.0, 1.0, 0.01) var invocation_hand_power := 0.35
@export_range(0.0, 1.0, 0.01) var response_king_power := 0.25
@export_range(0.0, 4.0, 0.05) var final_density_multiplier := 2.0
@export_range(0.0, 4.0, 0.05) var final_speed_multiplier := 2.25
@export_range(0.0, 8.0, 0.1) var burst_multiplier := 2.5
## Authored seconds from the beginning of BUILDUP. The opening RESPONSE
## crackle is intentionally separate from this list.
@export var buildup_crackle_times := PackedFloat32Array([0.30, 0.78, 0.90])
## Deprecated serialized field retained so older ritual resources still load.
@export_storage var secondary_crackle_count := 3
@export_range(0.02, 0.5, 0.01) var crackle_duration := 0.09
@export_range(1.0, 20.0, 0.5) var crackle_width := 4.0
@export_range(0.0, 240.0, 1.0) var crackle_hand_shift_distance := 48.0
@export_range(0.0, 0.5, 0.01) var crackle_hand_hold_duration := 0.05
@export_range(0.01, 1.0, 0.01) var crackle_hand_return_duration := 0.16
@export_range(1.0, 40.0, 0.5) var beam_width := 13.0
@export_range(1, 12, 1) var climax_beam_count := 4
@export_range(0.0, 240.0, 1.0) var climax_hand_shift_distance := 64.0
@export_range(0.01, 2.0, 0.01) var climax_hand_return_duration := 0.45
@export_group("Hand Exit")
## Begins after the existing climax displacement has returned to hover.
@export_range(0.0, 4.0, 0.01) var post_climax_retreat_delay := 0.18
@export_range(0.01, 4.0, 0.01) var retreat_duration := 0.65
@export var retreat_departure_handle := Vector2(100.0, 140.0)
@export var retreat_arrival_handle := Vector2(-140.0, -180.0)
@export_group("Lightning")
@export_range(2.0, 32.0, 1.0) var lightning_segment_length := 10.0
@export_range(0.0, 80.0, 1.0) var lightning_displacement := 18.0
@export_range(0.0, 160.0, 1.0) var lightning_curve_max := 36.0
@export_range(1.0, 32.0, 1.0) var lightning_checker_size := 8.0
@export_range(0.0, 24.0, 0.5) var rift_edge_roughness := 3.0
@export_range(0, 8, 1) var beam_branch_count := 3
@export_range(0, 24, 1) var impact_bolt_count := 5
@export_range(0.0, 160.0, 1.0) var impact_radius_min := 18.0
@export_range(0.0, 240.0, 1.0) var impact_radius_max := 52.0
@export_range(1.0, 16.0, 0.5) var impact_bolt_width := 3.0
@export_range(0.02, 0.5, 0.01) var tremor_interval := 0.07
@export_range(0, 8, 1) var tremor_max_pixels := 2
## Deprecated: tremor now always begins with BUILDUP.
@export_storage var tremor_start_fraction := 0.0
## Below 1.0 front-loads the tremor ramp; 1.0 is linear.
@export_range(0.2, 3.0, 0.05) var tremor_ramp_exponent := 0.75
@export_range(0.0, 2.0, 0.01) var hand_fade_duration := 0.22
@export_range(0.0, 1.0, 0.01) var resting_aura_power := 0.08
@export_range(0.0, 1.0, 0.01) var resting_particle_power := 0.08
@export_range(0.0, 4.0, 0.01) var resting_density_multiplier := 1.0
@export_range(0.0, 2.0, 0.01) var resting_speed_multiplier := 0.50
@export var random_seed := 2808
@export_group("")


func total_duration() -> float:
	var entrance := approach_duration + approach_settle_duration
	var hand_exit := climax_hand_return_duration + post_climax_retreat_delay + retreat_duration
	var release_tail := maxf(maxf(afterimage_duration, aura_release_duration), hand_exit)
	return entrance + invocation_duration + response_duration + buildup_duration + climax_duration + release_tail + resolve_duration
