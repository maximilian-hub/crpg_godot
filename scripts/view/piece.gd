#~~~~~~~~NEW FILE: piece.gd~~~~~~~~~~~~
# Attached to the piece scene.
# The View layer for each piece.

extends Area2D
class_name PieceView

var coordinate: Vector2i
var model: ModelPiece

var sprite: Sprite2D:
	get:
		return get_node("Sprite2D") as Sprite2D

func set_model(model_data: ModelPiece) -> void:
	model = model_data
	update_sprite()

func set_sprite(sprite_name: String) -> void: # "white_queen"
	sprite.texture = load("res://assets/pieces/" + sprite_name + ".png")
	align_sprite_to_ground()

func update_sprite() -> void:
	var sprite_name = model.color + "_" + model.type
	sprite.texture = load("res://assets/pieces/" + sprite_name + ".png")
	sprite.scale = Vector2.ONE

	#TODO: This feels really bad lmao. Standardize your image sizes or some sh*t.
	if model.type == "minotaur_king":
		sprite.scale = Vector2(0.5, 0.5)
	elif model.type == "bone_pawn":
		sprite.scale = Vector2(0.11, 0.11)
	elif model.type == "necromancer_king":
		sprite.scale = Vector2(0.13,0.13)
	elif model.type == "arakne_king":
		sprite.scale = Vector2(0.5,0.5)
	align_sprite_to_ground()

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
