extends Resource
class_name ChessAbilityPresentationCatalog

const Entry := preload("res://scripts/view/chess_ability_presentation_entry.gd")
@export var entries: Array[Resource] = []

func find_profile(piece_type_id: StringName, ability_id: StringName) -> Resource:
	var normalized := ChessPieceCatalog.normalize_type_id(piece_type_id)
	for entry in entries:
		if entry != null and ChessPieceCatalog.normalize_type_id(entry.piece_type_id) == normalized and entry.ability_id == ability_id:
			return entry.resolved_profile()
	return null

func upsert(piece_type_id: StringName, ability_id: StringName, profile: Resource) -> void:
	var normalized := ChessPieceCatalog.normalize_type_id(piece_type_id)
	var published_profile := profile.duplicate(true)
	_restore_external_resources(profile, published_profile)
	for entry in entries:
		if entry != null and ChessPieceCatalog.normalize_type_id(entry.piece_type_id) == normalized and entry.ability_id == ability_id:
			entry.presentation_profile = published_profile
			entry.projectile_profile = null
			return
	var entry := Entry.new()
	entry.piece_type_id = normalized
	entry.ability_id = ability_id
	entry.presentation_profile = published_profile
	entries.append(entry)


func _restore_external_resources(source: Resource, destination: Resource) -> void:
	for property in source.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var property_name: StringName = property.name
		var source_value = source.get(property_name)
		if not (source_value is Resource):
			continue
		var source_resource := source_value as Resource
		if not source_resource.resource_path.is_empty():
			destination.set(property_name, source_resource)
			continue
		var destination_resource := destination.get(property_name) as Resource
		if destination_resource != null:
			_restore_external_resources(source_resource, destination_resource)
