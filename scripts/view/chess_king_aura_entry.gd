extends Resource
class_name ChessKingAuraEntry

@export var king_type_id: StringName = &"classic_king"
@export var aura_profile: ChessAuraProfile
@export var aura_mode := ChessAura2D.AuraMode.HYBRID


func is_valid() -> bool:
	var normalized := ChessPieceCatalog.normalize_type_id(king_type_id)
	return aura_profile != null and normalized in ChessPieceCatalog.get_palette_type_ids(&"king")
