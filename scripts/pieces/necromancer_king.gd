#~~~~~~~~ NEW FILE: necromancer_king.gd ~~~~~~~~
extends KingPiece
class_name NecromancerKing

const BonePawn = preload("res://scripts/pieces/bone_pawn.gd")
var SkullAura = preload("res://effects/skull_aura.tscn")
var skull_aura_instance: Node = null

func _init(color: String, coord: Vector2i):
	super._init(color, coord)
	self.type = "necromancer_king"
	self.max_hp = 2
	self.current_hp = self.max_hp
	self.base_cooldown = 2
	self.active_ability_name = "Summon Bone Pawn"
	self.passive_ability_name = "Raise Dead"

func get_active_ability_targets() -> Array:
	return model.get_empty_squares_to_furthest_rank(self.color)

## Executes the active summon, but does not end the turn.
## The Model's action resolver finishes the action after all reactions resolve.
func active_target_selected(target: Vector2i):
	remove_aura()
	summon_bone_pawn(target)
	reset_cooldown()

func summon_bone_pawn(target: Vector2i):
	var new_pawn := BonePawn.new(self.color, target)
	model.add_piece(new_pawn, target)

func _on_piece_destroyed(destroyed_piece: ModelPiece):
	for base_type in model.MAJOR_MINOR_BASE_TYPES:
		if destroyed_piece.type.contains(base_type):
			raise_dead(destroyed_piece.coordinate)
			return

func raise_dead(death_square: Vector2i):
	model.queue_selection_opportunity(self, "raise_dead", death_square)

func get_selection_targets(action_type: String, event_data) -> Array:
	if action_type == "raise_dead":
		var death_square: Vector2i = event_data
		return model.get_empty_adjacent_squares(death_square)
	return []

## Called by the action resolver after this Necromancer's reaction target is chosen.
func _on_special_target_selected(coord: Vector2i):
	summon_bone_pawn(coord)

## TODO: move to view script
func apply_aura():
	print("apply_aura()")
	if not is_instance_valid(view_node):
		return

	if not is_instance_valid(skull_aura_instance):
		skull_aura_instance = SkullAura.instantiate()
		view_node.add_child(skull_aura_instance)

	# Restart the existing particle effect whenever targeting begins.
	skull_aura_instance.restart()
	skull_aura_instance.emitting = true

## TODO: move to view script
func remove_aura():
	if is_instance_valid(skull_aura_instance):
		skull_aura_instance.emitting = false

func _on_selection_processing_start(piece: ModelPiece):
	print("NK notified of selection process starting. checking if it's for me...")
	if piece == self:
		apply_aura()

func _on_selection_processing_end():
	remove_aura()

func _on_active_selected():
	apply_aura()

func _on_active_deselected(play_powerdown_sound: bool = false):
	remove_aura()
	if play_powerdown_sound:
		pass # add sound
