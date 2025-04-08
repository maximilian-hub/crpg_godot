#~~~~~~~~NEW FILE: chess_model.gd~~~~~~~~~~~~
extends Node

## Serves as the Model layer of our chess games.
# You may notice a lack of Checking; this is intentional.
# We believe that if you don't see that your King is threatened,
# he should just die.

@export var view: Node
@export var controller: Node
const BOARD_TYPE = "default"
var board: Array
var last_move: Dictionary = {}		# from, to, piecename
var last_destroyed_piece: ModelPiece		
var current_turn: String = "white"	# can be white or black
signal turn_changed(current_turn: String)
signal piece_destroyed(piece: ModelPiece)

var selection_queue: Array = [] # {calling_piece: ModelPiece, action_type: String, targets: Array[Vector2i], priotity: int}
var _pending_turn_switch: bool = false # utilized in the selection queue process

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
	initialize_board()
	#print(board) # debug
	view.draw_board(board)

func initialize_board():
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
	inject_all_dependencies() # passes references to the model and view to each piece

func initialize_default_pieces():
	board[0][0] = Rook.new("black", Vector2i(0, 0))
	board[0][1] = Knight.new("black", Vector2i(0, 1))
	board[0][2] = Bishop.new("black", Vector2i(0, 2))
	board[0][3] = Queen.new("black", Vector2i(0, 3))
	board[0][4] = MinotaurKing.new("black", Vector2i(0, 4))
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
	board[7][4] = NecromancerKing.new("white", Vector2i(7, 4))
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

func inject_all_dependencies():
	for row in board:
		for piece in row:
			if piece != null:
				inject_dependencies(piece)

func inject_dependencies(piece: ModelPiece):
	piece.view = view
	piece.model = self
	piece.controller = controller
	connect("turn_changed", piece._on_turn_changed)
	connect("piece_destroyed", piece._on_piece_destroyed)

	if piece is KingPiece: 
		var king_piece: KingPiece = piece 
		king_piece.connect("cooldown_changed", view.update_cooldown_display)
		king_piece.connect("cooldown_ready", view.ready_cooldown_display)
		king_piece.set_cooldown(king_piece.base_cooldown) # this is here to ensure the buttons show the proper text immediately

		if king_piece is MinotaurKing:
			king_piece.connect("piece_started_ability", view._on_piece_started_ability)
			king_piece.connect("passive_ability_effect", view._on_passive_ability_effect)



func get_legal_moves(piece: ModelPiece) -> Array:
	if not is_instance_valid(piece): # Basic safety check
		printerr("Attempted to get moves for invalid piece instance.")
		return []
	if piece.has_method("get_legal_moves"):
		return piece.get_legal_moves()
	else:
		printerr("Piece type %s does not have get_legal_moves method!" % piece.type)
		return []

## A player's move.
# Handles special moves, normal moves, and ends the turn.
# For simply moving a piece in the model, see actually_move_piece()
# Abilities are not considered moves and are handled elsewhere.
func move_piece(piece: ModelPiece, to: Vector2i):
	var from = piece.coordinate
	var piece_node = view.get_piece_node(from)
	var is_en_passant = move_is_en_passant(piece, from, to)
	var is_castling = move_is_castling(piece, from, to)
	var is_combat = move_is_combat(is_en_passant, to)

	if is_en_passant: handle_en_passant(piece, from, to)
	elif is_combat: handle_combat(piece, to) 
	elif is_castling: handle_castling(piece, from, to)
	else: actually_move_piece(piece, to)	# a normal move with no captures or exceptions
	
	update_last_move(piece, from, to)
	switch_turn()

## Moves a piece from one square to another.
# Assumes empty destination square.
# Validation is handled in move_piece()
func actually_move_piece(piece: ModelPiece, to: Vector2i):
	var from = piece.coordinate
	board[from.x][from.y] = null
	board[to.x][to.y] = piece
	piece.coordinate = to
	piece.has_moved = true
	view.move_piece_node(piece.view_node, to) # update the view
	if piece.type.contains("pawn"): promotion_check(piece)

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
	
	if current_turn == "white":
		current_turn = "black"
	else:
		current_turn = "white"
	print("emitting turn_changed")
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
		var row = from.x
		if to.y == 6: # King-side castle
			var kingside_rook = board[row][7]
			actually_move_piece(kingside_rook, Vector2i(row, 5))
		elif to.y == 2: # Queen-side castle
			var queenside_rook = board[row][0]
			actually_move_piece(queenside_rook, Vector2i(row, 3))
		
		actually_move_piece(king, to)

func handle_en_passant(piece: ModelPiece, from: Vector2i, to: Vector2i):
	var captured_row = from.x
	var captured_col = to.y
	var captured_piece_view_node = board[captured_row][captured_col].view_node
	view.destroy_piece(captured_piece_view_node)
	board[captured_row][captured_col] = null
	actually_move_piece(piece, to)

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


# Updated capture logic using the new destroy_piece flag
func handle_combat(attacker: ModelPiece, to: Vector2i):
	var defender = board[to.x][to.y]
	var damage = attacker.attack_power

	if defender.current_hp <= damage: # predict defender's death
		var defender_instance = defender
		var defender_original_coord = defender.coordinate 

		actually_move_piece(attacker, to)


		destroy_piece(defender_instance, false) # don't nullify the defender's square yet
	else: # Defender survives, takes damage, attacker stays put
		defender.take_damage(damage)

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

func destroy_piece(piece: ModelPiece, nullify_square: bool = true):
	var piece_coord = piece.coordinate
	last_destroyed_piece = piece
	
	piece_destroyed.emit(piece) # Necromancer needs to react based on the piece object
	view.destroy_piece(piece.view_node)

	if nullify_square: board[piece_coord.x][piece_coord.y] = null
	
	# Note: The ModelPiece object itself still exists until GDScript garbage collects it,
	# but it should no longer be referenced by the board array (if nullify_square=true)
	# or have a view_node.

func transform_piece(piece: ModelPiece, transformed_type: String):
	if transformed_type == "queen":
		piece.view_node.queue_free()
		var r = piece.coordinate.x
		var c = piece.coordinate.y
		
		var transformed_piece = Queen.new(piece.color, Vector2i(r,c))
		inject_dependencies(transformed_piece)
		view.add_piece_node(transformed_piece)
		board[r][c] = transformed_piece
		

## Called by ModelPieces to add a selection opportunity to the queue.
func queue_selection_opportunity(calling_piece: ModelPiece, action_type: String, event_data):
	var priority_value = 0 # default to highest priority
	if action_type == "raise_dead":
		var causing_player_color = current_turn # Assumes event_data might contain this if needed, or use current_turn
		priority_value = 1 if calling_piece.color != causing_player_color else 0 # Higher value for defender

	var selection_opportunity = {
		"calling_piece": calling_piece,
		"action_type": action_type,  
		"priority": priority_value,
		"event_data": event_data # for raise dead, this is the square a piece just died on
	}
	
	selection_queue.append(selection_opportunity)
	print("Queued another selection: ", selection_opportunity)

## Executes the next item in the selection queue.
# You kinda have to call this wherever there might be something in the queue...
func process_selection_queue():
	if selection_queue.is_empty():
		if _pending_turn_switch:
			_pending_turn_switch = false
			switch_turn()
		return
	
	selection_queue.sort_custom(func(a, b): return a.priority > b.priority)
	

	var opportunity = selection_queue[0] # Peek at the highest priority
	var calling_piece: ModelPiece = opportunity.calling_piece
	var action_type: String = opportunity.action_type
	var event_data = opportunity.event_data
	var targets = calling_piece.get_selection_targets(action_type, event_data)
	
	if targets.is_empty(): return 
	
	selection_queue.pop_front()
	controller.initiate_non_move_selection_mode(calling_piece, targets)
	
func get_other_color(color: String) -> String:
	if color == "white": return "black"
	else: return "white"
