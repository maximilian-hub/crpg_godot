extends Node2D
class_name ChessSquareEmitter2D

## Lightweight, deterministic pixel-square emitter whose spawn points are
## sampled from the opaque pixels of a source Sprite2D.

var profile: ChessAuraProfile
var source_sprite: Sprite2D
var power := 0.0
var enabled := true
var particles: Array[Dictionary] = []
var opaque_points := PackedVector2Array()
var spawn_budget := 0.0
var elapsed := 0.0
var rng := RandomNumberGenerator.new()
var cached_texture: Texture2D
var density_multiplier := 1.0
var speed_multiplier := 1.0
var simulation_speed := 1.0
var continuous_emission_enabled := true


func configure(source: Sprite2D, aura_profile: ChessAuraProfile, seed_offset := 0) -> void:
	source_sprite = source
	profile = aura_profile
	rng.seed = profile.random_seed + seed_offset
	_rebuild_opaque_points()
	set_process(true)


func set_emission_power(value: float) -> void:
	power = clampf(value, 0.0, 1.0)


func set_runtime_multipliers(density: float, speed: float) -> void:
	density_multiplier = maxf(density, 0.0)
	speed_multiplier = maxf(speed, 0.0)


func emit_burst(count: int, burst_power := 1.0) -> void:
	if opaque_points.is_empty():
		return
	var previous_power := power
	power = clampf(burst_power, 0.0, 1.0)
	for _index in range(maxi(count, 0)):
		_spawn_square()
	power = previous_power
	queue_redraw()


func set_simulation_speed(value: float) -> void:
	simulation_speed = maxf(value, 0.0)


func set_continuous_emission_enabled(value: bool) -> void:
	continuous_emission_enabled = value


func clear_particles() -> void:
	particles.clear()
	spawn_budget = 0.0
	queue_redraw()


func active_particle_count() -> int:
	return particles.size()


func _process(delta: float) -> void:
	delta *= simulation_speed
	if delta <= 0.0:
		return
	if profile == null or not is_instance_valid(source_sprite):
		return
	if source_sprite.texture != cached_texture:
		_rebuild_opaque_points()
	elapsed += delta
	if enabled and continuous_emission_enabled and power > 0.0 and not opaque_points.is_empty():
		spawn_budget += profile.square_density * density_multiplier * power * delta
		while spawn_budget >= 1.0:
			_spawn_square()
			spawn_budget -= 1.0
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) >= float(particle["lifetime"]):
			particles.remove_at(index)
			continue
		var velocity: Vector2 = particle["velocity"]
		velocity.y -= profile.upward_acceleration * delta
		particle["velocity"] = velocity
		var wobble := sin(elapsed * 8.0 + float(particle["phase"])) * profile.turbulence
		particle["position"] = Vector2(particle["position"]) + (velocity + Vector2(wobble, 0.0)) * delta
		particles[index] = particle
	queue_redraw()


func _spawn_square() -> void:
	var point := opaque_points[rng.randi_range(0, opaque_points.size() - 1)]
	var power_speed := lerpf(0.35, 1.0, power)
	particles.append({
		"position": point,
		"velocity": Vector2(
			rng.randf_range(-profile.horizontal_spread, profile.horizontal_spread) * power,
			-profile.rise_speed * speed_multiplier * power_speed * rng.randf_range(0.75, 1.25)
		),
		"age": 0.0,
		"lifetime": profile.square_lifetime * rng.randf_range(0.75, 1.2),
		"size": profile.square_size * rng.randf_range(0.75, 1.5),
		"mix": rng.randf(),
		"phase": rng.randf_range(0.0, TAU),
	})


func _rebuild_opaque_points() -> void:
	opaque_points.clear()
	cached_texture = source_sprite.texture if is_instance_valid(source_sprite) else null
	if cached_texture == null:
		return
	var image := cached_texture.get_image()
	if image == null or image.is_empty():
		return
	var size := image.get_size()
	var origin := Vector2.ZERO if not source_sprite.centered else -Vector2(size) * 0.5
	origin += source_sprite.offset
	# Sampling every other source pixel keeps setup cheap while retaining the
	# silhouette of 64/128-pixel artwork.
	for y in range(0, size.y, 2):
		for x in range(0, size.x, 2):
			if image.get_pixel(x, y).a > 0.2:
				opaque_points.append(origin + Vector2(x + 0.5, y + 0.5))


func _draw() -> void:
	if profile == null:
		return
	for particle in particles:
		var life_progress := float(particle["age"]) / float(particle["lifetime"])
		var fade := 1.0 - smoothstep(0.55, 1.0, life_progress)
		var color := profile.core_color.lerp(profile.accent_color, float(particle["mix"]))
		color.a *= fade * maxf(power, 0.35)
		var size := float(particle["size"])
		var position := Vector2(particle["position"]).round()
		draw_rect(Rect2(position - Vector2.ONE * size * 0.5, Vector2.ONE * size), color)
