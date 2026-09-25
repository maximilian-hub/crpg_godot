extends RefCounted
class_name ChessPieceArrivalContext

## Separates a mover's physical arrival from the remainder of its presentation.
## Presentation subscribers claim the context synchronously, mark each mover as
## it reaches its destination, and finish aftermath after retreat/settling ends.

var arrival_gates: Dictionary = {}
var aftermath_gate := CompletionGate.new()
var impact_gate := CompletionGate.new()
var tracks_impact := false


func _init(pieces: Array, include_impact := false) -> void:
	tracks_impact = include_impact
	for piece in pieces:
		arrival_gates[piece] = CompletionGate.new()


func claim() -> void:
	for gate: CompletionGate in arrival_gates.values():
		gate.hold()
	aftermath_gate.hold()
	if tracks_impact:
		impact_gate.hold()


func close_claims() -> void:
	for gate: CompletionGate in arrival_gates.values():
		gate.close()
	aftermath_gate.close()
	if tracks_impact:
		impact_gate.close()


func mark_impact() -> void:
	if tracks_impact and not impact_gate.is_completed():
		impact_gate.release()


func wait_for_impact() -> void:
	if tracks_impact:
		await impact_gate.wait_until_released()


func mark_arrived(piece: ModelPiece) -> void:
	var gate := arrival_gates.get(piece) as CompletionGate
	if gate != null and not gate.is_completed():
		gate.release()


func wait_for_arrival(piece: ModelPiece) -> void:
	var gate := arrival_gates.get(piece) as CompletionGate
	if gate != null:
		await gate.wait_until_released()


func finish_aftermath() -> void:
	if not aftermath_gate.is_completed():
		aftermath_gate.release()


func wait_for_aftermath() -> void:
	await aftermath_gate.wait_until_released()
