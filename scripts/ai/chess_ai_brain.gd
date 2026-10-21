extends RefCounted
class_name ChessAiBrain

var player


func _init(p_player) -> void:
	player = p_player


func choose_plan(_actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	return null
