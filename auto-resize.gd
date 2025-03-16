extends Control

func _ready():
	_resize()
	get_viewport().connect("size_changed", Callable(self, "_resize"))

func _resize():
	size = get_viewport_rect().size  # Update size to match the viewport
