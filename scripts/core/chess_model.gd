#~~~~~~~~NEW FILE: chess_model.gd~~~~~~~~~~~~
extends Node
class_name ChessBoardModel

## Serves as the Model layer of our chess games.
# You may notice a lack of Checking; this is intentional.
# We believe that if you don't see that your King is threatened,
# he should just die.

const BOARD_TYPE = "default"
var board: Array = []
var last_move: Dictionary = {}		# from, to, piecename
var last_destroyed_piece: ModelPiece		
var current_turn: String = "white"	# can be white or black
signal turn_changed(current_turn: String)
signal piece_destroyed(piece: ModelPiece)
signal action_started(owner_color: String)
signal action_finished()
signal action_cancelled()
signal battle_finished(winner_color: String)
signal board_initialized(board: Array)
signal piece_added(piece: ModelPiece)
signal piece_move_committed(piece: ModelPiece, from: Vector2i, to: Vector2i, completion: CompletionGate)
signal piece_transformed(old_piece: ModelPiece, new_piece: ModelPiece)
signal piece_damaged(piece: ModelPiece, amount: int, current_hp: int, max_hp: int)
signal piece_stunned(piece: ModelPiece, duration: int)
signal piece_recovered(piece: ModelPiece)
signal ability_started(piece: KingPiece, ability_name: String, completion: CompletionGate)
signal ability_effect_resolved(piece: KingPiece, ability_name: String, affected_coords: Array)
signal reaction_selection_requested(calling_piece: ModelPiece, action_type: String, targets: Array)
signal reaction_selection_resolved(calling_piece: ModelPiece, action_type: String, target: Vector2i)

var battle_over: bool = false
var battle_result: String = ""
var defeated_king_colors: Array[String] = []

var selection_queue: Array = [] # {calling_piece, action_type, priority, sequence, event_data}
var selection_sequence: int = 0
var pending_reaction: Dictionary = {}
var is_initialized: bool = false

# One primary move/ability and every consequence it causes are one action.
# current_turn does not change until the action and reaction queue are finished.
var action_in_progress: bool = false
var action_owner_color: String = ""

const MAJOR_MINOR_BASE_TYPES = ["knight", "rook", "bishop", "queen"]

const Pawn = preload("res://scripts/pieces/pawn.gd")
const Knight = preload("res://scripts/pieces/knight.gd")
const Bishop = preload("res://scripts/pieces/bishop.gd")
const Rook = preload("res://scripts/pieces/rook.gd")
const Queen = preload("res://scripts/pieces/queen.gd")
const ClassicKing = preload("res://scripts/pieces/classic_king.gd")
const MinotaurKing = preload("res://scripts/pieces/minotaur_king.gd")
const NecromancerKing = preload("res://scripts/pieces/necromancer_king.gd")

var custom_size = 16

func _ready():
	initialize_battle()

func initialize_battle() -> bool:
	if is_initialized:
		return false
	initialize_board()
	is_initialized = true
	board_initialized.emit(board)
	return true

func initialize_board():
	board.clear()
	if BOARD_TYPE == "default": # the normal 8x8 board
		for x in range(8):
			var row = []
			for y in range(8):
				row.append(null)
			board.append(row)
		initialize_default_pieces() # populates the board array with ModelPiece objects
	elif BOARD_TYPE == "custom": # a custom-sized (but still square) board
		for x in range(custom_size):
			board.append([null])
			for y in range(custom_size):
				board[x].append(null)
	elif BOARD_TYPE == "debug": # a board with immediately available en passant, castle etc
		for x in range(8):
			var row = []
			for y in range(8):
				row.append(null)
			board.append(row)
		initialize_debug_pieces() # populates the board array with ModelPiece objects
	inject_all_dependencies()

func initialize_default_pieces():
	board[0][0] = Rook.new("black", Vector2i(0, 0))
	board[0][1] = Knight.new("black", Vector2i(0, 1))
	board[0][2] = Bishop.new("black", Vector2i(0, 2))
	board[0][3] = Queen.new("black", Vector2i(0, 3))
	board[0][4] = NecromancerKing.new("black", Vector2i(0, 4))
	board[0][5] = Bishop.new("black", Vector2i(0, 5))
	board[0][6] = Knight.new("black", Vector2i(0, 6))
	board[0][7] = Rook.new("black", Vector2i(0, 7))

	for x in range(8):
		board[1][x] = Pawn.new("black", Vector2i(1, x)) 
		board[6][x] = Pawn.new("white", Vector2i(6, x))

	board[7][0] = Rook.new("white", Vector2i(7, 0))
	board[7][1] = Knight.new("white", Vector2i(7, 1))
	board[7][2] = Bishop.new("white", Vector2i(7, 2))
	board[7][3] = Queen.new("white", Vector2i(7, 3))
	board[7][4] = MinotaurKing.new("white", Vector2i(7, 4))
	board[7][5] = Bishop.new("white", Vector2i(7, 5))
	board[7][6] = Knight.new("white", Vector2i(7, 6))
	board[7][7] = Rook.new("white", Vector2i(7, 7))

func initialize_debug_pieces():
	board[0][0] = Rook.new("black", Vector2i(0, 0))
	board[0][1] = Knight.new("black", Vector2i(0, 1))
	board[0][2] = Bishop.new("black", Vector2i(0, 2))
	board[0][3] = Queen.new("black", Vector2i(0, 3))
	#board[0][4] = MinotaurKing.new("black", Vector2i(0, 4))
	board[0][5] = Bishop.new("black", Vector2i(0, 5))
	board[0][6] = Knight.new("black", Vector2i(0, 6))
	board[0][7] = Rook.new("black", Vector2i(0, 7))

	for x in range(8):
		board[1][x] = Pawn.new("white", Vector2i(1, x)) 
		board[6][x] = Pawn.new("white", Vector2i(6, x))
		
	board[1][5] = BonePawn.new("black", Vector2i(1, 5))
	board[3][4] = Pawn.new("white", Vector2i(3, 4))
	board[3][3] = MinotaurKing.new("black", Vector2i(3,3))
	board[4][4] = Bishop.new("white", Vector2i(4,4))
	board[2][2] = Bishop.new("white", Vector2i(2,2))

	board[7][0] = Rook.new("white", Vector2i(7, 0))
	#board[7][1] = ModelPiece.new("white", "knight", Vector2i(7, 1))
	#board[7][2] = ModelPiece.new("white", "bishop", Vector2i(7, 2))
	#board[7][3] = ModelPiece.new("white", "queen", Vector2i(7, 3))
	board[7][4] = NecromancerKing.new("white", Vector2i(7, 4))
	#board[7][5] = ModelPiece.new("white", "bishop", Vector2i(7, 5))
	#board[7][6] = ModelPiece.new("white", "knight", Vector2i(7, 6))
	board[7][7] = Rook.new("white", Vector2i(7, 7))

## Injects dependencies into every piece on the board.
func inject_all_dependencies():
	for row in board:
		for piece in row:
			if piece != null:
				inject_dependencies(piece)

func inject_dependencies(piece: ModelPiece):
	piece.model = self

	var turn_callback := Callable(piece, "_on_turn_changed")
	var death_callback := Callable(piece, "_on_piece_destroyed")

	if not is_connected("turn_changed", turn_callback):
		connect("turn_changed", turn_callback)
	if not is_connected("piece_destroyed", death_callback):
		connect("piece_destroyed", death_callback)
	if piece is KingPiece:
		var king_piece: KingPiece = piece
		king_piece.set_cooldown(king_piece.current_cooldown)

func unregister_piece(piece: ModelPiece) -> void:
	if not is_instance_valid(piece):
		return

	var turn_callback := Callable(piece, "_on_turn_changed")
	var death_callback := Callable(piece, "_on_piece_destroyed")

	if is_connected("turn_changed", turn_callback):
		disconnect("turn_changed", turn_callback)
	if is_connected("piece_destroyed", death_callback):
		disconnect("piece_destroyed", death_callback)

func announce_ability_started(piece: KingPiece, ability_name: String) -> void:
	var completion := CompletionGate.new()
	ability_started.emit(piece, ability_name, completion)
	completion.close()
	await completion.wait_until_released()

func add_piece(piece: ModelPiece, coord: Vector2i) -> bool:
	if not is_instance_valid(piece):
		printerr("add_piece: Invalid piece.")
		return false
	if not is_in_bounds(coord.x, coord.y):
		printerr("add_piece: Coordinate out of bounds: ", coord)
		return false
	if board[coord.x][coord.y] != null:
		printerr("add_piece: Coordinate is occupied: ", coord)
		return false

	piece.coordinate = coord
	board[coord.x][coord.y] = piece
	inject_dependencies(piece)
	piece_added.emit(piece)
	return true


func get_legal_moves(piece: ModelPiece) -> Array:
	if not is_instance_valid(piece): # Basic safety check
		printerr("Attempted to get moves for invalid piece instance.")
		return []
	if piece.has_method("get_legal_moves"):
		return piece.get_legal_moves()
	else:
		printerr("Piece type %s does not have get_legal_moves method!" % piece.type)
		return []

### A player's move.
## Handles special moves, normal moves, and ends the turn.
## For simply moving a piece in the model, see actually_move_piece()
## Abilities are not considered moves and are handled elsewhere.
func begin_action(owner_color: String) -> bool:
	if battle_over:
		printerr("begin_action: The battle is already over.")
		return false
	if action_in_progress:
		printerr("begin_action: An action is already in progress.")
		return false
	if owner_color != current_turn:
		printerr("begin_action: ", owner_color, " attempted to act during ", current_turn, "'s turn.")
		return false

	action_in_progress = true
	action_owner_color = owner_color
	print("ACTION START — ", action_owner_color)
	action_started.emit(action_owner_color)
	return true

func cancel_action() -> void:
	action_in_progress = false
	action_owner_color = ""
	action_cancelled.emit()

func finish_action() -> void:
	if not action_in_progress:
		printerr("finish_action: No action is in progress.")
		return

	if has_defeated_king():
		complete_battle()
		return

	print("ACTION END — ", action_owner_color)
	action_in_progress = false
	action_owner_color = ""
	switch_turn()
	action_finished.emit()

func has_defeated_king() -> bool:
	return not defeated_king_colors.is_empty()

func complete_battle() -> void:
	if battle_over:
		return

	var white_defeated := "white" in defeated_king_colors
	var black_defeated := "black" in defeated_king_colors

	if not white_defeated and not black_defeated:
		printerr("complete_battle: Called without a defeated king.")
		return

	battle_over = true
	selection_queue.clear()
	pending_reaction.clear()
	action_in_progress = false
	action_owner_color = ""

	if white_defeated and black_defeated:
		battle_result = "draw"
	elif white_defeated:
		battle_result = "black"
	else:
		battle_result = "white"

	print("BATTLE FINISHED — ", battle_result)
	battle_finished.emit(battle_result)

## Entry point for a player's normal move/capture/castle/en-passant action.
func move_piece(piece: ModelPiece, to: Vector2i):
	if not is_instance_valid(piece):
		printerr("move_piece: Invalid piece instance passed.")
		return
	if not is_in_bounds(to.x, to.y):
		printerr("move_piece: Target coordinate ", to, " is out of bounds.")
		return
	if not begin_action(piece.color):
		return

	var from := piece.coordinate
	if not is_in_bounds(from.x, from.y):
		printerr("move_piece: Piece's current coordinate ", from, " is out of bounds.")
		cancel_action()
		return

	var is_en_passant := move_is_en_passant(piece, from, to)
	var is_castling := move_is_castling(piece, from, to)
	var is_combat := move_is_combat(is_en_passant, to)

	if is_en_passant:
		await handle_en_passant(piece, from, to)
	elif is_combat:
		await handle_combat(piece, to)
	elif is_castling:
		await handle_castling(piece, from, to)
	else:
		await actually_move_piece(piece, to)

	update_last_move(piece, from, to)
	await continue_action_resolution()

func submit_move(piece: ModelPiece, to: Vector2i) -> bool:
	if not is_piece_active(piece) or piece.color != current_turn or piece.stunned:
		return false
	if action_in_progress or battle_over or to not in get_legal_moves(piece):
		return false
	await move_piece(piece, to)
	return true

## Entry point for a king's active ability.
func perform_active_ability(king: KingPiece, target: Vector2i):
	if not is_instance_valid(king):
		printerr("perform_active_ability: Invalid king.")
		return
	if not begin_action(king.color):
		return

	await king.active_target_selected(target)
	await continue_action_resolution()

func submit_active_ability(king: KingPiece, target: Vector2i) -> bool:
	if not is_piece_active(king) or king.color != current_turn or king.stunned:
		return false
	if action_in_progress or battle_over or king.current_cooldown > 0:
		return false
	if target not in king.get_active_ability_targets():
		return false
	await perform_active_ability(king, target)
	return true



## Moves a piece from one square to another.
# Assumes empty destination square for normal moves.
# Validation is handled in move_piece() or callers like handle_combat.
func actually_move_piece(piece: ModelPiece, to: Vector2i): # <-- Added 'async'
		# ... (existing safety checks) ...
		if not is_instance_valid(piece):
			printerr("actually_move_piece: Invalid piece instance provided.")
			return

		var from = piece.coordinate
		# ... (more checks: bounds, piece at 'from', 'to' empty etc.) ...

		print("actually moving piece, ", piece.type, " from ", from, " to ", to)
		board[from.x][from.y] = null
		board[to.x][to.y] = piece
		piece.coordinate = to # Update model coordinate *before* animation starts
		piece.has_moved = true

		var completion := CompletionGate.new()
		piece_move_committed.emit(piece, from, to, completion)
		completion.close()
		await completion.wait_until_released()
		print("Animation finished for piece: ", piece.type)

		# Bone Pawns expire inside the action that moved them, before reactions drain.
		if piece is BonePawn and piece._on_dead_row():
			destroy_piece(piece, true)
			return

		# Normal pawn promotion also resolves before the action ends.
		if piece.type == "pawn" and is_instance_valid(piece) and board[to.x][to.y] == piece:
			promotion_check(piece)

func can_castle_through(king_row: int, king_col: int, rook_row: int, rook_col: int, color: String) -> bool:
	var rook_piece = board[rook_row][rook_col]
	if rook_piece == null or rook_piece.color != color or rook_piece.type != "rook":
		return false

	if rook_piece.has_moved:
		return false

	var start = min(king_col, rook_col) + 1
	var end = max(king_col, rook_col)
	for c in range(start, end):
		if board[king_row][c] != null:
			return false

	return true

func switch_turn():
	if battle_over:
		return

	if current_turn == "white":
		current_turn = "black"
	else:
		current_turn = "white"
	
	print("switching turns.")
	emit_signal("turn_changed", current_turn)
		
func promotion_check(piece: ModelPiece):
	if piece.type != "pawn": return
	
	var board_height = board.size()
	var white_back_rank = get_back_rank("white")
	var black_back_rank = get_back_rank("black")

	var promotion_rank = white_back_rank if piece.color == "black" else black_back_rank
	if piece.coordinate.x == promotion_rank: # TODO: Implement player choice for promotion (Queen, Rook, Bishop, Knight)
		transform_piece(piece, "queen")

func update_last_move(piece: ModelPiece, from: Vector2i, to: Vector2i):
	last_move = {
		"from": from,
		"to": to,
		"piece": piece
	}
	
func handle_castling(king: KingPiece, from: Vector2i, to: Vector2i):
	var row := from.x
	if to.y == 6: # King-side castle
		var kingside_rook = board[row][7]
		await actually_move_piece(kingside_rook, Vector2i(row, 5))
	elif to.y == 2: # Queen-side castle
		var queenside_rook = board[row][0]
		await actually_move_piece(queenside_rook, Vector2i(row, 3))

	await actually_move_piece(king, to)

func handle_en_passant(piece: ModelPiece, from: Vector2i, to: Vector2i):
	var captured_row := from.x
	var captured_col := to.y
	var captured_piece: ModelPiece = board[captured_row][captured_col]
	if captured_piece == null:
		printerr("handle_en_passant: No pawn to capture.")
		return

	destroy_piece(captured_piece, true)
	await actually_move_piece(piece, to)

# Assumes a piece is moving to attack another piece.
#func handle_combat(attacker: ModelPiece, to: Vector2i, piece_node: Node):
	#var defender = board[to.x][to.y]
	#
	#if defender.current_hp == 1: # normal capture
		#destroy_piece(defender)				# TODO: but! destroy piece needs to come first, or a bug happens where a piece is no longer selectable after it captures...
		#actually_move_piece(attacker, to) 	# TODO: moving needs to come first for Raise Dead to target adjacent attacker squares. 
		#promotion_check(attacker, piece_node, to)
	#else: # doing damage, attacker doesn't move
		#defender.take_damage()	


#func handle_combat(attacker: ModelPiece, to: Vector2i):
	#var defender = board[to.x][to.y]
	#var damage = attacker.attack_power
#
	#if defender.current_hp <= damage: # predict defender's death
		#var defender_instance = defender
		#var defender_original_coord = defender.coordinate 
#
		#actually_move_piece(attacker, to)
#
#
		#destroy_piece(defender_instance, false) # don't nullify the defender's square yet
	#else: # Defender survives, takes damage, attacker stays put
		#defender.take_damage(damage)
		
		
func handle_combat(attacker: ModelPiece, to: Vector2i):
		# --- Start of added checks ---
		if not is_instance_valid(attacker):
			printerr("handle_combat: Invalid attacker instance provided.")
			return
		if not is_in_bounds(to.x, to.y):
			printerr("handle_combat: Target coordinate ", to, " is out of bounds.")
			return
			
		var defender = board[to.x][to.y]
		if not is_instance_valid(defender):
			printerr("handle_combat: No defender found at target coordinate ", to)
			return
		if attacker.color == defender.color:
			printerr("handle_combat: Attacker ", attacker.type, " attempted to attack friendly piece ", defender.type, " at ", to)
			return
		# --- End of added checks ---

		var damage = attacker.attack_power

		if defender.current_hp <= damage: # predict defender's death
			var defender_instance = defender # Keep a reference before the board changes
			# var defender_original_coord = defender.coordinate # Not currently used, but could be useful

			await actually_move_piece(attacker, to) # Attacker moves into the vacated square

			# Now destroy the defender. Pass false because actually_move_piece already overwrote the square.
			destroy_piece(defender_instance, false) 

		else: # Defender survives, takes damage, attacker stays put
			await defender.take_damage(damage)
		
		
		

func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and col >= 0 and col < board[row].size()
	
func move_is_castling(piece: ModelPiece, from: Vector2i, to: Vector2i) -> bool:
	return piece.type.ends_with("king") and abs(to.y - from.y) == 2

func move_is_en_passant(piece: ModelPiece, from: Vector2i, to: Vector2i) -> bool:
	return piece.type == "pawn" and from.y != to.y and board[to.x][to.y] == null

func move_is_combat(is_en_passant: bool, to: Vector2i) -> bool:
	return not is_en_passant and board[to.x][to.y] != null
	
func get_adjacent_squares(coord: Vector2i) -> Array:
	var offsets = [
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		Vector2i(0, -1),                Vector2i(0, 1),
		Vector2i(1, -1),  Vector2i(1, 0),  Vector2i(1, 1),
	]
	var results = []
	for offset in offsets:
		var check = coord + offset
		if is_in_bounds(check.x, check.y):
			results.append(check)
	return results

func get_empty_adjacent_squares(coord: Vector2i) -> Array:
	var empty_adjacent_squares = []
	var adjacent_squares = get_adjacent_squares(coord)
	
	for _coord in adjacent_squares:
		if board[_coord.x][_coord.y] == null:
			empty_adjacent_squares.append(_coord)
	
	return empty_adjacent_squares

## Returns an army's king.
func get_king(color: String) -> ModelPiece:
	for row in board:
		for piece in row:
			if piece != null and piece.color == color and piece.type.ends_with("king"):
				return piece
	return null

## Returns the back rank of an army.
func get_back_rank(color: String) -> int:
	if color == "white": return board.size() -1
	else: return 0


## Returns the furthest occupied rank for a particular army.
func get_furthest_rank(color: String) -> int:
	if color == "white": return _get_furthest_white_rank()
	else: return _get_furthest_black_rank()

func _get_furthest_white_rank() -> int:
	var back_rank = board.size()
	print("white army's back rank is ", back_rank)
	var furthest_rank = back_rank
	
	for r in range(board.size() - 1):
		for c in range(board[0].size()):
			var piece = board[r][c]
			if piece == null: continue
			if piece.color != "white": continue
			if r < furthest_rank: 
				furthest_rank = r
				break
				
	return furthest_rank
	
func _get_furthest_black_rank() -> int:
	var back_rank = 0
	var furthest_rank = back_rank

	# Should be board size agnostic.
	for r in range(board.size() -1):
		for c in range(board[0].size() - 1):
			var piece = board[r][c]
			if piece == null: continue
			if piece.color != "black": continue
			if r > furthest_rank: 
				furthest_rank = r
				break

	return furthest_rank

## Returns an array of unoccupied square coordinates.
# With no arguments, returns all empty squares on the board.
# Can also target a rectangular area if given corner coordinates.
func get_empty_squares(
lower_left_corner: Vector2i = Vector2i(board.size() - 1, 0), 
upper_right_corner: Vector2i = Vector2i(0, board[0].size() - 1)) -> Array:
	var squares = []
	
	for r in range(board.size()):
		if r > lower_left_corner.x or r < upper_right_corner.x: continue # ignore rows not in targeted range
		
		for c in range(board[0].size()):
			if c < lower_left_corner.y or c > upper_right_corner.y: continue # ignore columns not in target range
			if board[r][c] != null: continue # ignore occupied squares
			squares.append(Vector2i(r, c))
			
	return squares


## Returns an array of empty square coordinates,
## from the army's back rank, to its furthest occupied rank.
func get_empty_squares_to_furthest_rank(color: String) -> Array:
	var back_rank = get_back_rank(color)
	var furthest_rank = get_furthest_rank(color)
	var lower_left_corner: Vector2i
	var upper_right_corner: Vector2i
	
	if color == "white":
		lower_left_corner = Vector2i(back_rank, 0)
		upper_right_corner = Vector2i(furthest_rank, board[0].size() - 1)
	else:
		lower_left_corner = Vector2i(furthest_rank, 0)
		upper_right_corner = Vector2i(back_rank, board[0].size() - 1)
	
	var squares = get_empty_squares(lower_left_corner, upper_right_corner)

	return squares

func destroy_piece(piece: ModelPiece, nullify_square: bool):
	if not is_instance_valid(piece):
			printerr("destroy_piece: Attempted to destroy an invalid ModelPiece instance.")
			return
			
	var piece_coord = piece.coordinate
	if not is_in_bounds(piece_coord.x, piece_coord.y):
		printerr("destroy_piece: Piece ", piece.type, " coordinate ", piece_coord, " is out of bounds.")
		
	
	last_destroyed_piece = piece

	if piece.is_king and piece.color not in defeated_king_colors:
		defeated_king_colors.append(piece.color)
		print("KING DEFEATED — ", piece.color)

	piece_destroyed.emit(piece) # Necromancer needs to react based on the piece object
	
	
	# Only nullify if requested AND the piece is actually where we think it is
	if nullify_square and is_in_bounds(piece_coord.x, piece_coord.y) and board[piece_coord.x][piece_coord.y] == piece:
		board[piece_coord.x][piece_coord.y] = null
	elif nullify_square:
		printerr("destroy_piece: Requested to nullify square ", piece_coord, " but the piece wasn't found there in the model.")
	
	unregister_piece(piece)

func transform_piece(piece: ModelPiece, transformed_type: String):
	if not is_instance_valid(piece):
		printerr("transform_piece: Invalid piece instance provided.")
		return
		
	if transformed_type == "queen":
		var r = piece.coordinate.x
		var c = piece.coordinate.y
		
		unregister_piece(piece)
		var transformed_piece = Queen.new(piece.color, Vector2i(r,c))
		inject_dependencies(transformed_piece)
		board[r][c] = transformed_piece # Overwrite the old piece reference in the model
		piece_transformed.emit(piece, transformed_piece)
		
		# Optional: Disconnect signals from the old piece if necessary,
		# though it should get garbage collected eventually.
		# disconnect("turn_changed", piece._on_turn_changed) 
		# disconnect("piece_destroyed", piece._on_piece_destroyed)
		

## True only while a piece is alive and still occupies its recorded square.
## A freed visual node or a still-valid GDScript object is not enough.
func is_piece_active(piece: ModelPiece) -> bool:
	if not is_instance_valid(piece) or piece.current_hp <= 0:
		return false
	var coord := piece.coordinate
	return is_in_bounds(coord.x, coord.y) and board[coord.x][coord.y] == piece

## Called by ModelPieces to add either an automatic reaction or a selection
## opportunity to the same ordered queue.
func queue_selection_opportunity(calling_piece: ModelPiece, action_type: String, event_data):
	# Once a king has fallen, the current effect may finish, but no new reactions
	# should be added before the battle is finalized.
	if battle_over or has_defeated_king():
		return

	var priority_value := 0
	if action_type == "retaliating_rage":
		# Finish Minotaur exchanges before pausing for Raise Dead selections.
		priority_value = 100
	elif action_type == "raise_dead":
		# current_turn stays equal to the primary action owner until the whole action ends.
		# The non-acting player therefore receives first choice around a corpse.
		priority_value = 1 if calling_piece.color != action_owner_color else 0

	selection_sequence += 1
	selection_queue.append({
		"calling_piece": calling_piece,
		"action_type": action_type,
		"priority": priority_value,
		"sequence": selection_sequence,
		"event_data": event_data
	})
	print("Queued reaction: ", action_type, " for ", calling_piece.color)

## Drain automatic/choice reactions. A choice pauses this function; the chosen
## square later calls resolve_reaction_selection(), which resumes this action.
func continue_action_resolution() -> void:
	if not action_in_progress:
		printerr("continue_action_resolution: No action is in progress.")
		return

	if has_defeated_king():
		complete_battle()
		return

	while not selection_queue.is_empty():
		selection_queue.sort_custom(
			func(a, b):
				if a["priority"] == b["priority"]:
					return a["sequence"] < b["sequence"]
				return a["priority"] > b["priority"]
		)

		var opportunity: Dictionary = selection_queue.pop_front()
		var calling_piece: ModelPiece = opportunity["calling_piece"]
		if not is_piece_active(calling_piece):
			continue

		var action_type: String = opportunity["action_type"]
		var event_data = opportunity["event_data"]

		# Automatic reactions resolve immediately, and may append more reactions.
		# The loop re-sorts before each next reaction, so newly queued Rage effects
		# continue the exchange before lower-priority selection reactions.
		if action_type == "retaliating_rage":
			await calling_piece.resolve_automatic_reaction(action_type, event_data)

			# Let the already-running effect finish, but do not begin another
			# reaction after it defeats a king.
			if has_defeated_king():
				complete_battle()
				return

			continue

		var targets: Array = calling_piece.get_selection_targets(action_type, event_data)

		# Earlier reactions may have occupied every valid square. Skip cleanly.
		if targets.is_empty():
			continue

		pending_reaction = {
			"calling_piece": calling_piece,
			"action_type": action_type,
			"event_data": event_data,
			"targets": targets.duplicate(),
		}
		reaction_selection_requested.emit(calling_piece, action_type, targets.duplicate())
		return

	finish_action()

func has_pending_reaction() -> bool:
	return not pending_reaction.is_empty()

func get_pending_reaction() -> Dictionary:
	return pending_reaction.duplicate(true)

func submit_reaction_selection(coord: Vector2i) -> bool:
	if battle_over:
		return false
	if not action_in_progress:
		return false
	if pending_reaction.is_empty():
		return false

	var calling_piece: ModelPiece = pending_reaction["calling_piece"]
	if not is_piece_active(calling_piece):
		return false
	if coord not in pending_reaction["targets"]:
		return false

	var action_type: String = pending_reaction["action_type"]
	pending_reaction.clear()
	calling_piece._on_special_target_selected(coord)
	reaction_selection_resolved.emit(calling_piece, action_type, coord)
	await continue_action_resolution()
	return true

func get_other_color(color: String) -> String:
	if color == "white": return "black"
	else: return "white"
