extends RefCounted
class_name ChessPositionValidation

var structural_errors: Array[String] = []
var playability_errors: Array[String] = []

func is_structurally_valid() -> bool:
	return structural_errors.is_empty()

func is_playable() -> bool:
	return structural_errors.is_empty() and playability_errors.is_empty()
