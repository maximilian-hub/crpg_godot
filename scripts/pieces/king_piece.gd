##~~~~~~~~NEW FILE: king_piece.gd~~~~~~~~~~~~
extends ModelPiece
class_name KingPiece

## Base class for all King pieces.
## Handles common King functionality like cooldowns for active abilities.

## Emitted when the cooldown value changes (and is not 0).
signal cooldown_changed(king: KingPiece, new_cooldown: int)
## Emitted when the cooldown reaches 0 (ability is ready).
signal cooldown_ready(king: KingPiece)
## Emitted after an ability is spent but before its cooldown begins next turn.
signal cooldown_scheduled(king: KingPiece)
signal active_availability_changed(king: KingPiece, available: bool, reason: String)

## The base number of turns for the active ability cooldown.
## Subclasses should override this in their _init or set it directly.
@export var base_cooldown: int = 4 # Default value, override in specific Kings

## Remaining active cooldown turns. Readiness also requires no pending reset.
var current_cooldown: int = base_cooldown
## A spent ability schedules its visible cooldown for the King's next turn.
var cooldown_reset_pending := false
## Starting cooldowns remain intact through each King's first playable turn.
## The side already on move is marked entered when it joins the model.
var initial_cooldown_turn_pending := true

var active_ability_name: String = "Active Ability" 
var active_ability_id: StringName = &"active_ability"
var passive_ability_name: String = "Passive Ability"


# --- Methods ---

func _init(_color: String, _coordinate: Vector2i):
	super._init(_color, _coordinate) # Call the parent ModelPiece constructor
	self.is_king = true
	# The base constructor cannot know a subclass's authored cooldown yet.
	# Active King subclasses set base_cooldown and then call reset_cooldown().
	set_cooldown(0)
	
func get_legal_moves() -> Array:
	return super.get_legal_moves()


## Sets the current cooldown and emits the appropriate signal.
func set_cooldown(value: int):
	cooldown_reset_pending = false
	current_cooldown = max(0, value) # Ensure cooldown doesn't go below 0
	if current_cooldown > 0:

		emit_signal("cooldown_changed", self, current_cooldown)
	else:
		emit_signal("cooldown_ready", self)

## Immediately resets cooldown state. Active abilities use schedule_cooldown().
func reset_cooldown():
	set_cooldown(base_cooldown)

## Schedules recharge without showing motes until this King's next turn begins.
func schedule_cooldown() -> void:
	if model != null and model.active_ability_cooldowns_disabled:
		set_cooldown(0)
		return
	current_cooldown = 0
	cooldown_reset_pending = base_cooldown > 0
	if cooldown_reset_pending:
		cooldown_scheduled.emit(self)
	else:
		cooldown_ready.emit(self)

func is_active_ability_ready() -> bool:
	if model != null and model.active_ability_cooldowns_disabled:
		return true
	return current_cooldown == 0 and not cooldown_reset_pending

func announce_cooldown_state() -> void:
	if cooldown_reset_pending:
		cooldown_scheduled.emit(self)
	elif current_cooldown > 0:
		cooldown_changed.emit(self, current_cooldown)
	else:
		cooldown_ready.emit(self)

## Decrements the cooldown at the beginning of this King's turn.
func mark_initial_turn_entered() -> void:
	initial_cooldown_turn_pending = false

# --- Virtual Methods (to be overridden by subclasses) ---

## Returns the display name of this King's active ability.
func get_active_ability_name() -> String:
	# Subclasses should override this or set the active_ability_name property.
	return active_ability_name

func get_active_ability_id() -> StringName:
	return active_ability_id

## Whether this King implementation provides a player-selectable active ability.
func has_active_ability() -> bool:
	return false

## Calculate and return valid target squares for the active ability.
func get_active_ability_targets() -> Array:
	return model.get_active_ability_targets(self) if model != null else []
