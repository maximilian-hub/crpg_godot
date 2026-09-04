extends Resource
class_name ChessHandSoundSet

## Race-specific one-shot sounds made by the moving hand itself.

@export_group("Grab")
@export var grab: AudioStream
@export_range(-40.0, 6.0, 0.5) var grab_volume_db := 0.0
@export_range(0.0, 0.25, 0.01) var grab_pitch_variation := 0.05

@export_group("Release")
@export var release: AudioStream
@export_range(-40.0, 6.0, 0.5) var release_volume_db := 0.0
@export_range(0.0, 0.25, 0.01) var release_pitch_variation := 0.05
