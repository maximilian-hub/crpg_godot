extends Resource
class_name ChessBattlePresentationProfile

## Replaceable visual identity for a chess arena. Board and surroundings stay
## independent so either can be reused by another encounter.

@export var board_style: ChessBoardVisualStyle
@export var environment_style: ChessEnvironmentVisualStyle
