extends RefCounted
class_name ChessPresentationTransform

## Profiles are authored for the near seat. The far seat mirrors which side of
## the subject the hand occupies, while screen-up elevation remains unchanged.
static func king_hover_offset(authored_offset: Vector2, seat: int, hand_mirrored := false) -> Vector2:
	var result := authored_offset
	if hand_mirrored:
		result.x *= -1.0
	if seat == ChessHandRig.Seat.FAR:
		result.x *= -1.0
	return result

static func authored_display_coordinate(coordinate: Vector2i, seat: int, board_size := Vector2i(8, 8)) -> Vector2i:
	if seat != ChessHandRig.Seat.FAR:
		return coordinate
	return Vector2i(board_size.x - 1 - coordinate.x, board_size.y - 1 - coordinate.y)
