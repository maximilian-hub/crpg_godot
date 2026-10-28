extends RefCounted
class_name ChessAiPlan

var action: ChessPrimaryAction
var score := 0.0
var analyzed_leaf_count := 0
var brain_id: StringName = &"ryck"
var search_profile: Dictionary = {}
var candidates: Array[Dictionary] = []


func _init(p_action: ChessPrimaryAction = null) -> void:
	action = p_action
