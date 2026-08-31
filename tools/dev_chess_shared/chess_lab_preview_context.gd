extends RefCounted
class_name ChessLabPreviewContext

enum Loadout { PLAYER, OPPONENT }

const PLAYER_LOADOUT := preload("res://assets/player_army_presentation.tres")
const OPPONENT_LOADOUT := preload("res://assets/opponent_army_presentation.tres")

var seat := ChessHandRig.Seat.NEAR
var loadout := Loadout.PLAYER


func army_presentation() -> ChessArmyPresentationProfile:
	return PLAYER_LOADOUT if loadout == Loadout.PLAYER else OPPONENT_LOADOUT


func hand_style() -> ChessHandStyle:
	return army_presentation().hand_style


func hover_offset(authored: Vector2) -> Vector2:
	return ChessPresentationTransform.king_hover_offset(authored, seat)


func apply_to_hand(hand: ChessHandRig, visual_mirrored := false) -> void:
	hand.seat = seat
	hand.set_hand_style(hand_style())
	hand.set_visual_mirrored(visual_mirrored)
	hand._apply_pose(false)


func opposite_screen_point(near_point: Vector2, viewport_size: Vector2) -> Vector2:
	return viewport_size - near_point if seat == ChessHandRig.Seat.FAR else near_point

