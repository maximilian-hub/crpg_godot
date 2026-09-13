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

## The base number of turns for the active ability cooldown.
## Subclasses should override this in their _init or set it directly.
@export var base_cooldown: int = 4 # Default value, override in specific Kings

## Remaining active cooldown turns. Readiness also requires no pending reset.
var current_cooldown: int = base_cooldown
## A spent ability schedules its visible cooldown for the King's next turn.
var cooldown_reset_pending := false

var active_ability_name: String = "Active Ability" 
var active_ability_id: StringName = &"active_ability"
var passive_ability_name: String = "Passive Ability"


# --- Methods ---

func _init(_color: String, _coordinate: Vector2i):
	super._init(_color, _coordinate) # Call the parent ModelPiece constructor
	self.is_king = true
	# Abilities start ready by default.
	# Specific Kings can override base_cooldown in their own _init.
	set_cooldown(0)
	
func get_legal_moves() -> Array:
	var row = coordinate.x
	var col = coordinate.y

	var moves := []

	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var r = row + dr
			var c = col + dc
			if model.is_in_bounds(r, c):
				var target = model.board[r][c]
				if target == null or target.color != color:
					moves.append(Vector2i(r, c))

	if not has_moved:
		for castle_target in [Vector2i(row, 2), Vector2i(row, 6)]:
			if model.can_castle_move(self, coordinate, castle_target):
				moves.append(castle_target)

	return moves


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
	current_cooldown = 0
	cooldown_reset_pending = base_cooldown > 0
	if cooldown_reset_pending:
		cooldown_scheduled.emit(self)
	else:
		cooldown_ready.emit(self)

func is_active_ability_ready() -> bool:
	return current_cooldown == 0 and not cooldown_reset_pending

func announce_cooldown_state() -> void:
	if cooldown_reset_pending:
		cooldown_scheduled.emit(self)
	elif current_cooldown > 0:
		cooldown_changed.emit(self, current_cooldown)
	else:
		cooldown_ready.emit(self)

## Decrements the cooldown at the beginning of this King's turn.
func decrement_cooldown():
	if current_cooldown > 0:
		set_cooldown(current_cooldown - 1)

## A newly scheduled recharge emits its motes on the first turn entry; existing
## cooldowns begin absorbing a mote on each later turn entry.
func _on_turn_changed(current_turn: String):
	super._on_turn_changed(current_turn)
	if current_turn != color:
		return
	if cooldown_reset_pending:
		set_cooldown(base_cooldown)
		return
	decrement_cooldown()

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
	# Subclasses MUST implement this to define ability targeting.
	printerr("get_active_ability_targets() not implemented for ", self.type)
	return []

## Called by the Controller when a valid target square is selected for the active ability.
## Subclasses MUST implement the core logic of their ability here.
func active_target_selected(target):
	# Subclasses MUST implement this to execute their ability.
	printerr("active_target_selected() not implemented for ", self.type)
	pass
