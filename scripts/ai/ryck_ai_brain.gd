extends ChessAiBrain
class_name RyckAiBrain
const ActionCodec = preload("res://scripts/state/chess_action_codec.gd")


func choose_plan(actions: Array[ChessPrimaryAction]) -> ChessAiPlan:
	var action: ChessPrimaryAction = player.choose_primary_action(actions)
	if action == null:
		return null
	var plan := ChessAiPlan.new(action)
	plan.brain_id = &"ryck"
	plan.score = player._score_primary_action(action)
	var ranked: Array[Dictionary] = []
	for candidate in actions:
		ranked.append({"action": ActionCodec.describe(candidate), "score": player._score_primary_action(candidate), "status": "heuristic"})
	ranked.sort_custom(func(a, b): return float(a.score) > float(b.score))
	plan.candidates.assign(ranked.slice(0, mini(12, ranked.size())))
	return plan
