extends RefCounted
class_name ChessAiBrain

var player


func _init(p_player) -> void:
	player = p_player


func choose_plan(_actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	return null


## Optional policy for authoritative reactions which require a square choice.
## Returning null deliberately delegates to ChessCpuPlayer's legacy chooser.
func choose_reaction_target(_model: ChessBoardModel, _calling_piece: ModelPiece, _action_type: String, _event_data, _targets: Array):
	return null


## Optional policy for authoritative abilities which require a secondary
## movement-type choice. Null delegates to ChessCpuPlayer's legacy chooser.
func choose_movement_type_grant(_model: ChessBoardModel, _king: QuarterlyInitiativeKing, _target: ModelPiece, _options: Array[StringName]):
	return null


func on_action_executed(_action: ChessPrimaryAction, _origin: Vector2i) -> void:
	pass


func reset_session(_reason: StringName = &"reset") -> void:
	pass


func capture_debug_state() -> Dictionary:
	return {}
