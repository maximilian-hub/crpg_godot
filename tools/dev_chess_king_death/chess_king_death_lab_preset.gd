extends Resource
class_name ChessKingDeathLabPreset

const CURRENT_SCHEMA_VERSION := 1

@export var schema_version := CURRENT_SCHEMA_VERSION
@export var display_name := ""
@export var death_profile: Resource


func is_supported() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION and death_profile != null

