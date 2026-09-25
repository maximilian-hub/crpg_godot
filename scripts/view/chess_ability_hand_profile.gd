extends Resource
class_name ChessAbilityHandProfile

enum CommandStyle { STATIONARY, DIRECTIONAL }

@export var command_style: CommandStyle = CommandStyle.STATIONARY
@export_range(0.0, 2.0, 0.01) var pre_reveal_hover_duration := 0.18
@export_range(0.0, 2.0, 0.01) var post_reveal_hold_duration := 0.25

