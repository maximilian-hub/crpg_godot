extends Resource
class_name ChessMagicalMoveProfile

## Brief, repeatable choreography for a King that moves under its own power.
@export var hand_hover_offset := Vector2(150.0, -180.0)
@export_range(0.01, 2.0, 0.01) var hand_approach_duration := 0.24
@export_range(0.0, 1.0, 0.01) var invocation_duration := 0.14
@export_range(0.0, 1.0, 0.01) var settle_duration := 0.10
@export_range(0.01, 2.0, 0.01) var hand_retreat_duration := 0.24
@export_range(0.01, 2.0, 0.01) var travel_duration := 0.30
@export_range(0.0, 160.0, 1.0) var lift_height := 34.0
@export_range(0.0, 1.0, 0.01) var hand_silhouette_power := 0.45
@export_range(0.0, 1.0, 0.01) var hand_particle_power := 0.20
@export_range(0.0, 1.0, 0.01) var king_silhouette_power := 0.65
@export_range(0.0, 1.0, 0.01) var king_particle_power := 0.35
@export_range(0.01, 2.0, 0.01) var attack_rebound_duration := 0.24
@export_range(0.01, 3.0, 0.01) var knockoff_duration := 0.58
@export_range(0.0, 1080.0, 1.0) var knockoff_arc_height := 180.0
@export_range(0.0, 1440.0, 1.0) var knockoff_side_margin := 180.0
@export_range(0.0, 2160.0, 1.0) var knockoff_spin_degrees := 900.0

