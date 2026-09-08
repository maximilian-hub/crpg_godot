extends RefCounted
class_name ChessTargetedAbilityPresentationContext

signal effect_resolved(target_survived: bool, target_defeated: bool, target_is_king: bool)

var source: Node
var ability_id: StringName
var ability_name: String
var target_coordinate: Vector2i
var target_piece: Node
var impact_gate := CompletionGate.new()
var aftermath_gate := CompletionGate.new()
var _effect_reported := false
var target_survived := false
var target_defeated := false
var target_is_king := false


func _init(king: Node, id: StringName, display_name: String, coordinate: Vector2i, target: Node) -> void:
	source = king
	ability_id = id
	ability_name = display_name
	target_coordinate = coordinate
	target_piece = target

func claim() -> void:
	impact_gate.hold()
	aftermath_gate.hold()

func close_claims() -> void:
	impact_gate.close()
	aftermath_gate.close()

func mark_impact() -> void:
	if not impact_gate.is_completed():
		impact_gate.release()

func wait_for_impact() -> void:
	await impact_gate.wait_until_released()

func report_effect() -> void:
	if _effect_reported:
		return
	_effect_reported = true
	target_survived = is_instance_valid(target_piece) and target_piece.current_hp > 0
	target_defeated = not target_survived
	target_is_king = is_instance_valid(target_piece) and bool(target_piece.get("is_king"))
	effect_resolved.emit(target_survived, target_defeated, target_is_king)

func wait_for_effect() -> void:
	if _effect_reported:
		return
	await effect_resolved

func finish_aftermath() -> void:
	if not aftermath_gate.is_completed():
		aftermath_gate.release()

func wait_for_aftermath() -> void:
	await aftermath_gate.wait_until_released()
