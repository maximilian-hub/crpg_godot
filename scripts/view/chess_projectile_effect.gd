extends Node2D
class_name ChessProjectileEffect

signal impact_finished

var profile: Resource
var world_scale := 1.0
var projectile: AnimatedSprite2D
var impact: AnimatedSprite2D
var impact_marker: Node2D
var elapsed := 0.0
var placeholder_mode := false
var travel_tween: Tween
var impact_complete := false

func configure(value: Resource, scale_factor: float) -> void:
	profile = value
	world_scale = maxf(scale_factor, 0.01)
	z_index = ChessBoardView.BOARD_EFFECT_Z + 2
	z_as_relative = false

func fly(start: Vector2, finish: Vector2, duration_scale := 1.0) -> void:
	position = start.round()
	rotation = (finish - start).angle() + deg_to_rad(profile.rotation_offset_degrees)
	projectile = AnimatedSprite2D.new()
	projectile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	projectile.scale = Vector2.ONE * profile.projectile_scale * world_scale
	if profile.projectile_frames != null:
		projectile.sprite_frames = profile.projectile_frames
		projectile.play(profile.projectile_animation)
	else:
		placeholder_mode = true
	add_child(projectile)
	queue_redraw()
	_play_sound(profile.projectile_sound, profile.projectile_volume_db)
	var duration := start.distance_to(finish) / maxf(profile.travel_speed * world_scale, 1.0)
	travel_tween = create_tween()
	travel_tween.tween_method(func(p: float): position = start.lerp(finish, p).round(), 0.0, 1.0, duration * duration_scale)
	await travel_tween.finished
	travel_tween = null
	position = finish.round()

func cancel() -> void:
	if travel_tween != null and travel_tween.is_valid():
		travel_tween.kill()
	travel_tween = null
	if is_instance_valid(impact):
		impact.queue_free()
	if is_instance_valid(impact_marker):
		impact_marker.queue_free()
	queue_free()

func play_impact(parent: Node2D, at: Vector2, duration_scale := 1.0, play_profile_sound := true) -> Signal:
	impact_complete = false
	visible = false
	if play_profile_sound:
		_play_sound(profile.impact_sound, profile.impact_volume_db)
	if profile.impact_frames == null:
		impact_marker = ChessCaptureClackEffect.new()
		impact_marker.name = "ChessCaptureClackEffect"
		impact_marker.position = at + profile.impact_offset * world_scale
		parent.add_child(impact_marker)
		impact_marker.configure(world_scale * profile.impact_scale)
		parent.get_tree().create_timer(0.18 * duration_scale).timeout.connect(_finish_impact, CONNECT_ONE_SHOT)
		return impact_finished
	impact = AnimatedSprite2D.new()
	impact.sprite_frames = profile.impact_frames
	impact.animation = profile.impact_animation
	impact.speed_scale = profile.impact_playback_speed / maxf(duration_scale, 0.01)
	impact.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	impact.position = at + profile.impact_offset * world_scale
	impact.scale = Vector2.ONE * profile.impact_scale * world_scale
	impact.z_index = ChessBoardView.BOARD_EFFECT_Z + 3
	impact.z_as_relative = false
	parent.add_child(impact)
	impact.play()
	impact.animation_finished.connect(func():
		impact.queue_free()
		_finish_impact()
	, CONNECT_ONE_SHOT)
	return impact_finished

func wait_for_impact() -> void:
	if impact_complete:
		return
	await impact_finished

func _finish_impact() -> void:
	if impact_complete:
		return
	impact_complete = true
	impact_finished.emit()

func _draw() -> void:
	if not placeholder_mode:
		return
	# Crisp right-facing placeholder; rotation is owned by this Node2D.
	var s: float = world_scale * float(profile.projectile_scale)
	var points := PackedVector2Array()
	for point in [Vector2(-8,-2), Vector2(4,-2), Vector2(4,-5), Vector2(10,0), Vector2(4,5), Vector2(4,2), Vector2(-8,2)]:
		points.append(point * s)
	draw_colored_polygon(points, Color.WHITE)

func _play_sound(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - profile.pitch_variation, 1.0 + profile.pitch_variation)
	add_child(player)
	player.play()
