extends Node

class_name GameFlow

const OVERWORLD_SCENE := preload("res://scenes/overworld/overworld.tscn")
const CHESS_SCENE := preload("res://scenes/chess_game.tscn")

@export var transition_duration: float = 0.25

@onready var active_content: Node = $ActiveContent
@onready var fade_overlay: ColorRect = $TransitionLayer/FadeOverlay

var player_cell := Vector2i(-1, -1)
var player_facing := Vector2i.UP
var encounter_state: String = "initial"
var active_overworld: Overworld = null
var active_battle: ChessGame = null
var is_transitioning: bool = false

func _ready() -> void:
	fade_overlay.modulate.a = 0.0
	_show_overworld("")

func _show_overworld(pending_result: String) -> void:
	var frame := SubViewportContainer.new()
	frame.name = "OverworldFrame"
	frame.position = Vector2(480, 60)
	frame.size = Vector2(960, 960)
	frame.stretch = true
	frame.stretch_shrink = 6
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	active_content.add_child(frame)

	var viewport := SubViewport.new()
	viewport.name = "OverworldViewport"
	viewport.size = Vector2i(160, 160)
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	frame.add_child(viewport)

	active_overworld = OVERWORLD_SCENE.instantiate()
	active_overworld.configure(player_cell, player_facing, encounter_state, pending_result)
	active_overworld.challenge_requested.connect(_on_challenge_requested)
	viewport.add_child(active_overworld)

func _on_challenge_requested(_encounter_id: String) -> void:
	if is_transitioning or active_overworld == null:
		return
	player_cell = active_overworld.get_player_cell()
	player_facing = active_overworld.get_player_facing()
	encounter_state = "awaiting_result"
	await _transition_to_battle()

func _transition_to_battle() -> void:
	is_transitioning = true
	active_overworld.set_world_input_enabled(false)
	await _fade_to(1.0)
	_clear_active_content()

	active_battle = CHESS_SCENE.instantiate()
	active_battle.control_mode = ChessGame.ControlMode.PLAYER_VS_CPU
	active_battle.ai_color = "black"
	active_battle.player_color = "white"
	active_battle.battle_exit_requested.connect(_on_battle_exit_requested)
	active_content.add_child(active_battle)
	await _fade_to(0.0)
	is_transitioning = false

func _on_battle_exit_requested(player_result: String) -> void:
	if is_transitioning:
		return
	await _transition_to_overworld(player_result)

func _transition_to_overworld(player_result: String) -> void:
	is_transitioning = true
	await _fade_to(1.0)
	_clear_active_content()
	encounter_state = "rematchable"
	_show_overworld(player_result)
	await _fade_to(0.0)
	is_transitioning = false

func _clear_active_content() -> void:
	active_overworld = null
	active_battle = null
	for child in active_content.get_children():
		child.queue_free()
		active_content.remove_child(child)

func _fade_to(alpha: float) -> void:
	if transition_duration <= 0.0:
		fade_overlay.modulate.a = alpha
		return
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", alpha, transition_duration)
	await tween.finished
