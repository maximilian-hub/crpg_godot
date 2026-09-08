extends Node2D
class_name ChessCooldownMote2D

enum MotionState { ORBITING, EMERGING, ABSORBING }

var identity := 0
var motion_state := MotionState.ORBITING
var formation_angle := 0.0
var target_angle := 0.0
var velocity := Vector2.ZERO
var transition_elapsed := 0.0
var transition_delay := 0.0
var transition_duration := 0.5
var transition_start := Vector2.ZERO
var transition_control_a := Vector2.ZERO
var transition_control_b_offset := Vector2.ZERO
var transition_started := false
var hover_phase := 0.0
var color := Color.WHITE
var dormant_color := Color.GRAY
var size := 4.0
var opacity := 0.8


func configure(mote_id: int, aura_color: Color, visual_size: float, visual_opacity: float) -> void:
	identity = mote_id
	color = aura_color
	dormant_color = Color.WHITE
	size = visual_size
	opacity = visual_opacity
	hover_phase = fmod(float(identity) * 2.399963, TAU)
	queue_redraw()


func set_visual_charge(amount: float) -> void:
	modulate = dormant_color.lerp(color, clampf(amount, 0.0, 1.0))
	modulate.a *= opacity


func _draw() -> void:
	var half := maxf(size * 0.5, 1.0)
	# Layered pixel diamonds read as luminous motes without requiring bespoke art.
	draw_rect(Rect2(Vector2(-half, -half * 0.5).round(), Vector2(half * 2.0, maxf(half, 1.0)).round()), Color.WHITE)
	draw_rect(Rect2(Vector2(-half * 0.5, -half).round(), Vector2(maxf(half, 1.0), half * 2.0).round()), Color.WHITE)
