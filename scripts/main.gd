extends Node

class_name GameFlow

const OVERWORLD_SCENE := preload("res://scenes/overworld/overworld.tscn")
const CHESS_SCENE := preload("res://scenes/chess_game.tscn")
const BATTLE_BACKGROUND_TEXTURE := preload("res://assets/woodtile.png")
const BATTLE_LOGICAL_SIZE := Vector2i(960, 540)
const TARGET_OVERWORLD_LOGICAL_SIDE := 180
const DIALOGUE_LOGICAL_MARGIN := 4
const DIALOGUE_LOGICAL_HEIGHT := 44
const DIALOGUE_LOGICAL_BOTTOM_MARGIN := 5
enum BattlePresentationMode {
	FLUID_NATIVE,
	FIXED_LOGICAL,
}

@export var transition_duration: float = 0.25
@export var battle_presentation_mode: BattlePresentationMode = BattlePresentationMode.FLUID_NATIVE

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
var overworld_dialogue_layer: CanvasLayer = null
var battle_environment: TextureRect = null
var battle_frame: SubViewportContainer = null
var battle_viewport: SubViewport = null

func _ready() -> void:
	fade_overlay.modulate.a = 0.0
	get_viewport().size_changed.connect(_layout_overworld_frame)
	get_viewport().size_changed.connect(_layout_battle_frame)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(BATTLE_LOGICAL_SIZE)
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
	# Render text at window resolution while retaining the overworld's dialogue logic.
	overworld_dialogue_layer = active_overworld.get_node("DialogueLayer") as CanvasLayer
	overworld_dialogue_layer.reparent(self)
	_layout_overworld_frame()

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
	if is_instance_valid(overworld_dialogue_layer):
		_layout_overworld_dialogue(layout)

func _layout_overworld_dialogue(layout: Dictionary) -> void:
	var scale: int = layout.integer_scale
	var frame_position: Vector2 = layout.position
	var frame_side: int = layout.frame_side
	var panel := overworld_dialogue_layer.get_node("DialoguePanel") as Control
	var dialogue_label := panel.get_node("DialogueLabel") as Label
	var choice_label := panel.get_node("ChoiceLabel") as Label
	var margin := DIALOGUE_LOGICAL_MARGIN * scale
	var panel_height := DIALOGUE_LOGICAL_HEIGHT * scale
	panel.position = frame_position + Vector2(
		margin,
		frame_side - panel_height - DIALOGUE_LOGICAL_BOTTOM_MARGIN * scale
	)
	panel.size = Vector2(frame_side - margin * 2, panel_height)
	dialogue_label.position = Vector2(6, 4) * scale
	dialogue_label.size = Vector2(panel.size.x - 12 * scale, 23 * scale)
	dialogue_label.add_theme_font_size_override("font_size", 8 * scale)
	choice_label.position = Vector2(6, 29) * scale
	choice_label.size = Vector2(panel.size.x - 12 * scale, 11 * scale)
	choice_label.add_theme_font_size_override("font_size", 6 * scale)

static func calculate_overworld_layout(window_size: Vector2i) -> Dictionary:
	var integer_scale := maxi(1, floori(float(window_size.y) / TARGET_OVERWORLD_LOGICAL_SIDE)) + 2
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

func _on_challenge_requested(encounter_profile: ChessEncounterProfile) -> void:
	if is_transitioning or active_overworld == null:
		return
	player_cell = active_overworld.get_player_cell()
	player_facing = active_overworld.get_player_facing()
	encounter_state = "awaiting_result"
	await _transition_to_battle(encounter_profile)

func _transition_to_battle(encounter_profile: ChessEncounterProfile = null) -> void:
	is_transitioning = true
	active_overworld.set_world_input_enabled(false)
	await _fade_to(1.0)
	_clear_active_content()

	_create_battle_environment()
	active_battle = CHESS_SCENE.instantiate()
	active_battle.control_mode = ChessGame.ControlMode.PLAYER_VS_CPU
	active_battle.player_color = "white"
	if encounter_profile != null and encounter_profile.opponent_presentation != null:
		active_battle.opponent_presentation = encounter_profile.opponent_presentation
	active_battle.opponent_hand_style = encounter_profile.opponent_hand_style if encounter_profile != null else null
	active_battle.battle_exit_requested.connect(_on_battle_exit_requested)
	var board_view := active_battle.get_node("CanvasLayer/ChessBoard") as ChessBoardView
	if battle_presentation_mode == BattlePresentationMode.FLUID_NATIVE:
		active_content.add_child(active_battle)
	else:
		board_view.viewport_height_width_ratio = 0.90
		board_view.viewport_width_cap_ratio = 0.64
		board_view.scale_world_with_projection = false
		_create_fixed_battle_frame()
		battle_viewport.add_child(active_battle)
	await _fade_to(0.0)
	is_transitioning = false

func _create_battle_environment() -> void:
	battle_environment = TextureRect.new()
	battle_environment.name = "BattleEnvironment"
	battle_environment.texture = BATTLE_BACKGROUND_TEXTURE
	battle_environment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	battle_environment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	battle_environment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	active_content.add_child(battle_environment)
	battle_environment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _create_fixed_battle_frame() -> void:
	battle_frame = SubViewportContainer.new()
	battle_frame.name = "BattleFrame"
	battle_frame.stretch = true
	battle_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	active_content.add_child(battle_frame)

	battle_viewport = SubViewport.new()
	battle_viewport.name = "BattleViewport"
	battle_viewport.size = BATTLE_LOGICAL_SIZE
	battle_viewport.transparent_bg = true
	battle_viewport.physics_object_picking = true
	battle_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	battle_viewport.snap_2d_transforms_to_pixel = true
	battle_viewport.snap_2d_vertices_to_pixel = true
	battle_frame.add_child(battle_viewport)
	_layout_battle_frame()

func _layout_battle_frame() -> void:
	if not is_instance_valid(battle_frame) or not is_instance_valid(battle_viewport):
		return
	var window_size := Vector2i(get_viewport().get_visible_rect().size)
	if window_size.x <= 0 or window_size.y <= 0:
		return
	var layout := calculate_battle_layout(window_size)
	battle_frame.position = layout.position
	battle_frame.size = Vector2(layout.frame_size)
	battle_frame.stretch_shrink = layout.integer_scale

static func calculate_battle_layout(window_size: Vector2i) -> Dictionary:
	var integer_scale := maxi(1, mini(
		floori(float(window_size.x) / BATTLE_LOGICAL_SIZE.x),
		floori(float(window_size.y) / BATTLE_LOGICAL_SIZE.y)
	))
	var frame_size := BATTLE_LOGICAL_SIZE * integer_scale
	return {
		"position": Vector2(
			floori((window_size.x - frame_size.x) * 0.5),
			floori((window_size.y - frame_size.y) * 0.5)
		),
		"frame_size": frame_size,
		"integer_scale": integer_scale,
	}

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
	battle_environment = null
	battle_frame = null
	battle_viewport = null
	overworld_frame = null
	overworld_viewport = null
	if is_instance_valid(overworld_dialogue_layer):
		overworld_dialogue_layer.get_parent().remove_child(overworld_dialogue_layer)
		overworld_dialogue_layer.queue_free()
	overworld_dialogue_layer = null
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
