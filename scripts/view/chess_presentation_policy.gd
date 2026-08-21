extends Resource
class_name ChessPresentationPolicy

enum Speed { SLOW, NORMAL, FAST, INSTANT }

@export var speed := Speed.NORMAL
@export_range(1.0, 4.0, 0.1) var slow_duration_scale := 4.0
@export_range(0.01, 1.0, 0.01) var fast_duration_scale := 0.2
@export var play_sounds_in_instant := false

func duration_scale() -> float:
	match speed:
		Speed.SLOW:
			return slow_duration_scale
		Speed.FAST:
			return fast_duration_scale
		_:
			return 1.0

func should_animate() -> bool:
	return speed != Speed.INSTANT

func should_hold_completion_gate() -> bool:
	return should_animate()
