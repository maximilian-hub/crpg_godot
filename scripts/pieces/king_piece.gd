##~~~~~~~~NEW FILE: king_piece.gd~~~~~~~~~~~~
extends ModelPiece
class_name KingPiece

## Base class for all King pieces in Chess RPG.
## Handles common King functionality like cooldowns for active abilities.

# --- Signals ---
## Emitted when the cooldown value changes (and is not 0).
signal cooldown_changed(king: KingPiece, new_cooldown: int)
## Emitted when the cooldown reaches 0 (ability is ready).
signal cooldown_ready(king: KingPiece)

# --- Properties ---

## The base number of turns for the active ability cooldown.
## Subclasses should override this in their _init or set it directly.
@export var base_cooldown: int = 4 # Default value, override in specific Kings

## The current remaining turns for the cooldown. 0 means ready.
var current_cooldown: int = 0

## The display name for the active ability. Subclasses should define this.
var active_ability_name: String = "Active Ability" # Default, override


# --- Methods ---

func _init(_color: String, _type: String, _coordinate: Vector2i):
	super._init(_color, _type, _coordinate) # Call the parent ModelPiece constructor
	self.is_king = true
	# Abilities start ready by default.
	# Specific Kings can override base_cooldown in their own _init.
	set_cooldown(0)


## Sets the current cooldown and emits the appropriate signal.
func set_cooldown(value: int):
	current_cooldown = max(0, value) # Ensure cooldown doesn't go below 0
	if current_cooldown > 0:
		emit_signal("cooldown_changed", self, current_cooldown)
	else:
		emit_signal("cooldown_ready", self)

## Resets the cooldown to its base value. Usually called after using the ability.
func reset_cooldown():
	set_cooldown(base_cooldown)

## Decrements the cooldown by one turn. Usually called at the start of the King's turn.
func decrement_cooldown():
	if current_cooldown > 0:
		set_cooldown(current_cooldown - 1)

## Called automatically when the turn changes (connected in ChessModel.inject_dependencies).
## Handles decrementing stun AND ability cooldowns.
func _on_turn_changed(current_turn: String):
	super._on_turn_changed(current_turn) # Handle stun decrement from ModelPiece
	if current_turn == color:
		decrement_cooldown()

# --- Virtual Methods (to be overridden by subclasses) ---

## Returns the display name of this King's active ability.
func get_active_ability_name() -> String:
	# Subclasses should override this or set the active_ability_name property.
	return active_ability_name

## Calculate and return valid target squares for the active ability.
func get_active_ability_targets() -> Array:
	# Subclasses MUST implement this to define ability targeting.
	printerr("get_active_ability_targets() not implemented for ", self.type)
	return []

## Called by the Controller when a valid target square is selected for the active ability.
## Subclasses MUST implement the core logic of their ability here.
func active_target_selected(target):
	# Subclasses MUST implement this to execute their ability.
	printerr("active_target_selected() not implemented for ", self.type)
	# Example structure for subclasses:
	# 1. Perform ability logic (move piece, spawn effects, damage targets etc.)
	#    using the 'target' information.
	# 2. Call reset_cooldown()
	# 3. Call model.switch_turn() if the ability consumes the turn.
	pass
