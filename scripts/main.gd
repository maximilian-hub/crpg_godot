extends Node

func _ready():
	var startup_menu = load("res://scenes/startup_menu.tscn").instantiate()
	add_child(startup_menu)
