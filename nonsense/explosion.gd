extends AnimatedSprite2D

func _ready():
	play("explode") # Optional if you didn’t check “Autoplay on Load”

func _on_animation_finished():
	print("animation finished.")
	queue_free()
