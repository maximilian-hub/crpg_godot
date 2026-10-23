extends RefCounted
class_name ChessAiBrain

var player


func _init(p_player) -> void:
	player = p_player


func choose_plan(_actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	return null


func on_action_executed(_action: ChessPrimaryAction, _origin: Vector2i) -> void:
	pass


func reset_session(_reason: StringName = &"reset") -> void:
	pass
