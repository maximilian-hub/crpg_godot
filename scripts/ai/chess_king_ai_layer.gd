extends RefCounted
class_name ChessKingAiLayer

const AbilityEffect = preload("res://scripts/ai/dupre_ability_effect.gd")

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
	for effect in collect_ability_threats(_model, _king, _occupancy, _horizon):
		if effect.target_piece_id == _target.piece_id or (effect.target_piece_id.is_empty() and effect.target_coordinate == _target_coordinate):
			return {
				"ability_id": effect.ability_id,
				"damage": effect.damage,
				"lethal": effect.lethal,
				"ready_in_turn_entries": effect.ready_in_turn_entries,
				"certainty": effect.certainty,
				"effect": effect,
			}
	return {}


## Side-effect-free descriptions. Effects contain stable ids/coordinates, not
## references to speculative pieces, and are valid only for the supplied state.
func collect_ability_threats(_model: ChessBoardModel, _king: KingPiece, _occupancy: Dictionary, _horizon: int = 0) -> Array[DupreAbilityEffect]:
	return []


func has_ability_threat_effects() -> bool:
	return false


func describe_ability_action(_model: ChessBoardModel, _action: ChessPrimaryAction, _occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	return []


func describe_action_reactions(_model: ChessBoardModel, _action: ChessPrimaryAction, _occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	return []


func has_action_reaction_effects() -> bool:
	return false


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
