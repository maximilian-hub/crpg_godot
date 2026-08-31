extends RefCounted
class_name ChessPresentationTransform

## Profiles are authored for the near seat. The far seat occupies the opposite
## side of the subject, while airborne lift remains screen-up elsewhere.
static func king_hover_offset(authored_offset: Vector2, seat: int) -> Vector2:
	return -authored_offset if seat == ChessHandRig.Seat.FAR else authored_offset

static func authored_display_coordinate(coordinate: Vector2i, seat: int, board_size := Vector2i(8, 8)) -> Vector2i:
	if seat != ChessHandRig.Seat.FAR:
		return coordinate
	return Vector2i(board_size.x - 1 - coordinate.x, board_size.y - 1 - coordinate.y)

