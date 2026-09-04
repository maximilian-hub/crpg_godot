extends Resource
class_name ChessKingDeathProfile

@export_range(1, 8, 1) var red_blink_count := 3
@export_range(0.01, 1.0, 0.01) var blink_on_duration := 0.08
@export_range(0.01, 1.0, 0.01) var blink_off_duration := 0.06
@export_range(0.0, 4.0, 0.01) var pre_death_hold_duration := 0.18
@export_range(0.05, 3.0, 0.01) var stone_fade_duration := 0.70
@export_range(0.01, 0.5, 0.01) var tremor_interval := 0.07
@export_range(0, 16, 1) var tremor_max_pixels := 2
@export_range(0.01, 3.0, 0.01) var tremor_slowdown_duration := 0.45
## Time from the death beat until battle flow may advance to results. This is
## deliberately independent of how long the outward rift circles remain visible.
@export_range(0.0, 10.0, 0.05) var result_delay := 3.0
@export_range(1, 16, 1) var rift_circle_count := 8
@export_range(1.0, 48.0, 1.0) var rift_radius := 9.0
@export_range(10.0, 1000.0, 1.0) var rift_speed := 120.0
@export_range(0.02, 0.5, 0.01) var rift_frame_duration := 0.10
@export_range(0.0, 0.5, 0.01) var rift_frame_growth := 0.12
## Deprecated serialized timings retained for older saved profiles.
@export_storage var stone_hold_duration := 0.18
@export_storage var rift_travel_distance := 96.0
@export_storage var rift_duration := 1.15
@export_range(1.0, 64.0, 1.0) var checker_size := 8.0
@export var death_sound: AudioStream = preload("res://assets/audio/chess/kings/death/king_death.wav")
@export_range(-40.0, 6.0, 0.5) var sound_volume_db := -3.0
