extends Resource
class_name ChessPresentationPolicy

enum Speed { ULTRA_SLOW, SLOW, NORMAL, FAST, INSTANT }

@export var speed := Speed.NORMAL
@export_range(4.0, 12.0, 0.1) var ultra_slow_duration_scale := 8.0
@export_range(1.0, 4.0, 0.1) var slow_duration_scale := 4.0
@export_range(0.01, 1.0, 0.01) var fast_duration_scale := 0.2
@export var play_sounds_in_instant := false

func duration_scale() -> float:
	match speed:
		Speed.ULTRA_SLOW:
			return ultra_slow_duration_scale
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
