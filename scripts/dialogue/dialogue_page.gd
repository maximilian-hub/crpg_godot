extends RefCounted
class_name DialoguePage

var speaker_id := ""
var speaker_name := ""
var speaker_known := true
var initial_portrait_id := ""
var text := ""
var events: Array[DialogueEvent] = []
var choices: Array[DialogueChoice] = []
var character_speed_multipliers := PackedFloat32Array()
