extends RefCounted
class_name ChessKingAiLayer

enum SupportLevel { UNSUPPORTED, GENERIC, ENHANCED }


func supports(_king_type: StringName) -> bool:
	return false


func support_level() -> SupportLevel:
	return SupportLevel.ENHANCED


func allows_traditional_opening() -> bool:
	return true


func action_policy_bonus(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	return 0.0


func action_is_forcing(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String) -> bool:
	return false


func active_ability_is_lethal(_action: ChessPrimaryAction, _target: ModelPiece) -> bool:
	return false


## Cheap, side-effect-free threat query for policy and opening safety. The
## occupancy argument may describe a projected position whose pieces are not
## registered with the live model. Horizon is measured in future turn entries
## for the attacking King: 0 means ready now, 1 means ready when it next moves.
func active_ability_threat(_model: ChessBoardModel, _king: KingPiece, _target: ModelPiece, _target_coordinate: Vector2i, _occupancy: Dictionary, _horizon: int = 0) -> Dictionary:
	return {}


func active_ability_ready_in_turn_entries(model: ChessBoardModel, king: KingPiece) -> int:
	if model.active_ability_cooldowns_disabled or king.is_active_ability_ready():
		return 0
	if king.cooldown_reset_pending:
		return king.base_cooldown + 1
	return king.current_cooldown + int(king.initial_cooldown_turn_pending)


func evaluation_bonus(_model: ChessBoardModel, _perspective: String) -> float:
	return 0.0


func exchange_policy_adjustment(_model: ChessBoardModel, _action: ChessPrimaryAction, _perspective: String, _exchange: Dictionary, _tactical_map = null) -> float:
	return 0.0


func reaction_target_score(_model: ChessBoardModel, _calling_piece: ModelPiece, _action_type: String, _event_data, _target: Vector2i, _perspective: String, _tactical_map = null) -> float:
	return -INF
