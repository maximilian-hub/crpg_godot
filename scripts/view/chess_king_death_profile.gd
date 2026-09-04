extends Resource
class_name ChessKingDeathProfile

@export_range(1, 8, 1) var red_blink_count := 3
@export_range(0.01, 1.0, 0.01) var blink_on_duration := 0.08
@export_range(0.01, 1.0, 0.01) var blink_off_duration := 0.06
@export_range(0.0, 2.0, 0.01) var stone_hold_duration := 0.18
@export_range(0.05, 3.0, 0.01) var stone_fade_duration := 0.70
@export_range(1, 16, 1) var rift_circle_count := 8
@export_range(1.0, 48.0, 1.0) var rift_radius := 9.0
@export_range(10.0, 1000.0, 1.0) var rift_speed := 120.0
@export_storage var rift_travel_distance := 96.0
@export_storage var rift_duration := 1.15
@export_range(1.0, 64.0, 1.0) var checker_size := 8.0
@export var death_sound: AudioStream = preload("res://assets/explosion/explosion.wav")
@export_range(-40.0, 6.0, 0.5) var sound_volume_db := -3.0
