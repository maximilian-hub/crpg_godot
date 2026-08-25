extends Resource
class_name ChessAuraProfile

## Shared tuning for silhouette resonance and rising chess-square motes.

@export var core_color := Color("fff2b0")
@export var accent_color := Color("72d8ff")
@export_range(0.0, 4.0, 0.25) var outline_width := 1.0
@export_range(0.0, 2.0, 0.05) var outline_intensity := 0.9
@export_range(0.0, 2.0, 0.05) var interior_intensity := 0.45
@export_range(0.5, 8.0, 0.5) var square_size := 2.0
@export_range(0.0, 160.0, 1.0) var square_density := 48.0
@export_range(0.05, 3.0, 0.05) var square_lifetime := 0.8
@export_range(0.0, 160.0, 1.0) var rise_speed := 42.0
@export_range(0.0, 120.0, 1.0) var horizontal_spread := 22.0
@export_range(0.0, 160.0, 1.0) var upward_acceleration := 24.0
@export_range(0.0, 80.0, 1.0) var turbulence := 8.0
@export_range(0.0, 1.0, 0.01) var idle_power := 0.0
@export_range(0.01, 4.0, 0.01) var power_up_duration := 0.65
@export_range(0.01, 4.0, 0.01) var power_down_duration := 0.55
@export var random_seed := 1701

