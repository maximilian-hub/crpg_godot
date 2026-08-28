extends Resource
class_name ChessActivationLabPreset

const CURRENT_SCHEMA_VERSION := 3

@export var schema_version := CURRENT_SCHEMA_VERSION
@export var display_name := ""
@export var activation_profile: Resource
@export var aura_preset_path := ""
@export var aura_preset_name := ""
@export var aura_snapshot: Resource
@export var aura_mode := ChessAura2D.AuraMode.HYBRID
@export var king_type_id: StringName = &"minotaur_king"
@export_enum("white", "black") var army_color := "white"
## Deprecated schema-one/two fields. Hover placement now lives in the shared
## activation profile as hand_hover_offset so every preview uses king-relative
## coordinates. Keep these serialized fields so old presets remain loadable.
@export_storage var hand_grip_y_offset := 0.0
@export_storage var hand_grip_x_offset := 0.0


func is_supported() -> bool:
	return schema_version > 0 and schema_version <= CURRENT_SCHEMA_VERSION and activation_profile != null and aura_snapshot != null
