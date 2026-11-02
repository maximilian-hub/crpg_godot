extends RefCounted
class_name ChessCoreKingRules

const ArakneRules := preload("res://scripts/core/pure/arakne_core_rules.gd")
const NecromancerRules := preload("res://scripts/core/pure/necromancer_core_rules.gd")
const MinotaurRules := preload("res://scripts/core/pure/minotaur_core_rules.gd")
const QuarterlyRules := preload("res://scripts/core/pure/quarterly_initiative_core_rules.gd")
const CannonRules := preload("res://scripts/core/pure/cannon_core_rules.gd")
const RhetoricianRules := preload("res://scripts/core/pure/rhetorician_core_rules.gd")
const WraithRules := preload("res://scripts/core/pure/wraith_core_rules.gd")
const ArcherRules := preload("res://scripts/core/pure/archer_core_rules.gd")


static func for_type(type_id: StringName):
	match type_id:
		&"arakne_king": return ArakneRules
		&"necromancer_king": return NecromancerRules
		&"minotaur_king": return MinotaurRules
		&"quarterly_initiative_king": return QuarterlyRules
		&"cannon_king": return CannonRules
		&"rhetorician_king": return RhetoricianRules
		&"wraith_king": return WraithRules
		&"archer_king", &"archer_king_draw", &"archer_king_quiver", &"archer_king_combination", &"archer_king_charge": return ArcherRules
		_: return null


static func is_supported_king(type_id: StringName) -> bool:
	return type_id == &"classic_king" or for_type(type_id) != null


static func base_cooldown(type_id: StringName) -> int:
	var rules = for_type(type_id)
	return int(rules.base_cooldown()) if rules != null else 0
