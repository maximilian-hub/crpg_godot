@tool
extends Resource
class_name OverworldCharacterAppearance

@export var appearance_id: StringName
@export var sprite_frames: SpriteFrames
@export var mirror_left := true
@export var visual_offset := Vector2(0, -4)
