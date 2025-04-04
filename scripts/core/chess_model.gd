#~~~~~~~~NEW FILE: chess_model.gd~~~~~~~~~~~~
extends Node

## Serves as the Model layer of our chess games.
# You may notice a lack of Checking; this is intentional.
# We believe that if you don't see that your King is threatened,
# he should just die.

@export var view: Node
@export var controller: Node
const BOARD_TYPE = "debug"
var board: Array
var last_move: Dictionary = {}		# from, to, piecename
var current_turn: String = "white"	# can be white or black
signal turn_changed(current_turn: String)

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
	inject_dependencies() # passes references to the model and view to each piece

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
	board[3][1] = NecromancerKing.new("white", Vector2i(3,1))
	board[3][2] = NecromancerKing.new("black", Vector2i(3,2))

	board[7][0] = Rook.new("white", Vector2i(7, 0))
	#board[7][1] = ModelPiece.new("white", "knight", Vector2i(7, 1))
	#board[7][2] = ModelPiece.new("white", "bishop", Vector2i(7, 2))
	#board[7][3] = ModelPiece.new("white", "queen", Vector2i(7, 3))
	#board[7][4] = MinotaurKing.new("white", Vector2i(7, 4))
	#board[7][5] = ModelPiece.new("white", "bishop", Vector2i(7, 5))
	#board[7][6] = ModelPiece.new("white", "knight", Vector2i(7, 6))
	board[7][7] = Rook.new("white", Vector2i(7, 7))

func inject_dependencies():
	for row in board:
		for piece in row:
			if piece != null:
				piece.view = view
				piece.model = self
				connect("turn_changed", piece._on_turn_changed)

				# Connect KingPiece specific signals TO the view
				if piece is KingPiece: # Check if the piece is a KingPiece or subclass
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
	elif is_combat: handle_combat(piece, to, piece_node) 
	elif is_castling: handle_castling(piece, from, to)
	else: actually_move_piece(piece, to, piece_node)	# a normal move with no captures or exceptions
	
	update_last_move(piece, from, to)
	switch_turn()

## Moves a piece from one square to another.
# Assumes empty destination square.
# Validation is handled in move_piece()
func actually_move_piece(piece: ModelPiece, to: Vector2i, pawn_node: Node = null):
	var from = piece.coordinate
	board[from.x][from.y] = null
	board[to.x][to.y] = piece
	piece.coordinate = to
	piece.has_moved = true
	view.move_piece_node(piece.view_node, to) # update the view
	if pawn_node != null: promotion_check(piece, pawn_node, to)

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
	
	emit_signal("turn_changed", current_turn)

func promotion_check(piece: ModelPiece, piece_node: Node, to: Vector2i):
	if piece.type == "pawn":
		if (piece.color == "white" and to.x == 0) or (piece.color == "black" and to.x == 7): # TODO: this only works on 8x8 boards.
			piece.type = "queen" #TODO: give options
			piece_node.update_sprite()

func update_last_move(piece: ModelPiece, from: Vector2i, to: Vector2i):
	last_move = {
		"from": from,
		"to": to,
		"piece": piece
	}
	
func handle_castling(piece: ModelPiece, from: Vector2i, to: Vector2i):
		print("heyyy we're castling folks!")
		var row = from.x
		if to.y == 6: # King-side castle
			board[row][5] = board[row][7]
			board[row][7] = null
			view.move_piece_node(view.get_piece_at(Vector2i(row, 7)), Vector2i(row, 5))
		elif to.y == 2: # Queen-side castle
			board[row][3] = board[row][0]
			board[row][0] = null
			view.move_piece_node(view.get_piece_at(Vector2i(row, 0)), Vector2i(row, 3))
		
		actually_move_piece(piece, to)

func handle_en_passant(piece: ModelPiece, from: Vector2i, to: Vector2i):
	var captured_row = from.x
	var captured_col = to.y
	var captured_piece_view_node = board[captured_row][captured_col].view_node
	view.destroy_piece(captured_piece_view_node)
	board[captured_row][captured_col] = null
	actually_move_piece(piece, to)

# Assumes a piece is moving to attack another piece.
func handle_combat(attacker: ModelPiece, to: Vector2i, piece_node: Node):
	var defender = board[to.x][to.y]
	
	if defender.current_hp == 1: # normal capture
		view.destroy_piece(defender.view_node)
		actually_move_piece(attacker, to)
		promotion_check(attacker, piece_node, to)
	else: # doing damage, attacker doesn't move
		defender.take_damage()	
		#defender.on_damaged(attacker, board, view)
			
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

## Returns an army's king.
func get_king(color: String) -> ModelPiece:
	for row in board:
		for piece in row:
			if piece != null and piece.color == color and piece.type.ends_with("king"):
				return piece
	return null
