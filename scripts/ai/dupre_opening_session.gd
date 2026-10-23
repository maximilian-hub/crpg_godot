extends RefCounted
class_name DupreOpeningSession

var active := false
var selected_family: Dictionary = {}
var candidate_line_indices: Array[int] = []
var cursor := 0
var book_moves_played := 0
var own_actions_played := 0
var started_global_turn := 0
var deviated := false
var exit_reason: StringName = &"not_started"
var last_observed_enemy_move := ""


func begin(family: Dictionary, global_turn: int, initial_cursor := 0, initial_lines: Array[int] = []) -> void:
	active = true
	selected_family = family
	candidate_line_indices.assign(initial_lines)
	if candidate_line_indices.is_empty():
		for index in range(family.get("lines", []).size()): candidate_line_indices.append(index)
	cursor = initial_cursor
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
	selected_family = {}
	candidate_line_indices.clear()
	cursor = 0
	book_moves_played = 0
	own_actions_played = 0
	started_global_turn = 0
	deviated = false
	exit_reason = &"not_started"
	last_observed_enemy_move = ""
