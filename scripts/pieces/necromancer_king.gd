#~~~~~~~~ NEW FILE: necromancer_king.gd ~~~~~~~~
extends KingPiece # and KingPiece extends ModelPiece
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

# --- Overridden Methods ---

## Active: Summon Bone Pawn - Find empty squares up to the furthest rank occupied.
func get_active_ability_targets() -> Array:
	return model.get_empty_squares_to_furthest_rank(self.color)

## Active: Execute the Summon Bone Pawn ability.
func active_target_selected(target: Vector2i):
	remove_aura()
	summon_bone_pawn(target)
	reset_cooldown() 
	model.switch_turn() 

func summon_bone_pawn(target: Vector2i):
	var new_pawn = BonePawn.new(self.color, target)
	new_pawn.model = self.model 
	new_pawn.view = self.view   
	model.connect("turn_changed", new_pawn._on_turn_changed)
	model.board[target.x][target.y] = new_pawn
	view.draw_piece(new_pawn) 
	
	#if new_pawn._on_dead_row(): model.destroy(new_pawn)

func _on_piece_destroyed(destroyed_piece: ModelPiece):
	# Active Rase Dead only if the destroyed piece is a major or minor piece.
	for base_type in model.MAJOR_MINOR_BASE_TYPES:
		if destroyed_piece.type.contains(base_type):
			raise_dead() 

func raise_dead():
	var death_square = model.last_destroyed_piece.coordinate
	model.queue_selection_opportunity(self, "raise_dead", death_square)

	# Now that non_move_selection_mode has been initiated,
	# if user selects a square,
	# a bone pawn will be summoned from _on_target_selected().
	
	

func get_selection_targets(action_type: String, event_data) -> Array:
	if action_type == "raise_dead":
		var death_square = event_data
		var raisable_squares = model.get_empty_adjacent_squares(death_square)

		# Add the death square itself if it's empty
		if model.board[death_square.x][death_square.y] == null:
			raisable_squares.append(death_square)

		return raisable_squares
	else: return []

## Called when a summon target is selected.
# Assumes the target is empty.
func _on_special_target_selected(coord: Vector2i):
	summon_bone_pawn(coord)
	if model.current_turn == self.color: model._pending_turn_switch = true # If you choose to Raise Dead when your turn is coming up, your turn is skipped.
	
# move to view script
func apply_aura():
	print("apply_aura()")
	if skull_aura_instance == null:
		skull_aura_instance = SkullAura.instantiate()
		view_node.add_child(skull_aura_instance)
		skull_aura_instance.restart()
	skull_aura_instance.emitting = true
	skull_aura_instance.connect("finished", skull_aura_instance.queue_free, CONNECT_ONE_SHOT)

# move to view script
func remove_aura():
	if skull_aura_instance and skull_aura_instance is GPUParticles2D:
		skull_aura_instance.emitting = false
		#skull_aura_instance = null

func _on_selection_processing_start(piece: ModelPiece): 
	print("NK notified of selection process starting. checking if it's for me...")
	if piece == self: apply_aura()
	
func _on_selection_processing_end(): remove_aura()

func _on_active_selected():
	apply_aura()

func _on_active_deselected(play_powerdown_sound: bool = false):
	remove_aura()
	if play_powerdown_sound: pass # add sound
	
