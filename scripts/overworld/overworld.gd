extends Node2D
class_name Overworld

signal challenge_requested(encounter_profile: ChessEncounterProfile)
signal inspection_requested(dialogue_path: String)
signal npc_dialogue_requested(npc: OverworldNpc, dialogue_path: String)

@onready var collision_grid: OverworldCollisionGrid = $CollisionGrid
@onready var player: OverworldPlayer = $YSortedWorld/Player
@onready var y_sorted_world: Node2D = $YSortedWorld

var npcs: Array[OverworldNpc] = []
var npc: OverworldNpc = null
var interaction_npc: OverworldNpc = null

var configured_cell := Vector2i(-1, -1)
var configured_facing := Vector2i.UP
var encounter_state: String = "initial"
var configured_player_appearance: OverworldCharacterAppearance = null

func configure(
	cell: Vector2i,
	facing: Vector2i,
	state: String,
	player_appearance: OverworldCharacterAppearance = null
) -> void:
	configured_cell = cell
	configured_facing = facing
	encounter_state = state
	configured_player_appearance = player_appearance

func _ready() -> void:
	$Map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_discover_npcs()
	var npc_spawn := get_node_or_null("NpcSpawn") as Marker2D
	if npc != null and npc_spawn != null:
		var npc_cell := Vector2i(floor(npc_spawn.position.x / 16.0), floor(npc_spawn.position.y / 16.0))
		npc.configure_at_cell(npc_cell)
	var start_cell := configured_cell
	if start_cell.x < 0 or start_cell.y < 0:
		start_cell = Vector2i(floor($PlayerSpawn.position.x / 16.0), floor($PlayerSpawn.position.y / 16.0))
	if configured_player_appearance != null:
		player.set_appearance(configured_player_appearance)
	player.configure(collision_grid, npcs, start_cell, configured_facing)

func _discover_npcs() -> void:
	npcs.clear()
	for child in y_sorted_world.get_children():
		if child is OverworldNpc:
			npcs.append(child)
	npc = null
	for candidate in npcs:
		if candidate.encounter_profile != null:
			npc = candidate
			break
	if npc == null and not npcs.is_empty():
		npc = npcs[0]

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var target_npc := get_npc_in_front()
	if target_npc != null:
		get_viewport().set_input_as_handled()
		_begin_npc_interaction(target_npc)
		return
	var inspectable := get_inspectable_for_player()
	if inspectable != null:
		get_viewport().set_input_as_handled()
		_begin_inspection(inspectable)

func set_world_input_enabled(enabled: bool) -> void:
	player.set_input_enabled(enabled)
	if enabled:
		for candidate in npcs:
			candidate.return_to_original_facing_after_delay()

func get_player_cell() -> Vector2i:
	return player.grid_cell

func get_player_facing() -> Vector2i:
	return player.facing

func _can_talk_to_npc() -> bool:
	return get_npc_in_front() != null

func get_npc_in_front() -> OverworldNpc:
	if not player.is_grid_idle():
		return null
	var target_cell := player.grid_cell + player.facing
	for candidate in npcs:
		if candidate.grid_cell == target_cell and (candidate.encounter_profile != null or not candidate.dialogue_path.is_empty()):
			return candidate
	return null

func get_inspectable_in_front() -> OverworldInspectable:
	return get_inspectable_for_player()

func get_inspectable_for_player() -> OverworldInspectable:
	if not player.is_grid_idle():
		return null
	for candidate in get_tree().get_nodes_in_group(&"overworld_inspectable"):
		if candidate is OverworldInspectable and is_ancestor_of(candidate) and candidate.can_interact(player.grid_cell, player.facing):
			return candidate
	return null

func get_inspectable_at(cell: Vector2i) -> OverworldInspectable:
	for candidate in get_tree().get_nodes_in_group(&"overworld_inspectable"):
		if candidate is OverworldInspectable and is_ancestor_of(candidate) and candidate.get_grid_cell() == cell:
			return candidate
	return null

func _begin_inspection(inspectable: OverworldInspectable) -> void:
	if inspectable == null:
		return
	player.set_input_enabled(false)
	inspection_requested.emit(inspectable.dialogue_path)

func _begin_challenge_dialogue() -> void:
	var target := interaction_npc if is_instance_valid(interaction_npc) else npc
	if target == null:
		return
	_begin_npc_interaction(target)

func _begin_npc_interaction(target: OverworldNpc) -> void:
	if target == null:
		return
	interaction_npc = target
	target.face_toward(player.grid_cell)
	player.set_input_enabled(false)
	if target.encounter_profile != null:
		challenge_requested.emit(target.encounter_profile)
	elif not target.dialogue_path.is_empty():
		npc_dialogue_requested.emit(target, target.dialogue_path)
