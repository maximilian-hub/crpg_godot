extends Resource
class_name ChessKingAuraCatalog

const AuraEntry := preload("res://scripts/view/chess_king_aura_entry.gd")

@export var entries: Array[Resource] = []


func find_entry(king_type_id: StringName) -> Resource:
	var normalized := ChessPieceCatalog.normalize_type_id(king_type_id)
	for entry in entries:
		if entry != null and ChessPieceCatalog.normalize_type_id(entry.king_type_id) == normalized:
			return entry
	return null


func upsert(king_type_id: StringName, aura_profile: ChessAuraProfile, aura_mode: int) -> Resource:
	var normalized := ChessPieceCatalog.normalize_type_id(king_type_id)
	var entry := find_entry(normalized)
	if entry == null:
		entry = AuraEntry.new()
		entries.append(entry)
	entry.king_type_id = normalized
	entry.aura_profile = aura_profile.duplicate(true) as ChessAuraProfile
	entry.aura_mode = clampi(aura_mode, ChessAura2D.AuraMode.SILHOUETTE, ChessAura2D.AuraMode.HYBRID)
	return entry
