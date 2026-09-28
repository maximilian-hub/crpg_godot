extends Node2D
class_name Overworld

signal challenge_requested(encounter_profile: ChessEncounterProfile)

@onready var collision_grid: OverworldCollisionGrid = $CollisionGrid
@onready var player: OverworldPlayer = $YSortedWorld/Player
@onready var npc: OverworldNpc = $YSortedWorld/Npc

var configured_cell := Vector2i(-1, -1)
var configured_facing := Vector2i.UP
var encounter_state: String = "initial"

func configure(cell: Vector2i, facing: Vector2i, state: String) -> void:
	configured_cell = cell
	configured_facing = facing
	encounter_state = state

func _ready() -> void:
	$Map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var npc_cell := Vector2i(floor($NpcSpawn.position.x / 16.0), floor($NpcSpawn.position.y / 16.0))
	npc.configure_at_cell(npc_cell)
	var start_cell := configured_cell
	if start_cell.x < 0 or start_cell.y < 0:
		start_cell = Vector2i(floor($PlayerSpawn.position.x / 16.0), floor($PlayerSpawn.position.y / 16.0))
	player.configure(collision_grid, npc, start_cell, configured_facing)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _can_talk_to_npc():
		get_viewport().set_input_as_handled()
		_begin_challenge_dialogue()

func set_world_input_enabled(enabled: bool) -> void:
	player.set_input_enabled(enabled)

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
	player.set_input_enabled(false)
	challenge_requested.emit(npc.encounter_profile)
