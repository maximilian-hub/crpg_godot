extends Sprite2D

var dragging: bool = false  # Track whether the piece is being dragged

func _input(event):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Check if the mouse is over this piece
			if get_rect().has_point(to_local(event.position)):
				dragging = true  # Start dragging
				set_z_index(10)  # Move piece on top of other objects (optional)
	
		elif not event.pressed:
			dragging = false  # Stop dragging
			set_z_index(1)  # Reset z-index (optional)
	
	if event is InputEventMouseMotion and dragging:
		global_position = event.position  # Move piece with the mouse
