extends RefCounted
class_name ChessKingAiRegistry

const ClassicLayer = preload("res://scripts/ai/classic_king_ai_layer.gd")
const ArakneLayer = preload("res://scripts/ai/arakne_king_ai_layer.gd")

static var _layers: Array = [ClassicLayer.new(), ArakneLayer.new()]


static func layer_for(king_type: StringName):
	for layer in _layers:
		if layer.supports(king_type):
			return layer
	return null


static func supports(king_type: StringName) -> bool:
	return layer_for(king_type) != null
