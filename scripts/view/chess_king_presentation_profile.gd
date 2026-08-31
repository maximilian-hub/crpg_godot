extends Resource
class_name ChessKingPresentationProfile

const MagicalMoveProfile = preload("res://scripts/view/chess_magical_move_profile.gd")

@export var aura_profile: ChessAuraProfile
@export var aura_mode := ChessAura2D.AuraMode.HYBRID
@export var activation_profile: ChessKingActivationProfile
@export var movement_profile: Resource

func ensure_defaults() -> void:
	if aura_profile == null: aura_profile = ChessAuraProfile.new()
	if activation_profile == null: activation_profile = ChessKingActivationProfile.new()
	if movement_profile == null: movement_profile = MagicalMoveProfile.new()
