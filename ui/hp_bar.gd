extends Node2D

@export var max_hp := 4
var current_hp := 4

@onready var foreground = $Foreground

func _ready():
	pass
	
func set_hp(hp: int, maxhp: int = -1):
	if maxhp != -1:
		max_hp = maxhp
	current_hp = clamp(hp, 0, max_hp)
	_update_bar()

func _update_bar():
	var percent = float(current_hp) / max_hp
	if foreground == null:
		print("foreground is null?!?!?!?") # this is not printing
	
	var tween = create_tween()
	tween.tween_property(
		foreground,
		"scale:x",
		percent * 40,
		0.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
