extends Node

class_name GameFlow

const OVERWORLD_SCENE := preload("res://scenes/overworld/overworld.tscn")
const CHESS_SCENE := preload("res://scenes/chess_game.tscn")
const TARGET_OVERWORLD_LOGICAL_SIDE := 180

@export var transition_duration: float = 0.25

@onready var active_content: Node = $ActiveContent
@onready var fade_overlay: ColorRect = $TransitionLayer/FadeOverlay

var player_cell := Vector2i(-1, -1)
var player_facing := Vector2i.UP
var encounter_state: String = "initial"
var active_overworld: Overworld = null
var active_battle: ChessGame = null
var is_transitioning: bool = false
var overworld_frame: SubViewportContainer = null
var overworld_viewport: SubViewport = null

func _ready() -> void:
	fade_overlay.modulate.a = 0.0
	get_viewport().size_changed.connect(_layout_overworld_frame)
	_show_overworld("")

func _show_overworld(pending_result: String) -> void:
	overworld_frame = SubViewportContainer.new()
	overworld_frame.name = "OverworldFrame"
	overworld_frame.stretch = true
	overworld_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	active_content.add_child(overworld_frame)

	overworld_viewport = SubViewport.new()
	overworld_viewport.name = "OverworldViewport"
	overworld_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	overworld_viewport.snap_2d_transforms_to_pixel = true
	overworld_frame.add_child(overworld_viewport)
	_layout_overworld_frame()

	active_overworld = OVERWORLD_SCENE.instantiate()
	active_overworld.configure(player_cell, player_facing, encounter_state, pending_result)
	active_overworld.challenge_requested.connect(_on_challenge_requested)
	overworld_viewport.add_child(active_overworld)

func _layout_overworld_frame() -> void:
	if not is_instance_valid(overworld_frame) or not is_instance_valid(overworld_viewport):
		return
	var window_size := Vector2i(get_viewport().get_visible_rect().size)
	if window_size.x <= 0 or window_size.y <= 0:
		return
	var layout := calculate_overworld_layout(window_size)
	overworld_frame.position = layout.position
	overworld_frame.size = Vector2(layout.frame_side, layout.frame_side)
	overworld_frame.stretch_shrink = layout.integer_scale

static func calculate_overworld_layout(window_size: Vector2i) -> Dictionary:
	var integer_scale := maxi(1, floori(float(window_size.y) / TARGET_OVERWORLD_LOGICAL_SIDE))
	var logical_side := maxi(1, floori(float(window_size.y) / integer_scale))
	var frame_side := logical_side * integer_scale
	return {
		"position": Vector2(
			floori((window_size.x - frame_side) * 0.5),
			floori((window_size.y - frame_side) * 0.5)
		),
		"frame_side": frame_side,
		"integer_scale": integer_scale,
		"logical_side": logical_side,
	}

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
	overworld_frame = null
	overworld_viewport = null
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
