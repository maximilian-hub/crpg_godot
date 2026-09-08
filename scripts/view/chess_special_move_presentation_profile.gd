extends Resource
class_name ChessSpecialMovePresentationProfile

@export_group("Invocation")
@export var cry_sound: AudioStream
@export_range(-60.0, 6.0, 0.5) var cry_volume_db := -4.0
@export_range(0.0, 5.0, 0.01) var cry_duration := 0.65
@export_range(0, 8, 1) var wiggle_blink_count := 2
@export_range(1, 12, 1) var wiggle_line_count := 4
@export_range(1.0, 128.0, 1.0) var wiggle_radius := 42.0
@export_range(1.0, 64.0, 1.0) var wiggle_length := 18.0
@export_range(1.0, 16.0, 1.0) var wiggle_width := 3.0
@export_range(0.01, 1.0, 0.01) var wiggle_on_time := 0.08
@export_range(0.0, 1.0, 0.01) var wiggle_off_time := 0.09
@export var wiggle_sound: AudioStream
@export_range(-60.0, 6.0, 0.5) var wiggle_volume_db := -8.0

@export_group("Volley")
@export_range(1, 8, 1) var projectile_count := 3
@export_range(0.0, 2.0, 0.01) var shot_interval := 0.12
@export_range(0.0, 128.0, 1.0) var volley_tangent_offset := 12.0
@export var projectile_profile: ChessProjectilePresentationProfile


func resolved_projectile_profile() -> ChessProjectilePresentationProfile:
	if projectile_profile == null:
		projectile_profile = ChessProjectilePresentationProfile.new()
	return projectile_profile
