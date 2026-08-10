extends Node2D
class_name Overworld

signal challenge_requested(encounter_id: String)

enum DialogueMode { CLOSED, PAGES, CHOICE }

@export var greeting_pages: Array[String] = ["Hey there. Want to play a game of chess?"]
@export var decline_pages: Array[String] = ["Maybe next time."]
@export var win_pages: Array[String] = ["You won. Well played."]
@export var loss_pages: Array[String] = ["I won this one. Try again anytime."]
@export var draw_pages: Array[String] = ["A draw. Good game."]
@export var rematch_pages: Array[String] = ["Want a rematch?"]

@onready var collision_grid: OverworldCollisionGrid = $CollisionGrid
@onready var player: OverworldPlayer = $Player
@onready var npc: OverworldNpc = $Npc
@onready var dialogue_panel: Control = $DialogueLayer/DialoguePanel
@onready var dialogue_label: Label = $DialogueLayer/DialoguePanel/DialogueLabel
@onready var choice_label: Label = $DialogueLayer/DialoguePanel/ChoiceLabel

var configured_cell := Vector2i(-1, -1)
var configured_facing := Vector2i.UP
var encounter_state: String = "initial"
var pending_result: String = ""
var dialogue_mode := DialogueMode.CLOSED
var active_pages: Array[String] = []
var page_index: int = 0

func configure(cell: Vector2i, facing: Vector2i, state: String, result: String) -> void:
	configured_cell = cell
	configured_facing = facing
	encounter_state = state
	pending_result = result

func _ready() -> void:
	$Map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var npc_cell := Vector2i(floor($NpcSpawn.position.x / 16.0), floor($NpcSpawn.position.y / 16.0))
	npc.configure_at_cell(npc_cell)
	var start_cell := configured_cell
	if start_cell.x < 0 or start_cell.y < 0:
		start_cell = Vector2i(floor($PlayerSpawn.position.x / 16.0), floor($PlayerSpawn.position.y / 16.0))
	player.configure(collision_grid, npc, start_cell, configured_facing)
	dialogue_panel.hide()
	if not pending_result.is_empty():
		call_deferred("_begin_result_dialogue")

func _unhandled_input(event: InputEvent) -> void:
	if dialogue_mode != DialogueMode.CLOSED:
		if event.is_action_pressed("back"):
			get_viewport().set_input_as_handled()
			if dialogue_mode == DialogueMode.CHOICE:
				_decline_challenge()
			else:
				_close_dialogue()
			return
		if event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			if dialogue_mode == DialogueMode.CHOICE:
				_accept_challenge()
			else:
				_advance_page()
			return
		return

	if event.is_action_pressed("interact") and _can_talk_to_npc():
		get_viewport().set_input_as_handled()
		_begin_challenge_dialogue()

func set_world_input_enabled(enabled: bool) -> void:
	player.set_input_enabled(enabled and dialogue_mode == DialogueMode.CLOSED)

func get_player_cell() -> Vector2i:
	return player.grid_cell

func get_player_facing() -> Vector2i:
	return player.facing

func _can_talk_to_npc() -> bool:
	if not player.is_grid_idle():
		return false
	return player.grid_cell + player.facing == npc.grid_cell

func _begin_challenge_dialogue() -> void:
	npc.face_toward(player.grid_cell)
	var pages := rematch_pages if encounter_state == "rematchable" else greeting_pages
	_show_pages(pages)

func _begin_result_dialogue() -> void:
	npc.face_toward(player.grid_cell)
	match pending_result:
		"win": _show_pages(win_pages, false)
		"loss": _show_pages(loss_pages, false)
		"draw": _show_pages(draw_pages, false)
		_: _show_pages(["Good game."], false)
	pending_result = ""

func _show_pages(pages: Array[String], lead_to_choice: bool = true) -> void:
	active_pages = pages.duplicate()
	page_index = 0
	dialogue_mode = DialogueMode.PAGES
	dialogue_panel.set_meta("lead_to_choice", lead_to_choice)
	dialogue_panel.show()
	choice_label.hide()
	player.set_input_enabled(false)
	_update_page()

func _update_page() -> void:
	dialogue_label.text = active_pages[page_index] if page_index < active_pages.size() else ""

func _advance_page() -> void:
	page_index += 1
	if page_index < active_pages.size():
		_update_page()
		return
	if dialogue_panel.get_meta("lead_to_choice", false):
		dialogue_mode = DialogueMode.CHOICE
		dialogue_label.text = "Play a match?"
		choice_label.text = "K / Confirm: Yes     J: No"
		choice_label.show()
	else:
		_close_dialogue()

func _accept_challenge() -> void:
	_close_dialogue(false)
	challenge_requested.emit(npc.encounter_id)

func _decline_challenge() -> void:
	_show_pages(decline_pages, false)

func _close_dialogue(restore_input: bool = true) -> void:
	dialogue_mode = DialogueMode.CLOSED
	active_pages.clear()
	dialogue_panel.hide()
	choice_label.hide()
	if restore_input:
		player.set_input_enabled(true)
