extends GPUParticles2D

var dismissing := false


func configure_emission_footprint(size: Vector2) -> void:
	var material := process_material as ParticleProcessMaterial
	if material == null:
		return
	# Each anchor has a differently projected square, so keep its material local.
	material = material.duplicate() as ParticleProcessMaterial
	process_material = material
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(size.x * 0.5, size.y * 0.5, 1.0)

func _ready() -> void:
	add_to_group(&"reaction_skull_anchor")
	restart()


func dismiss() -> void:
	if dismissing:
		return
	dismissing = true
	emitting = false
	await get_tree().create_timer(lifetime).timeout
	queue_free()
