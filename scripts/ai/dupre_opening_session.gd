extends RefCounted
class_name DupreOpeningSession

var active := false
var selected_family_id: StringName = &""
var node_id := 0
var book_moves_played := 0
var own_actions_played := 0
var started_global_turn := 0
var deviated := false
var exit_reason: StringName = &"not_started"
var last_observed_enemy_move := ""


func begin(family_id: StringName, global_turn: int, initial_node := 0) -> void:
	active = true
	selected_family_id = family_id
	node_id = initial_node
	book_moves_played = 0
	own_actions_played = 0
	started_global_turn = global_turn
	deviated = false
	exit_reason = &""
	last_observed_enemy_move = ""


func leave(reason: StringName) -> void:
	active = false
	exit_reason = reason


func reset() -> void:
	active = false
	selected_family_id = &""
	node_id = 0
	book_moves_played = 0
	own_actions_played = 0
	started_global_turn = 0
	deviated = false
	exit_reason = &"not_started"
	last_observed_enemy_move = ""
