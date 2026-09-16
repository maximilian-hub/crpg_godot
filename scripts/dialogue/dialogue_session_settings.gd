extends RefCounted
class_name DialogueSessionSettings

signal changed(setting: StringName, value: Variant)

var player_speed_multiplier := 1.0
var instant_text := false
var animated_text_enabled := true
var reduced_motion := false
var voice_enabled := true
var ui_sounds_enabled := true


func set_player_speed(value: float) -> void:
	player_speed_multiplier = maxf(0.01, value)
	changed.emit(&"player_speed_multiplier", player_speed_multiplier)


func set_instant_text(value: bool) -> void:
	instant_text = value
	changed.emit(&"instant_text", value)


func set_animated_text_enabled(value: bool) -> void:
	animated_text_enabled = value
	changed.emit(&"animated_text_enabled", value)


func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	changed.emit(&"reduced_motion", value)


func set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	changed.emit(&"voice_enabled", value)


func set_ui_sounds_enabled(value: bool) -> void:
	ui_sounds_enabled = value
	changed.emit(&"ui_sounds_enabled", value)
