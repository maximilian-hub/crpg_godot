extends Resource
class_name ChessHandSoundSet

## Race-specific one-shot sounds made by the moving hand itself.

@export var grab: AudioStream
@export var release: AudioStream
@export_range(-40.0, 6.0, 0.5) var volume_db := 0.0
@export_range(0.0, 0.25, 0.01) var pitch_variation := 0.05
