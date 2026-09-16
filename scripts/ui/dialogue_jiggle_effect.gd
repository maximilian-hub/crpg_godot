extends RichTextEffect
class_name DialogueJiggleEffect

var bbcode := "dialogue_jiggle"
var animation_enabled := true
var reduced_motion := false
var animation_time := 0.0
var revealed_at: Dictionary = {}


func reset() -> void:
	animation_time = 0.0
	revealed_at.clear()


func advance(delta: float) -> void:
	animation_time += maxf(0.0, delta)


func reveal_through(visible_character_count: int) -> void:
	for index in range(maxi(0, visible_character_count)):
		if not revealed_at.has(index):
			revealed_at[index] = animation_time


func offset_for(character_index: int, amplitude: float, frequency: float) -> Vector2:
	if not animation_enabled or reduced_motion or not revealed_at.has(character_index):
		return Vector2.ZERO
	var age: float = maxf(0.0, animation_time - float(revealed_at[character_index]))
	var phase := float(character_index * 37 + 11)
	var x := sin(age * frequency * TAU + phase * 0.73) * amplitude
	var y := cos(age * frequency * TAU * 1.17 + phase * 1.31) * amplitude
	return Vector2(roundf(x), roundf(y))


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var amplitude := float(char_fx.env.get("amplitude", 1.0))
	var frequency := float(char_fx.env.get("frequency", 7.0))
	char_fx.offset += offset_for(char_fx.range.x, amplitude, frequency)
	return true
