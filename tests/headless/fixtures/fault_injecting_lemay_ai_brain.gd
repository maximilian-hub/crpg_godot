extends LeMayAiBrain

enum FaultMode { REJECT, LEAVE_UNSETTLED }

var fault_mode := FaultMode.REJECT


func _execute_descriptor(simulation: ChessBoardModel, descriptor: Dictionary) -> bool:
	if fault_mode == FaultMode.LEAVE_UNSETTLED:
		simulation.action_in_progress = true
		return true
	return false
