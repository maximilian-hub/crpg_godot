extends Resource
class_name ChessAbilityPresentationEntry

@export var piece_type_id: StringName = &"arakne_king"
@export var ability_id: StringName = &"spike_burst"
@export var presentation_profile: Resource
## Legacy compatibility for projectile-only authored entries.
@export var projectile_profile: Resource

func resolved_profile() -> Resource:
	return presentation_profile if presentation_profile != null else projectile_profile
