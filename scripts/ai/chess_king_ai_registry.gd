extends RefCounted
class_name ChessKingAiRegistry

const ClassicLayer = preload("res://scripts/ai/classic_king_ai_layer.gd")
const ArakneLayer = preload("res://scripts/ai/arakne_king_ai_layer.gd")
const MinotaurLayer = preload("res://scripts/ai/minotaur_king_ai_layer.gd")
const RhetoricianLayer = preload("res://scripts/ai/rhetorician_king_ai_layer.gd")
const NecromancerLayer = preload("res://scripts/ai/necromancer_king_ai_layer.gd")

static var _legacy_layers: Array = [ClassicLayer.new(), ArakneLayer.new()]
static var _dupre_layers: Array = _legacy_layers + [MinotaurLayer.new(), RhetoricianLayer.new(), NecromancerLayer.new()]


static func layer_for(king_type: StringName):
	for layer in _dupre_layers:
		if layer.supports(king_type):
			return layer
	return null


static func supports(king_type: StringName) -> bool:
	for layer in _legacy_layers:
		if layer.supports(king_type):
			return true
	return false


static func supports_dupre(king_type: StringName) -> bool:
	return layer_for(king_type) != null


static func dupre_support_level(king_type: StringName) -> ChessKingAiLayer.SupportLevel:
	var layer = layer_for(king_type)
	return layer.support_level() if layer != null else ChessKingAiLayer.SupportLevel.UNSUPPORTED


static func dupre_unsupported_reason(king_type: StringName) -> String:
	return "" if supports_dupre(king_type) else "King has not passed Dupre authoritative-simulation compatibility tests."
