extends Resource
class_name ChessKingCooldownPresentationProfile

@export_group("Motes")
@export_range(1.0, 16.0, 0.5) var mote_size := 4.0
@export_range(0.0, 1.0, 0.01) var mote_opacity := 0.78
@export var anchor_offset := Vector2.ZERO
@export var orbit_radius := Vector2(54.0, 22.0)
@export_range(-3.0, 3.0, 0.01) var orbit_speed := 0.34
@export_range(0.0, 20.0, 0.25) var hover_amplitude := 3.0
@export_range(0.0, 8.0, 0.05) var hover_frequency := 1.15
@export_range(0.0, 1.0, 0.01) var hover_variation := 0.22
@export_range(1, 24, 1) var motes_per_ring := 8
@export_range(0.0, 80.0, 1.0) var ring_spacing := 16.0

@export_group("Following")
@export_range(0.0, 500.0, 1.0) var follow_base_speed := 55.0
@export_range(0.0, 20.0, 0.05) var follow_distance_gain := 4.0
@export_range(1.0, 1200.0, 1.0) var follow_max_speed := 420.0
@export_range(1.0, 2400.0, 1.0) var follow_acceleration := 900.0
@export_range(0.0, 40.0, 0.1) var arrival_smoothing := 10.0
@export_range(0.0, 20.0, 0.1) var formation_angular_smoothing := 5.0

@export_group("Transitions")
@export_range(0.01, 3.0, 0.01) var release_duration := 0.55
@export_range(0.01, 3.0, 0.01) var absorption_duration := 0.48
@export_range(0.0, 1.0, 0.01) var absorption_stagger := 0.1
@export_range(0.0, 2.0, 0.01) var absorption_curve_strength := 0.72
@export_range(0.0, 200.0, 1.0) var absorption_outward_distance := 62.0
@export_range(1.0, 1.5, 0.005) var pulse_scale := 1.055
@export_range(0.01, 1.5, 0.01) var pulse_duration := 0.24

@export_group("Ready Aura")
@export_range(0.0, 1.0, 0.01) var ready_silhouette_power := 0.58
@export_range(0.0, 1.0, 0.01) var ready_particle_power := 0.2
@export_range(0.0, 4.0, 0.05) var ready_density_multiplier := 1.35
@export_range(0.0, 4.0, 0.05) var ready_speed_multiplier := 0.8
@export_range(0.0, 0.5, 0.01) var ready_brightening_intensity := 0.1
@export_range(0.1, 12.0, 0.1) var ready_brightening_period := 4.5
@export_range(0.05, 1.0, 0.01) var ready_brightening_fraction := 0.24

@export_group("Selection Orb")
@export var selection_orb_offset := Vector2(0.0, 10.0)
@export_range(2.0, 64.0, 0.5) var selection_orb_size := 13.0
@export_range(0.0, 1.0, 0.01) var selection_orb_opacity := 0.68
@export_range(0.0, 8.0, 0.05) var selection_orb_speed := 1.15

@export_group("Audio")
@export var charge_sound: AudioStream
@export var absorption_sound: AudioStream
@export var completion_sound: AudioStream
@export var selection_sound: AudioStream
@export_range(-60.0, 6.0, 0.5) var charge_volume_db := -18.0
@export_range(-60.0, 6.0, 0.5) var absorption_volume_db := -16.0
@export_range(-60.0, 6.0, 0.5) var completion_volume_db := -12.0
@export_range(-60.0, 6.0, 0.5) var selection_volume_db := -18.0
