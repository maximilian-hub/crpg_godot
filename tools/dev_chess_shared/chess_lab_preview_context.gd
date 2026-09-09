extends RefCounted
class_name ChessLabPreviewContext

enum Loadout { PLAYER, OPPONENT }

const ArmyPresentation := preload("res://scripts/view/chess_army_presentation_profile.gd")
const PLAYER_LOADOUT_PATH := "res://assets/player_army_presentation.tres"
const OPPONENT_LOADOUT_PATH := "res://assets/opponent_army_presentation.tres"

var seat := ChessHandRig.Seat.NEAR
var loadout := Loadout.PLAYER
var _player_loadout: ChessArmyPresentationProfile
var _opponent_loadout: ChessArmyPresentationProfile


func army_presentation() -> ChessArmyPresentationProfile:
	if loadout == Loadout.PLAYER:
		if _player_loadout == null:
			_player_loadout = ResourceLoader.load(PLAYER_LOADOUT_PATH, "ChessArmyPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessArmyPresentationProfile
		return _player_loadout
	if _opponent_loadout == null:
		_opponent_loadout = ResourceLoader.load(OPPONENT_LOADOUT_PATH, "ChessArmyPresentationProfile", ResourceLoader.CACHE_MODE_IGNORE) as ChessArmyPresentationProfile
	return _opponent_loadout


func hand_style() -> ChessHandStyle:
	return army_presentation().hand_style


func hover_offset(authored: Vector2, world_scale := 1.0) -> Vector2:
	return ChessPresentationTransform.king_hover_offset(authored, seat, false, world_scale)


func apply_to_hand(hand: ChessHandRig, visual_mirrored := false) -> void:
	hand.seat = seat
	hand.set_hand_style(hand_style())
	hand.set_visual_mirrored(visual_mirrored)
	hand._apply_pose(false)


func opposite_screen_point(near_point: Vector2, viewport_size: Vector2) -> Vector2:
	return viewport_size - near_point if seat == ChessHandRig.Seat.FAR else near_point
