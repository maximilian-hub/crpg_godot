extends Resource
class_name ChessSetupLabPreset

const CURRENT_SCHEMA_VERSION := 1

@export var schema_version := CURRENT_SCHEMA_VERSION
@export var display_name := ""
@export var setup_profile: ChessArmySetupProfile
@export var activation_preset_path := ""
@export var activation_snapshot: Resource


func is_supported() -> bool:
	return schema_version > 0 and schema_version <= CURRENT_SCHEMA_VERSION and setup_profile != null
