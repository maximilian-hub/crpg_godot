extends RefCounted
class_name DupreOpeningBook

## Curated coordinate lines are deliberately data-only.  A future PGN importer
## can emit this same shape without changing Dupre or the session machinery.


static func families() -> Array[Dictionary]:
	return [
		_family(&"italian", "Italian Game", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 1, 2, 2), _m("white", "bishop", 7, 5, 4, 2), _m("black", "bishop", 0, 5, 3, 2), _m("white", "pawn", 6, 3, 5, 3), _m("black", "pawn", 1, 3, 2, 3)],
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 6, 2, 5), _m("white", "bishop", 7, 5, 4, 2), _m("black", "bishop", 0, 5, 3, 2), _m("white", "pawn", 6, 3, 5, 3), _m("black", "pawn", 1, 3, 2, 3)],
		]),
		_family(&"ruy_lopez", "Ruy Lopez", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 1, 2, 2), _m("white", "bishop", 7, 5, 3, 1), _m("black", "pawn", 1, 0, 2, 0), _m("white", "bishop", 3, 1, 4, 0), _m("black", "knight", 0, 6, 2, 5)],
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 6, 5, 5), _m("black", "pawn", 1, 0, 2, 0), _m("white", "bishop", 7, 5, 3, 1), _m("black", "knight", 0, 1, 2, 2), _m("white", "bishop", 3, 1, 4, 0), _m("black", "knight", 0, 6, 2, 5)],
		]),
		_family(&"scotch", "Scotch Game", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 1, 2, 2), _m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 3, 4, 4, 3), _m("white", "knight", 5, 5, 4, 3), _m("black", "knight", 0, 6, 2, 5)],
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 3, 4), _m("white", "pawn", 6, 3, 4, 3), _m("black", "knight", 0, 1, 2, 2), _m("white", "knight", 7, 6, 5, 5), _m("black", "pawn", 3, 4, 4, 3), _m("white", "knight", 5, 5, 4, 3), _m("black", "knight", 0, 6, 2, 5)],
		]),
		_family(&"sicilian", "Sicilian Defense", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 2, 3, 2), _m("white", "knight", 7, 6, 5, 5), _m("black", "pawn", 1, 3, 2, 3), _m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 3, 2, 4, 3), _m("white", "knight", 5, 5, 4, 3), _m("black", "knight", 0, 6, 2, 5)],
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 2, 3, 2), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 1, 2, 2), _m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 3, 2, 4, 3), _m("white", "knight", 5, 5, 4, 3), _m("black", "knight", 0, 6, 2, 5)],
		]),
		_family(&"french", "French Defense", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 2, 4), _m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 1, 3, 3, 3), _m("white", "knight", 7, 1, 5, 2), _m("black", "knight", 0, 6, 2, 5), _m("white", "pawn", 4, 4, 3, 4), _m("black", "knight", 2, 5, 1, 3)],
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 4, 2, 4), _m("white", "knight", 7, 1, 5, 2), _m("black", "pawn", 1, 3, 3, 3), _m("white", "pawn", 4, 4, 3, 4), _m("black", "pawn", 1, 2, 3, 2), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 1, 2, 2)],
		]),
		_family(&"caro_kann", "Caro-Kann Defense", [
			[_m("white", "pawn", 6, 4, 4, 4), _m("black", "pawn", 1, 2, 2, 2), _m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 1, 3, 3, 3), _m("white", "knight", 7, 1, 5, 2), _m("black", "pawn", 3, 3, 4, 4), _m("white", "knight", 5, 2, 4, 4), _m("black", "bishop", 0, 2, 4, 6)],
		]),
		_family(&"queens_gambit", "Queen's Gambit", [
			[_m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 1, 3, 3, 3), _m("white", "pawn", 6, 2, 4, 2), _m("black", "pawn", 1, 4, 2, 4), _m("white", "knight", 7, 1, 5, 2), _m("black", "knight", 0, 6, 2, 5), _m("white", "knight", 7, 6, 5, 5), _m("black", "bishop", 0, 5, 1, 4)],
			[_m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 1, 3, 3, 3), _m("white", "pawn", 6, 2, 4, 2), _m("black", "pawn", 1, 2, 3, 2), _m("white", "pawn", 6, 4, 5, 4), _m("black", "knight", 0, 6, 2, 5), _m("white", "knight", 7, 6, 5, 5), _m("black", "pawn", 1, 4, 2, 4)],
		]),
		_family(&"london", "London System", [
			[_m("white", "pawn", 6, 3, 4, 3), _m("black", "pawn", 1, 3, 3, 3), _m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 6, 2, 5), _m("white", "bishop", 7, 2, 4, 5), _m("black", "pawn", 1, 4, 2, 4), _m("white", "pawn", 6, 4, 5, 4), _m("black", "bishop", 0, 5, 3, 2)],
		]),
		_family(&"english", "English Opening", [
			[_m("white", "pawn", 6, 2, 4, 2), _m("black", "pawn", 1, 4, 3, 4), _m("white", "knight", 7, 1, 5, 2), _m("black", "knight", 0, 6, 2, 5), _m("white", "pawn", 6, 6, 5, 6), _m("black", "pawn", 1, 3, 2, 3), _m("white", "bishop", 7, 5, 6, 6), _m("black", "pawn", 1, 6, 2, 6)],
			[_m("white", "pawn", 6, 2, 4, 2), _m("black", "pawn", 1, 2, 3, 2), _m("white", "knight", 7, 1, 5, 2), _m("black", "knight", 0, 1, 2, 2), _m("white", "pawn", 6, 6, 5, 6), _m("black", "pawn", 1, 6, 2, 6), _m("white", "bishop", 7, 5, 6, 6), _m("black", "bishop", 0, 5, 1, 6)],
		]),
		_family(&"reti", "Reti Opening", [
			[_m("white", "knight", 7, 6, 5, 5), _m("black", "pawn", 1, 3, 3, 3), _m("white", "pawn", 6, 6, 5, 6), _m("black", "knight", 0, 6, 2, 5), _m("white", "bishop", 7, 5, 6, 6), _m("black", "pawn", 1, 6, 2, 6), _m("white", "pawn", 6, 2, 4, 2), _m("black", "bishop", 0, 5, 1, 6)],
			[_m("white", "knight", 7, 6, 5, 5), _m("black", "knight", 0, 6, 2, 5), _m("white", "pawn", 6, 2, 4, 2), _m("black", "pawn", 1, 2, 3, 2), _m("white", "pawn", 6, 6, 5, 6), _m("black", "pawn", 1, 6, 2, 6), _m("white", "bishop", 7, 5, 6, 6), _m("black", "bishop", 0, 5, 1, 6)],
		]),
	]


static func _family(id: StringName, display_name: String, lines: Array) -> Dictionary:
	return {"id": id, "name": display_name, "lines": lines}


static func _m(color: String, piece: String, from_row: int, from_column: int, to_row: int, to_column: int) -> Dictionary:
	return {
		"kind": ChessPrimaryAction.Kind.MOVE,
		"color": color,
		"piece": StringName(piece),
		"from": Vector2i(from_row, from_column),
		"to": Vector2i(to_row, to_column),
		"path": [Vector2i(to_row, to_column)],
	}
