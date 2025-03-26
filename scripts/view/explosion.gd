extends AnimatedSprite2D

func _ready():
	play("explode") # Optional if you didn’t check “Autoplay on Load”
	$AudioStreamPlayer2D.pitch_scale = randf_range(0.75, 1.25)
	$AudioStreamPlayer2D.play()

func _on_animation_finished():
	queue_free()
