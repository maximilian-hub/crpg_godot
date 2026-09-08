extends Resource
class_name ChessProjectilePresentationProfile

@export_group("Projectile")
@export var projectile_frames: SpriteFrames
@export var projectile_animation: StringName = &"default"
@export_range(0.1, 8.0, 0.05) var projectile_scale := 1.0
@export_range(1.0, 3000.0, 1.0) var travel_speed := 520.0
@export_range(-180.0, 180.0, 1.0) var rotation_offset_degrees := 0.0
@export var launch_offset := Vector2.ZERO
@export var projectile_sound: AudioStream
@export_range(-60.0, 6.0, 0.5) var projectile_volume_db := -8.0
@export_group("Impact")
@export var impact_frames: SpriteFrames
@export var impact_animation: StringName = &"default"
@export_range(0.1, 8.0, 0.05) var impact_scale := 1.0
@export_range(0.1, 4.0, 0.05) var impact_playback_speed := 1.0
@export var impact_offset := Vector2.ZERO
@export var impact_sound: AudioStream
@export_range(-60.0, 6.0, 0.5) var impact_volume_db := -4.0
@export_range(0.0, 0.5, 0.01) var pitch_variation := 0.06
@export_group("Defeat Knockoff")
@export_range(1.0, 2000.0, 1.0) var knockoff_horizontal_speed := 650.0
@export_range(0.0, 2000.0, 1.0) var knockoff_upward_speed := 480.0
@export_range(1.0, 5000.0, 1.0) var knockoff_gravity := 1200.0
@export_range(0.0, 3600.0, 1.0) var knockoff_angular_speed := 1200.0

