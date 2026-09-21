extends Resource
class_name DialogueSkin

@export_category("Replaceable presentation assets")
@export var complete_frame_texture: Texture2D
@export var text_panel_style: StyleBox
@export var portrait_panel_style: StyleBox
@export var name_plate_style: StyleBox
@export var text_interior_texture: Texture2D
@export var empty_portrait_texture: Texture2D
@export var continue_indicator_texture: Texture2D
@export var body_font: Font
@export var name_font: Font
@export var choice_navigation_sound: AudioStream
@export var choice_confirm_sound: AudioStream
@export var choice_cancel_sound: AudioStream
@export var choice_cursor := "▶"
@export var semantic_color_names := PackedStringArray(["emphasis", "warning", "mystery"])
@export var semantic_color_values := PackedColorArray([Color("d8c590"), Color("e87568"), Color("8fb4d9")])
@export var semantic_size_names := PackedStringArray(["small", "normal", "large"])
@export var semantic_size_values := PackedInt32Array([6, 8, 12])
@export var semantic_jiggle_names := PackedStringArray(["subtle", "standard", "strong"])
@export var semantic_jiggle_amplitudes := PackedFloat32Array([1.0, 1.0, 2.0])
@export var semantic_jiggle_frequencies := PackedFloat32Array([4.0, 7.0, 10.0])

@export_category("Dialogue voice dynamics")
@export var small_text_voice_volume_offset_db := -12.0
@export var normal_text_voice_volume_offset_db := 0.0
@export var large_text_voice_volume_offset_db := 6.0

@export_category("Logical layout")
@export var portrait_aspect_ratio := 0.75
@export var panel_height := 64
@export var panel_join_overlap := 2
@export var panel_inner_padding := 5
@export var portrait_inner_padding := 2
@export var portrait_content_insets := Vector4.ZERO
@export var text_content_insets := Vector4.ZERO
@export var body_text_offset := Vector2.ZERO
@export var name_plate_horizontal_offset := 4
@export var name_plate_size := Vector2i(92, 14)
@export var name_text_offset := Vector2(5, 0)
@export var body_font_size := 8
@export var name_font_size := 8
@export var choice_font_size := 7

@export_category("Fallback colors")
@export var body_color := Color("f0eee8")
@export var name_color := Color("191b1e")
@export var choice_color := Color("d8c590")
@export var empty_portrait_color := Color("6f757b")


func has_semantic_color(color_name: String) -> bool:
	var index := semantic_color_names.find(color_name)
	return index >= 0 and index < semantic_color_values.size()


func semantic_color(color_name: String) -> Color:
	var index := semantic_color_names.find(color_name)
	return semantic_color_values[index] if index >= 0 and index < semantic_color_values.size() else body_color


func has_semantic_size(size_name: String) -> bool:
	var index := semantic_size_names.find(size_name)
	return index >= 0 and index < semantic_size_values.size()


func semantic_size(size_name: String) -> int:
	var index := semantic_size_names.find(size_name)
	return maxi(1, semantic_size_values[index]) if index >= 0 and index < semantic_size_values.size() else body_font_size


func semantic_size_voice_volume_offset_db(size_name: String) -> float:
	match size_name:
		"small":
			return small_text_voice_volume_offset_db
		"large":
			return large_text_voice_volume_offset_db
		_:
			return normal_text_voice_volume_offset_db


func has_semantic_jiggle(jiggle_name: String) -> bool:
	var index := semantic_jiggle_names.find(jiggle_name)
	return index >= 0 and index < semantic_jiggle_amplitudes.size() and index < semantic_jiggle_frequencies.size()


func semantic_jiggle(jiggle_name: String) -> Dictionary:
	var index := semantic_jiggle_names.find(jiggle_name)
	if index < 0 or index >= semantic_jiggle_amplitudes.size() or index >= semantic_jiggle_frequencies.size():
		index = semantic_jiggle_names.find("standard")
	if index < 0 or index >= semantic_jiggle_amplitudes.size() or index >= semantic_jiggle_frequencies.size():
		return {"amplitude": 1.0, "frequency": 7.0}
	return {"amplitude": semantic_jiggle_amplitudes[index], "frequency": semantic_jiggle_frequencies[index]}
