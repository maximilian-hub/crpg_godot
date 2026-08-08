#~~~~~~~~ NEW FILE: necromancer_king.gd ~~~~~~~~
extends KingPiece
class_name NecromancerKing

const BonePawn = preload("res://scripts/pieces/bone_pawn.gd")

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

func has_active_ability() -> bool:
	return true

## Executes Summon Bone Pawn, but does not end the turn.
## The Model's action resolver finishes the action after all reactions resolve.
func active_target_selected(target: Vector2i):
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
