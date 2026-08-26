extends Resource
class_name ChessAuraLabPreset

const CURRENT_SCHEMA_VERSION := 1

@export var schema_version := CURRENT_SCHEMA_VERSION
@export var display_name := ""
@export var aura_profile: ChessAuraProfile
@export var aura_mode := ChessAura2D.AuraMode.HYBRID
@export var target_mode := 0
@export_range(0.0, 1.0, 0.01) var king_power := 0.0
@export_range(0.0, 1.0, 0.01) var hand_power := 0.0
@export var hand_grip_y_offset := 0.0
@export var king_type_id: StringName = &"minotaur_king"
@export_enum("white", "black") var army_color := "white"


func is_supported() -> bool:
	return schema_version > 0 and schema_version <= CURRENT_SCHEMA_VERSION and aura_profile != null


static func safe_file_stem(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	var result := ""
	var last_was_separator := false
	for character in normalized:
		var allowed := character in "abcdefghijklmnopqrstuvwxyz0123456789-_"
		if allowed:
			result += character
			last_was_separator = false
		elif not last_was_separator and not result.is_empty():
			result += "_"
			last_was_separator = true
	return result.trim_suffix("_")

