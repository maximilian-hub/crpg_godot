extends Resource
class_name ChessKingPresentationProfile

enum ActivationChoreography { STANDARD_RITUAL, HOOD_DECISIVE }

const MagicalMoveProfile = preload("res://scripts/view/chess_magical_move_profile.gd")
const AuraCatalog = preload("res://scripts/view/chess_king_aura_catalog.gd")

@export var aura_profile: ChessAuraProfile
@export var aura_mode := ChessAura2D.AuraMode.HYBRID
@export var aura_catalog: Resource
@export var activation_profile: ChessKingActivationProfile
@export var movement_profile: Resource
@export var activation_choreography := ActivationChoreography.STANDARD_RITUAL

func ensure_defaults() -> void:
	if aura_profile == null: aura_profile = ChessAuraProfile.new()
	if activation_profile == null: activation_profile = ChessKingActivationProfile.new()
	if movement_profile == null: movement_profile = MagicalMoveProfile.new()


func resolve_aura_entry(king_type_id: StringName) -> Resource:
	return aura_catalog.find_entry(king_type_id) if aura_catalog != null else null
