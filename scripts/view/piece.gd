#~~~~~~~~NEW FILE: piece.gd~~~~~~~~~~~~
# Attached to the piece scene.
# The View layer for each piece.

extends Area2D
class_name PieceView

const WHITE_PALETTE_SHADER := preload("res://assets/pieces/profiles/white_piece_palette.gdshader")
const PIECE_ART_PROFILES := {
	&"pawn": preload("res://assets/pieces/profiles/pawn.tres"),
	&"rook": preload("res://assets/pieces/profiles/rook.tres"),
	&"knight": preload("res://assets/pieces/profiles/knight.tres"),
	&"bishop": preload("res://assets/pieces/profiles/bishop.tres"),
	&"queen": preload("res://assets/pieces/profiles/queen.tres"),
	&"king": preload("res://assets/pieces/profiles/king.tres"),
	&"arakne_king": preload("res://assets/pieces/profiles/arakne_king.tres"),
	&"minotaur_king": preload("res://assets/pieces/profiles/minotaur_king.tres"),
	&"necromancer_king": preload("res://assets/pieces/profiles/necromancer_king.tres"),
}

var coordinate: Vector2i
var model: ModelPiece
var art_profile: Resource
var show_grip_anchor_debug := false
var grip_anchor_debug_overlay: Node2D = null

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
	var art_id := _get_art_id(requested_type)
	art_profile = PIECE_ART_PROFILES.get(art_id, PIECE_ART_PROFILES[&"pawn"])
	var selected_texture: Texture2D = art_profile.texture_for_color(color)
	sprite.texture = selected_texture
	sprite.scale = Vector2.ONE * art_profile.texture_scale(selected_texture)
	sprite.material = null
	if color == "white" and art_profile.white_texture == null:
		var white_material := ShaderMaterial.new()
		white_material.shader = WHITE_PALETTE_SHADER
		sprite.material = white_material
	align_sprite_to_ground()

func _get_art_id(requested_type: String) -> StringName:
	var definition := ChessPieceCatalog.get_definition(StringName(requested_type))
	if not definition.is_empty():
		return definition.get("art", &"pawn")
	push_warning("Unknown piece art type '%s'; using pawn art." % requested_type)
	return &"pawn"

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
	get_grip_anchor().position = art_profile.grip_anchor if art_profile != null else get_head_anchor().position
	_sync_grip_anchor_debug_overlay()

func get_ground_anchor() -> Marker2D:
	return get_node("GroundAnchor") as Marker2D

func get_body_anchor() -> Marker2D:
	return get_node("BodyAnchor") as Marker2D

func get_head_anchor() -> Marker2D:
	return get_node("HeadAnchor") as Marker2D

func get_grip_anchor() -> Marker2D:
	return get_node("GripAnchor") as Marker2D

func set_grip_anchor_debug_visible(enabled: bool) -> void:
	show_grip_anchor_debug = enabled
	_sync_grip_anchor_debug_overlay()

func _sync_grip_anchor_debug_overlay() -> void:
	if grip_anchor_debug_overlay == null:
		grip_anchor_debug_overlay = Node2D.new()
		grip_anchor_debug_overlay.name = "GripAnchorDebugOverlay"
		grip_anchor_debug_overlay.z_index = 1000
		for points in [PackedVector2Array([Vector2(-4, 0), Vector2(4, 0)]), PackedVector2Array([Vector2(0, -4), Vector2(0, 4)])]:
			var line := Line2D.new()
			line.points = points
			line.width = 1.0
			line.default_color = Color(1.0, 0.0, 0.8, 1.0)
			line.antialiased = true
			grip_anchor_debug_overlay.add_child(line)
		add_child(grip_anchor_debug_overlay)
	grip_anchor_debug_overlay.position = get_grip_anchor().position
	grip_anchor_debug_overlay.visible = show_grip_anchor_debug

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
