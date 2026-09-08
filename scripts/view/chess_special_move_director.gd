extends Node2D
class_name ChessSpecialMoveDirector

signal projectile_landed(index: int, final_hit: bool)
signal projectile_launched(index: int, final_hit: bool)
signal gameplay_impact_reached
signal final_projectile_landed
signal all_projectiles_finished
signal final_impact_sound_selected(cue: StringName)

var board: ChessBoardView
var source: PieceView
var target: PieceView
var profile: ChessSpecialMovePresentationProfile
var duration_scale := 1.0
var rng := RandomNumberGenerator.new()
var active_projectiles: Array[ChessProjectileEffect] = []
var active_tween: Tween
var cancelled := false
var final_landed := false
var outstanding_projectiles := 0


func configure(board_view: ChessBoardView, source_view: PieceView, target_view: PieceView, value: ChessSpecialMovePresentationProfile, playback_scale: float, seed: int) -> void:
	board = board_view
	source = source_view
	target = target_view
	profile = value
	duration_scale = maxf(playback_scale, 0.01)
	rng.seed = seed


func play_until_gameplay_impact() -> void:
	var cue := ChessSpecialMoveSourceCue.new()
	cue.position = source.get_anchor_position_in(board, source.get_body_anchor())
	add_child(cue)
	cue.configure(profile, board.get_world_scale(), rng.randi())
	await cue.play(duration_scale)
	if cancelled:
		return
	cue.queue_free()
	var shot_count := maxi(profile.projectile_count, 1)
	final_landed = false
	outstanding_projectiles = shot_count
	for shot in range(shot_count):
		var final_hit := shot == shot_count - 1
		_run_projectile(shot, final_hit)
		projectile_launched.emit(shot, final_hit)
		if shot < shot_count - 1 and profile.shot_interval > 0.0:
			await get_tree().create_timer(profile.shot_interval * duration_scale).timeout
			if cancelled:
				return
	if not final_landed:
		await final_projectile_landed


func play_aftermath(target_defeated: bool, target_is_king: bool) -> void:
	if cancelled:
		return
	if target_defeated and not target_is_king and is_instance_valid(target):
		board.play_default_capture_clack_sound()
		final_impact_sound_selected.emit(&"capture_clack")
		await _play_knockoff()
	else:
		_play_final_hit_sound()
		final_impact_sound_selected.emit(&"spike_hit")
	if outstanding_projectiles > 0:
		await all_projectiles_finished


func cancel() -> void:
	cancelled = true
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
	for projectile in active_projectiles.duplicate():
		if is_instance_valid(projectile):
			projectile.cancel()
	active_projectiles.clear()
	outstanding_projectiles = 0
	queue_free()


func _run_projectile(index: int, is_final: bool) -> void:
	var projectile_profile := profile.resolved_projectile_profile()
	var world_scale := board.get_world_scale()
	var start: Vector2 = source.get_anchor_position_in(board, source.get_body_anchor()) + projectile_profile.launch_offset * world_scale
	var finish: Vector2 = target.get_anchor_position_in(board, target.get_body_anchor())
	var direction := (finish - start).normalized()
	var tangent := Vector2(-direction.y, direction.x)
	var path_offset := tangent * shot_tangent_offset(index, maxi(profile.projectile_count, 1), profile.volley_tangent_offset) * world_scale
	start += path_offset
	finish += path_offset
	var projectile := ChessProjectileEffect.new()
	projectile.name = "ChessProjectileEffect"
	active_projectiles.append(projectile)
	board.add_child(projectile)
	projectile.configure(projectile_profile, world_scale)
	await projectile.fly(start, finish, duration_scale)
	if cancelled:
		return
	projectile.play_impact(board, finish, duration_scale, not is_final)
	projectile_landed.emit(index, is_final)
	if is_final:
		final_landed = true
		gameplay_impact_reached.emit()
		final_projectile_landed.emit()
	await projectile.wait_for_impact()
	if is_instance_valid(projectile):
		projectile.queue_free()
	active_projectiles.erase(projectile)
	outstanding_projectiles = maxi(outstanding_projectiles - 1, 0)
	if outstanding_projectiles == 0:
		all_projectiles_finished.emit()


static func shot_tangent_offset(index: int, count: int, amount: float) -> float:
	# The final, gameplay-bearing projectile always uses the true aim line.
	if index >= maxi(count, 1) - 1:
		return 0.0
	# Earlier projectiles alternate predictably across the aim line.
	return -amount if index % 2 == 0 else amount


func _play_final_hit_sound() -> void:
	var projectile_profile := profile.resolved_projectile_profile()
	if projectile_profile.impact_sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "SpecialMoveFinalHitSound"
	player.bus = &"SFX"
	player.stream = projectile_profile.impact_sound
	player.volume_db = projectile_profile.impact_volume_db
	player.pitch_scale = rng.randf_range(1.0 - projectile_profile.pitch_variation, 1.0 + projectile_profile.pitch_variation)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _play_knockoff() -> void:
	var projectile_profile := profile.resolved_projectile_profile()
	var world_scale := board.get_world_scale()
	var trajectory := ChessKingMagicController.build_ballistic_knockoff(
		source.position, target.position, target.position, board.get_viewport_rect().size,
		ChessKingMagicController.piece_visual_radius(target), projectile_profile.knockoff_horizontal_speed * world_scale,
		projectile_profile.knockoff_upward_speed * world_scale, projectile_profile.knockoff_gravity * world_scale, rng)
	var side: int = trajectory.side
	var origin := target.position
	var rotation_start := target.rotation
	target.z_index = ChessBoardView.BOARD_EFFECT_Z + 1
	active_tween = create_tween()
	active_tween.tween_method(func(time: float):
		target.position = ChessKingMagicController.ballistic_position(origin, trajectory.initial_velocity, trajectory.gravity, time).round()
		target.rotation = rotation_start + deg_to_rad(projectile_profile.knockoff_angular_speed * side) * time
	, 0.0, trajectory.duration, trajectory.duration * duration_scale)
	await active_tween.finished
	active_tween = null
