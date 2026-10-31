extends "res://scripts/ai/chess_king_ai_layer.gd"
class_name QuarterlyInitiativeKingAiLayer

const QuarterlyPolicy = preload("res://scripts/ai/quarterly_initiative_ai_policy.gd")
const GRANT_OPTIONS: Array[StringName] = [&"pawn", &"knight", &"bishop", &"rook"]


func supports(king_type: StringName) -> bool:
	return king_type == &"quarterly_initiative_king"


func choose_movement_type_grant(model: ChessBoardModel, _king: QuarterlyInitiativeKing, target: ModelPiece, options: Array[StringName]) -> StringName:
	return QuarterlyPolicy.deterministic_choice(model, target, options)


func action_policy_bonus(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String, _tactical_map = null) -> float:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is QuarterlyInitiativeKing:
		return 0.0
	# ChessCpuPlayer's established Quarterly policy remains the single source of
	# the action score; this layer adds effects, forcing status, and simulation
	# selection without counting that value twice.
	return 0.0


func action_is_forcing(model: ChessBoardModel, action: ChessPrimaryAction, _perspective: String) -> bool:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is QuarterlyInitiativeKing:
		return false
	var recipient: ModelPiece = model.board[action.target.x][action.target.y]
	if recipient == null:
		return false
	var best := QuarterlyPolicy.best_grant(model, recipient, QuarterlyPolicy.eligible_options(model, recipient, GRANT_OPTIONS))
	return float(best.score) >= 20.0


func describe_ability_action(model: ChessBoardModel, action: ChessPrimaryAction, _occupancy: Dictionary) -> Array[DupreAbilityEffect]:
	if action.kind != ChessPrimaryAction.Kind.ACTIVE_ABILITY or not action.piece is QuarterlyInitiativeKing:
		return []
	var recipient: ModelPiece = model.board[action.target.x][action.target.y]
	if recipient == null:
		return []
	var choice := QuarterlyPolicy.deterministic_choice(model, recipient, GRANT_OPTIONS)
	if choice == &"":
		return []
	var effect := AbilityEffect.new()
	effect.source_piece_id = action.piece.piece_id
	effect.source_color = action.piece.color
	effect.ability_id = QuarterlyInitiativeKing.ACTIVE_ABILITY_ID
	effect.target_piece_id = recipient.piece_id
	effect.target_coordinate = recipient.coordinate
	effect.kind = AbilityEffect.Kind.MOVEMENT_GRANT
	effect.material_delta = QuarterlyPolicy.score_grant(model, recipient, choice)
	effect.metadata = {
		"movement_type": choice,
		"hp_cost": 0 if model.global_turn_number % 4 == 0 else 1,
		"high_impact": effect.material_delta >= 20.0,
	}
	return [effect]


func evaluation_bonus(model: ChessBoardModel, perspective: String) -> float:
	var result := 0.0
	for row in model.board:
		for piece in row:
			if piece == null or piece.is_king:
				continue
			var bonus := float(piece.granted_movement_types.size()) * 0.6
			result += bonus if piece.color == perspective else -bonus
	return result
