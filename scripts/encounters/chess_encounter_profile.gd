extends Resource
class_name ChessEncounterProfile

## Authored identity and presentation for one overworld chess encounter.
## Army, AI, arena, setup, and activation data can grow into this resource
## without teaching GameFlow about individual NPC types.

@export var encounter_id: StringName
@export var battle_presentation: ChessBattlePresentationProfile
@export var opponent_presentation: Resource
## Compatibility fallback for older encounter resources.
@export var opponent_hand_style: ChessHandStyle
