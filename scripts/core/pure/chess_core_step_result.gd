extends RefCounted
class_name ChessCoreStepResult

enum Status { COMPLETED, PENDING_CHOICE, REJECTED, UNSUPPORTED }

var status := Status.REJECTED
var state: ChessCoreState
var events: Array[ChessCoreEvent] = []
var choice: ChessCoreChoice
var error := ""


static func rejected(source: ChessCoreState, message: String) -> ChessCoreStepResult:
	var result := ChessCoreStepResult.new()
	result.status = Status.REJECTED
	result.state = source.copy() if source != null else null
	result.error = message
	return result
