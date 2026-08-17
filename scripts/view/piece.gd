#~~~~~~~~NEW FILE: piece.gd~~~~~~~~~~~~
# Attached to the piece scene.
# The View layer for each piece.

extends Area2D
class_name PieceView

const STANDARD_PIECE_DIRECTORY := "res://assets/pieces/standard/"
const WHITE_PALETTE_SHADER := preload("res://assets/pieces/white_piece_palette.gdshader")

var coordinate: Vector2i
var model: ModelPiece

var sprite: Sprite2D:
	get:
		return get_node("Sprite2D") as Sprite2D

func set_model(model_data: ModelPiece) -> void:
	model = model_data
	update_sprite()

func set_sprite(sprite_name: String) -> void: # "white_queen"
	var color := model.color if model != null else "white"
	var type := sprite_name
	if sprite_name.begins_with("white_"):
		color = "white"
		type = sprite_name.trim_prefix("white_")
	elif sprite_name.begins_with("black_"):
		color = "black"
		type = sprite_name.trim_prefix("black_")
	_apply_piece_art(color, type)

func update_sprite() -> void:
	_apply_piece_art(model.color, model.type)

func _apply_piece_art(color: String, requested_type: String) -> void:
	var standard_type := _get_standard_type(requested_type)
	var authored_path := STANDARD_PIECE_DIRECTORY + color + "_" + standard_type + ".png"
	var uses_authored_color := ResourceLoader.exists(authored_path)
	var texture_path := authored_path if uses_authored_color else STANDARD_PIECE_DIRECTORY + "black_" + standard_type + ".png"
	sprite.texture = load(texture_path)
	sprite.scale = Vector2.ONE
	sprite.material = null
	if color == "white" and not uses_authored_color:
		var white_material := ShaderMaterial.new()
		white_material.shader = WHITE_PALETTE_SHADER
		sprite.material = white_material
	align_sprite_to_ground()

func _get_standard_type(requested_type: String) -> String:
	if requested_type == "bone_pawn":
		return "pawn"
	if requested_type == "king" or requested_type == "classic_king" or requested_type.ends_with("_king"):
		return "king"
	if requested_type in ["pawn", "rook", "knight", "bishop", "queen"]:
		return requested_type
	push_warning("Unknown piece art type '%s'; using pawn art." % requested_type)
	return "pawn"

func align_sprite_to_ground() -> void:
	if sprite == null or sprite.texture == null:
		return
	var displayed_height := float(sprite.texture.get_height()) * absf(sprite.scale.y)
	sprite.position = Vector2(0.0, -displayed_height * 0.5)
	_update_effect_anchors()

func _update_effect_anchors() -> void:
	get_ground_anchor().position = Vector2.ZERO
	get_body_anchor().position = sprite.position
	get_head_anchor().position = Vector2(0.0, get_sprite_top_local_y())

func get_ground_anchor() -> Marker2D:
	return get_node("GroundAnchor") as Marker2D

func get_body_anchor() -> Marker2D:
	return get_node("BodyAnchor") as Marker2D

func get_head_anchor() -> Marker2D:
	return get_node("HeadAnchor") as Marker2D

func get_anchor_position_in(target_parent: Node2D, anchor: Node2D) -> Vector2:
	return target_parent.to_local(anchor.global_position)

func get_sprite_top_local_y() -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	var displayed_height := float(sprite.texture.get_height()) * absf(sprite.scale.y)
	return sprite.position.y - displayed_height * 0.5

func get_sprite_bottom_local_y() -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	var displayed_height := float(sprite.texture.get_height()) * absf(sprite.scale.y)
	return sprite.position.y + displayed_height * 0.5

func update_hp(new_hp: int) -> void:
	if has_node("HpBar"):
		$HpBar.set_hp(new_hp, model.max_hp)
