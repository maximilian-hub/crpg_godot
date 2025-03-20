extends Node

func _ready():
	var chess_game = load("res://scenes/chess_game.tscn").instantiate()
	add_child(chess_game)
