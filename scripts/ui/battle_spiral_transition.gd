extends Node
class_name BattleSpiralTransition

const RendererScript := preload("res://scripts/ui/battle_spiral_renderer.gd")
const LetterboxScript := preload("res://scripts/ui/transition_letterbox_blackout.gd")

signal covered()
signal reveal_cue_reached()

@export_range(1, 64, 1) var cell_size := 8
@export_range(1, 128, 1) var cells_per_tick := 7
@export_range(0.001, 1.0, 0.001) var tick_interval := 2.5 / 60.0
@export var transition_audio: AudioStream
@export_range(-80.0, 24.0, 0.5) var transition_audio_volume_db := 0.0
@export_range(0.0, 30.0, 0.01) var battle_reveal_time := 3.0

@onready var logical_canvas: CanvasLayer = $LogicalCanvas
@onready var renderer: Control = $LogicalCanvas/SpiralRenderer
@onready var root_blackout_layer: CanvasLayer = $RootBlackoutLayer
@onready var letterbox_blackout: Control = $RootBlackoutLayer/LetterboxBlackout
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

var is_playing := false
var captured_logical_size := Vector2i.ZERO
var _tick_elapsed := 0.0
var _completion_pending := false
var _covered_emitted := false
var _reveal_cue_emitted := false
var _started_usec := 0
var _last_transition_time := 0.0
var _active_tick_interval := 0.0


func _ready() -> void:
	set_process(false)
	logical_canvas.visible = false
	root_blackout_layer.visible = false


func play_inward(logical_viewport: SubViewport, overworld_frame: Control, immediate := false) -> void:
	reset()
	if not is_instance_valid(logical_viewport) or not is_instance_valid(overworld_frame):
		return
	captured_logical_size = logical_viewport.size
	if captured_logical_size.x <= 0 or captured_logical_size.y <= 0:
		return

	var columns := ceili(float(captured_logical_size.x) / float(maxi(1, cell_size)))
	var rows := ceili(float(captured_logical_size.y) / float(maxi(1, cell_size)))
	renderer.configure(captured_logical_size, cell_size, build_spiral_order(columns, rows))
	var reveal_ticks := ceili(float(renderer.cell_order.size()) / float(maxi(1, cells_per_tick)))
	var cover_deadline := maxf(0.001, battle_reveal_time - (2.0 / 60.0))
	_active_tick_interval = minf(tick_interval, cover_deadline / float(maxi(1, reveal_ticks)))
	logical_canvas.custom_viewport = logical_viewport
	letterbox_blackout.set_frame_rect(Rect2(overworld_frame.global_position, overworld_frame.size))
	logical_canvas.visible = true
	root_blackout_layer.visible = true
	if transition_audio != null:
		audio_player.stream = transition_audio
		audio_player.volume_db = transition_audio_volume_db
		audio_player.play()
		if transition_audio.get_length() < battle_reveal_time:
			push_warning("Transition audio is shorter than the %.2f-second battle reveal cue." % battle_reveal_time)
	_started_usec = Time.get_ticks_usec()

	if immediate:
		renderer.reveal_through(renderer.cell_order.size())
		await get_tree().process_frame
		_covered_emitted = true
		_reveal_cue_emitted = true
		return

	is_playing = true
	set_process(true)
	await covered


func reset() -> void:
	is_playing = false
	_tick_elapsed = 0.0
	_completion_pending = false
	_covered_emitted = false
	_reveal_cue_emitted = false
	_started_usec = 0
	_last_transition_time = 0.0
	_active_tick_interval = 0.0
	set_process(false)
	release_visual_cover()
	if is_instance_valid(audio_player):
		audio_player.stop()
	captured_logical_size = Vector2i.ZERO


func release_visual_cover() -> void:
	if is_instance_valid(logical_canvas):
		logical_canvas.visible = false
		# CanvasLayer rejects a null custom viewport. Reattach the hidden layer to
		# Main's viewport before the temporary overworld viewport is freed.
		if is_inside_tree():
			logical_canvas.custom_viewport = get_viewport()
	if is_instance_valid(root_blackout_layer):
		root_blackout_layer.visible = false
	if is_instance_valid(renderer):
		renderer.clear()
	captured_logical_size = Vector2i.ZERO


func wait_for_reveal_cue() -> void:
	if _reveal_cue_emitted:
		return
	await reveal_cue_reached


func _process(delta: float) -> void:
	if not is_playing:
		return
	if _completion_pending:
		_completion_pending = false
		if not _covered_emitted:
			_covered_emitted = true
			covered.emit()
	if not _covered_emitted:
		_tick_elapsed += delta
		while _tick_elapsed >= _active_tick_interval and not renderer.is_fully_covered():
			_tick_elapsed -= _active_tick_interval
			_reveal_tick()
		if renderer.is_fully_covered() and not _completion_pending:
			# Emit on the next process frame so the complete black grid is actually
			# drawn once before Main is permitted to replace the overworld.
			_completion_pending = true
	if not _reveal_cue_emitted and _transition_time() >= battle_reveal_time:
		_reveal_cue_emitted = true
		is_playing = false
		set_process(false)
		reveal_cue_reached.emit()


func _reveal_tick() -> void:
	renderer.reveal_through(renderer.revealed_cell_count + cells_per_tick)


func _transition_time() -> float:
	var elapsed := 0.0
	if _started_usec > 0:
		elapsed = float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	if audio_player.playing:
		var audible_position := (
			audio_player.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()
		)
		elapsed = maxf(0.0, audible_position)
	_last_transition_time = maxf(_last_transition_time, elapsed)
	return _last_transition_time


static func build_spiral_order(columns: int, rows: int) -> Array[Vector2i]:
	var order: Array[Vector2i] = []
	if columns <= 0 or rows <= 0:
		return order
	var left := 0
	var right := columns - 1
	var top := 0
	var bottom := rows - 1
	while left <= right and top <= bottom:
		for y in range(top, bottom + 1):
			order.append(Vector2i(left, y))
		left += 1
		if left > right:
			break

		for x in range(left, right + 1):
			order.append(Vector2i(x, bottom))
		bottom -= 1
		if top > bottom:
			break

		for y in range(bottom, top - 1, -1):
			order.append(Vector2i(right, y))
		right -= 1
		if left > right:
			break

		for x in range(right, left - 1, -1):
			order.append(Vector2i(x, top))
		top += 1
	return order
