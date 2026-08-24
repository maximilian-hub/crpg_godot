extends RefCounted
class_name ChessPieceCatalog

const DEFINITIONS := {
	&"pawn": {"name": "Pawn", "script": preload("res://scripts/pieces/pawn.gd"), "art": &"pawn", "palette": true, "palette_group": &"ordinary", "palette_order": 0},
	&"knight": {"name": "Knight", "script": preload("res://scripts/pieces/knight.gd"), "art": &"knight", "palette": true, "palette_group": &"ordinary", "palette_order": 1},
	&"bishop": {"name": "Bishop", "script": preload("res://scripts/pieces/bishop.gd"), "art": &"bishop", "palette": true, "palette_group": &"ordinary", "palette_order": 2},
	&"rook": {"name": "Rook", "script": preload("res://scripts/pieces/rook.gd"), "art": &"rook", "palette": true, "palette_group": &"ordinary", "palette_order": 3},
	&"queen": {"name": "Queen", "script": preload("res://scripts/pieces/queen.gd"), "art": &"queen", "palette": true, "palette_group": &"ordinary", "palette_order": 4},
	&"classic_king": {"name": "Classic King", "script": preload("res://scripts/pieces/classic_king.gd"), "art": &"king", "palette": true, "palette_group": &"king", "palette_order": 0},
	&"arakne_king": {"name": "Arakne King", "script": preload("res://scripts/pieces/arakne_king.gd"), "art": &"king", "palette": true, "palette_group": &"king", "palette_order": 1},
	&"minotaur_king": {"name": "Minotaur King", "script": preload("res://scripts/pieces/minotaur_king.gd"), "art": &"minotaur_king", "palette": true, "palette_group": &"king", "palette_order": 2},
	&"necromancer_king": {"name": "Necromancer King", "script": preload("res://scripts/pieces/necromancer_king.gd"), "art": &"necromancer_king", "palette": true, "palette_group": &"king", "palette_order": 3},
	&"bone_pawn": {"name": "Bone Pawn", "script": preload("res://scripts/pieces/bone_pawn.gd"), "art": &"pawn", "palette": false, "palette_group": &"hidden", "palette_order": 0},
}

static func normalize_type_id(type_id: StringName) -> StringName:
	return &"classic_king" if type_id == &"king" else type_id

static func has_type(type_id: StringName) -> bool:
	return DEFINITIONS.has(normalize_type_id(type_id))

static func get_definition(type_id: StringName) -> Dictionary:
	return DEFINITIONS.get(normalize_type_id(type_id), {}).duplicate()

static func get_type_ids(include_hidden := false) -> Array[StringName]:
	var result: Array[StringName] = []
	for type_id in DEFINITIONS:
		if include_hidden or DEFINITIONS[type_id]["palette"]:
			result.append(type_id)
	result.sort()
	return result

static func get_palette_type_ids(group: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for type_id in DEFINITIONS:
		var definition: Dictionary = DEFINITIONS[type_id]
		if definition.get("palette", false) and definition.get("palette_group", &"") == group:
			result.append(type_id)
	result.sort_custom(func(a: StringName, b: StringName): return int(DEFINITIONS[a].get("palette_order", 0)) < int(DEFINITIONS[b].get("palette_order", 0)))
	return result

static func create_piece(type_id: StringName, color: String, coordinate: Vector2i) -> ModelPiece:
	var normalized := normalize_type_id(type_id)
	if not DEFINITIONS.has(normalized) or color not in ["white", "black"]:
		return null
	var script: Script = DEFINITIONS[normalized]["script"]
	var piece: ModelPiece = script.new(color, coordinate)
	return piece
