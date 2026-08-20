extends Resource
class_name ChessBoardSoundSet

## Temporary universal interaction sounds for the physical board and pieces.
## A future resolver can replace these defaults using piece and board materials.

@export var default_capture_pickup: AudioStream
@export var default_place: AudioStream
@export var default_slide: AudioStream
@export_range(-40.0, 6.0, 0.5) var volume_db := 0.0
@export_range(0.0, 0.25, 0.01) var pitch_variation := 0.05
@export_range(0.0, 0.25, 0.01) var slide_fade_duration := 0.05

