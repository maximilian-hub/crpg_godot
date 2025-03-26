extends ModelPiece
class_name MinotaurKing

func _init(color: String, coord: Vector2i):
	print("Minotaur King initialized.")
	self.color = color
	self.coordinate = coord
	self.max_hp = 4
	self.current_hp = 4
	self.type = "minotaur_king"

func take_damage() -> bool:
	var killed = super.take_damage()
	if current_hp > 0: retaliating_rage()
	return killed


func retaliating_rage() -> void:
	await view.start_minotaur_rage_intro(coordinate) #what's this do?

	var board = model.board
	var exploded_squares: Array = []

	var adjacent = [
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		Vector2i(0, -1),                Vector2i(0, 1),
		Vector2i(1, -1),  Vector2i(1, 0),  Vector2i(1, 1),
	]

	for offset in adjacent:
		var coord = coordinate + offset
		if coord.x >= 0 and coord.x < board.size() and coord.y >= 0 and coord.y < board[coord.x].size():
			exploded_squares.append(coord)

			var target = board[coord.x][coord.y]
			if target != null:
				var killed = target.take_damage()
				if killed:
					board[coord.x][coord.y] = null
					view.remove_piece_at(coord)
				#else:
					#view.hurt_piece_at(coord)

	view.minotaur_retaliate(coordinate, exploded_squares)






#func retaliate():
	#print("RETALIATING!!!!!")
	#var victims = []
	#var offsets = [
		#Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		#Vector2i(0, -1),                Vector2i(0, 1),
		#Vector2i(1, -1),  Vector2i(1, 0),  Vector2i(1, 1),
	#]
	#for offset in offsets:
		#var coord = coordinate + offset
		#if coord.x >= 0 and coord.x < board.size() and coord.y >= 0 and coord.y < board[coord.x].size():
			#var target = board[coord.x][coord.y]
			#if target != null:
				#var killed = target.take_damage()
				#if killed:
					#board[coord.x][coord.y] = null
					#view.remove_piece_at(coord)
				#else:
					#view.hurt_piece_at(coord)
				#victims.append(coord)
#
	#view.minotaur_retaliate(coordinate, victims)

func get_passive_name() -> String:
	return "Retaliating Rage"
