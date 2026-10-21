extends ChessAiBrain
class_name RyckAiBrain


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	var action: ChessPrimaryAction = player.choose_primary_action(actions)
	if action == null:
		return null
	var plan := ChessAiPlan.new(action)
	plan.brain_id = &"ryck"
	plan.score = player._score_primary_action(action)
	return plan
