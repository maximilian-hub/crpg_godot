#~~~~~~~~NEW FILE: chess_model.gd~~~~~~~~~~~~
extends Node
class_name ChessBoardModel

enum StartupMode { DEFAULT_BATTLE, EMPTY }
enum LiveAuthority { CLASSIC_CORE }

const TargetedAbilityContext := preload("res://scripts/core/chess_targeted_ability_presentation_context.gd")
const PieceArrivalContext := preload("res://scripts/core/chess_piece_arrival_context.gd")
const ArcherKing := preload("res://scripts/pieces/archer_king.gd")
const LineOfSight := preload("res://scripts/core/chess_line_of_sight.gd")
const ActionCodec := preload("res://scripts/state/chess_action_codec.gd")

## Serves as the Model layer of our chess games.
# You may notice a lack of Checking; this is intentional.
# We believe that if you don't see that your King is threatened,
# he should just die.

const BOARD_TYPE = "default"
var board: Array = []
## DEFAULT_BATTLE preserves the live-game contract. Disposable search models set
## this before entering the SceneTree, then install an explicit ChessPosition.
var startup_mode := StartupMode.DEFAULT_BATTLE
var requested_live_authority := LiveAuthority.CLASSIC_CORE
var active_live_authority := LiveAuthority.CLASSIC_CORE
var live_authority_fallback_reason := ""
var _classic_core_bridge: ClassicCoreLiveBridge
## ModelPiece Nodes are not SceneTree children, so the model must retain and
## release them explicitly. Destroyed pieces remain owned until replacement or
## disposal because presentation and reactions may still refer to them.
var _owned_pieces: Dictionary = {}
var owned_piece_registration_count := 0
var owned_piece_disposal_count := 0
var last_move: Dictionary = {}		# from, to, piecename
var current_turn: String = "white"	# can be white or black
signal turn_changed(current_turn: String)
signal piece_destroyed(piece: ModelPiece)
signal action_started(owner_color: String)
signal primary_action_committed(descriptor: Dictionary)
signal action_finished()
signal action_cancelled()
signal forced_pass_sequence_started()
signal turn_passed(skipped_color: String, consecutive_passes: int)
signal forced_pass_sequence_finished()
signal battle_finished(winner_color: String)
signal board_initialized(board: Array)
signal board_rebuilt(board: Array)
signal settled_action_completed()
signal piece_added(piece: ModelPiece)
signal piece_summoned(piece: ModelPiece, completion: CompletionGate)
signal piece_move_committed(piece: ModelPiece, from: Vector2i, to: Vector2i, presentation)
signal piece_landed(piece: ModelPiece, from: Vector2i, to: Vector2i, completion: CompletionGate)
signal skitter_step_started(piece: ArakneKing, from: Vector2i, to: Vector2i)
signal piece_castling_committed(king: KingPiece, rook: ModelPiece, king_from: Vector2i, king_to: Vector2i, rook_from: Vector2i, rook_to: Vector2i, presentation)
signal piece_capture_committed(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, captured_at: Vector2i, presentation)
signal piece_attack_committed(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, completion: CompletionGate)
signal archer_attack_committed(attacker: ArcherKing, defender: ModelPiece, from: Vector2i, to: Vector2i, presentation)
signal piece_promotion_committed(old_piece: ModelPiece, new_piece: ModelPiece, completion: CompletionGate)
signal piece_transformed(old_piece: ModelPiece, new_piece: ModelPiece)
signal promotion_selection_requested(pawn: ModelPiece, options: Array[StringName])
signal promotion_selection_resolved(piece_type: StringName)
signal piece_damaged(piece: ModelPiece, amount: int, current_hp: int, max_hp: int)
signal piece_stunned(piece: ModelPiece, duration: int)
signal piece_recovered(piece: ModelPiece)
signal ability_started(piece: KingPiece, ability_name: String, completion: CompletionGate)
signal targeted_ability_committed(context)
signal archer_volley_committed(king: ArcherKing, targets: Array[Vector2i], completion: CompletionGate)
signal archer_state_changed(king: ArcherKing, state: StringName, message: String)
signal archer_arrow_dropped(effect: ChessTileEffectState)
signal archer_arrow_collected(piece: ModelPiece, king: ArcherKing)
signal ability_effect_resolved(piece: KingPiece, ability_name: String, affected_coords: Array)
signal reaction_selection_requested(calling_piece: ModelPiece, action_type: String, targets: Array)
signal reaction_selection_preparing(calling_piece: ModelPiece, action_type: String, targets: Array, completion: CompletionGate)
signal reaction_selection_committed(calling_piece: ModelPiece, action_type: String, target: Vector2i)
signal reaction_selection_resolved(calling_piece: ModelPiece, action_type: String, target: Vector2i)
signal reaction_queued(calling_piece: ModelPiece, action_type: String, event_data, sequence: int)
signal reaction_finished(calling_piece: ModelPiece, action_type: String, event_data, sequence: int, resolved: bool)
signal tile_effect_added(effect: ChessTileEffectState)
signal tile_effect_removed(effect: ChessTileEffectState)
signal tile_effect_refreshed(effect: ChessTileEffectState)
signal autonomous_entity_added(entity: ChessAutonomousEntityState, completion: CompletionGate)
signal autonomous_entity_moved(entity: ChessAutonomousEntityState, from: Vector2i, to: Vector2i, completion: CompletionGate)
signal autonomous_entity_removed(entity: ChessAutonomousEntityState, reason: StringName, completion: CompletionGate)
signal arc_mortar_impact(entity: ChessAutonomousEntityState, affected_coords: Array, completion: CompletionGate)
signal movement_type_selection_requested(king: QuarterlyInitiativeKing, target: ModelPiece, options: Array[StringName])
## Emitted only after an authoritative secondary choice has been accepted.
## Record/replay surfaces use this generic transcript hook instead of knowing
## which king or presentation UI supplied the choice.
signal authoritative_selection_committed(kind: StringName, option: Variant)
signal lunacy_changed(color: String, value: int, socratic_turns_remaining: int)

var battle_over: bool = false
var battle_result: String = ""
var defeated_king_colors: Array[String] = []

var pending_reaction: Dictionary = {}
var is_initialized: bool = false
var position_revision: int = 0
var tile_effects: Array[ChessTileEffectState] = []
var autonomous_entities: Array[ChessAutonomousEntityState] = []
var _next_state_id := 1
var lunacy_by_color := {"white": 0, "black": 0}
var socratic_turns_by_color := {"white": 0, "black": 0}
var _projected_random_states: Dictionary = {}
var global_turn_number := 1
var pending_movement_type_grant: Dictionary = {}
signal movement_type_selection_resolved(movement_type: StringName)
var pending_promotion: Dictionary = {}

# Runtime policy used by developer surfaces such as the board sandbox. This is
# deliberately not part of ChessPosition, so test conveniences never leak into
# saved or production battle state.
var active_ability_cooldowns_disabled := false
## Disabled on disposable AI search models to avoid thousands of log writes.
var diagnostic_logging_enabled := true


func _diagnostic(message: String) -> void:
	if diagnostic_logging_enabled:
		print(message)

# One primary move/ability and every consequence it causes are one action.
# current_turn does not change until the action and reaction queue are finished.
var action_in_progress: bool = false
var action_owner_color: String = ""
var forced_pass_in_progress := false
var consecutive_forced_passes := 0
var forced_pass_delay_seconds := 0.5

const MAX_CONSECUTIVE_FORCED_PASSES := 6

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
	_classic_core_bridge = ClassicCoreLiveBridge.new(self)
	_projected_random_states = ClassicChessCore.randomized_random_states()
	if startup_mode == StartupMode.DEFAULT_BATTLE:
		initialize_battle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		dispose_owned_state()

func initialize_battle() -> bool:
	if is_initialized:
		return false
	initialize_board()
	is_initialized = true
	_resynchronize_live_authority()
	board_initialized.emit(board)
	return true

func is_settled() -> bool:
	return not action_in_progress and not forced_pass_in_progress and pending_reaction.is_empty() and pending_movement_type_grant.is_empty() and pending_promotion.is_empty()


## Unlimited-range piece-occlusion map. Consumers may apply their own range or
## targeting rules to the retained coordinates.
func get_visibility_map(origin: Vector2i, minimum_visibility := LineOfSight.DEFAULT_VISIBILITY_THRESHOLD) -> Dictionary:
	return LineOfSight.build_visibility_map(board, origin, minimum_visibility)

func capture_position() -> ChessPosition:
	if active_live_authority == LiveAuthority.CLASSIC_CORE and _classic_core_bridge != null and _classic_core_bridge.active:
		# A pending core choice is intentionally not exportable as a settled
		# position; never substitute the partially projected facade.
		return _classic_core_bridge.capture_position()
	return _capture_projected_position()


func _capture_projected_position() -> ChessPosition:
	var position := ChessPosition.new()
	position.board_size = Vector2i(board.size(), board[0].size() if not board.is_empty() else 0)
	position.board_type = StringName(BOARD_TYPE)
	position.current_turn = current_turn
	position.battle_over = battle_over
	position.battle_result = battle_result
	position.defeated_king_colors.assign(defeated_king_colors)
	position.lunacy_by_color = lunacy_by_color.duplicate(true)
	position.socratic_turns_by_color = socratic_turns_by_color.duplicate(true)
	position.random_states = _projected_random_states.duplicate(true)
	position.global_turn_number = global_turn_number
	position.active_ability_cooldowns_disabled = active_ability_cooldowns_disabled
	position.next_state_id = _next_state_id
	for row in board:
		for piece in row:
			if piece != null:
				position.pieces.append(piece.capture_piece_state())
	for effect in tile_effects: position.tile_effects.append(effect.copy())
	for entity in autonomous_entities: position.autonomous_entities.append(entity.copy())
	if last_move.has("piece") or last_move.has("piece_type"):
		var moved_piece: ModelPiece = last_move.get("piece")
		position.last_move.is_present = true
		position.last_move.from = last_move.get("from", Vector2i.ZERO)
		position.last_move.to = last_move.get("to", Vector2i.ZERO)
		position.last_move.piece_type_id = StringName(last_move.get("piece_type", moved_piece.get_position_type_id() if is_instance_valid(moved_piece) else &""))
		position.last_move.piece_color = String(last_move.get("piece_color", moved_piece.color if is_instance_valid(moved_piece) else ""))
	return position

func load_position(position: ChessPosition) -> bool:
	if not is_settled():
		printerr("load_position: Model must be settled.")
		return false
	# Earlier schemas predate portions of authoritative non-physical state.
	if position.schema_version in [1, 2, 3, 4]: position.schema_version = ChessPosition.CURRENT_SCHEMA_VERSION
	var validation := ChessPositionValidator.validate(position)
	if not validation.is_structurally_valid():
		printerr("load_position: ", "; ".join(validation.structural_errors))
		return false
	# The pure core is the only rules authority. Reject unsupported rule state
	# before replacing any live presentation objects.
	var core_import := ClassicChessCore.import_position(position)
	if not core_import.ok:
		printerr("load_position: ", String(core_import.get("error", "Unsupported authoritative position.")))
		return false
	var replacement: Array = []
	for row_index in range(position.board_size.x):
		var row: Array = []
		row.resize(position.board_size.y)
		row.fill(null)
		replacement.append(row)
	var created: Array[ModelPiece] = []
	_next_state_id = position.next_state_id
	for state in position.pieces:
		var piece := ChessPieceCatalog.create_piece(state.type_id, state.color, state.coordinate)
		if piece == null:
			for partial: ModelPiece in created:
				if is_instance_valid(partial): partial.free()
			return false
		piece.restore_piece_state(state)
		_reserve_state_id(piece.piece_id)
		replacement[state.coordinate.x][state.coordinate.y] = piece
		created.append(piece)
	# From this point the replacement is committed. Stop exposing the previous
	# core snapshot before any projection-rebuild signals can observe new pieces.
	active_live_authority = LiveAuthority.CLASSIC_CORE
	if _classic_core_bridge != null: _classic_core_bridge.deactivate()
	_dispose_owned_pieces()
	board = replacement
	tile_effects.clear()
	for effect in position.tile_effects: tile_effects.append(effect.copy())
	autonomous_entities.clear()
	for entity in position.autonomous_entities: autonomous_entities.append(entity.copy())
	for effect in tile_effects: _reserve_state_id(effect.effect_id)
	for entity in autonomous_entities: _reserve_state_id(entity.entity_id)
	for piece in created:
		inject_dependencies(piece)
	current_turn = position.current_turn
	battle_over = position.battle_over
	battle_result = position.battle_result
	defeated_king_colors.assign(position.defeated_king_colors)
	lunacy_by_color = position.lunacy_by_color.duplicate(true)
	socratic_turns_by_color = position.socratic_turns_by_color.duplicate(true)
	_projected_random_states = position.random_states.duplicate(true)
	global_turn_number = position.global_turn_number
	active_ability_cooldowns_disabled = position.active_ability_cooldowns_disabled
	# Dependency injection announces live cooldown state and may initialize a
	# freshly-created King. Position replacement must retain the serialized rule
	# state instead, including the one-time initial-turn hold.
	for index in range(created.size()):
		var restored_piece: ModelPiece = created[index]
		if restored_piece is KingPiece:
			var restored_king := restored_piece as KingPiece
			var restored_state: ChessPieceState = position.pieces[index]
			restored_king.current_cooldown = restored_state.current_cooldown
			restored_king.cooldown_reset_pending = restored_state.cooldown_reset_pending
			restored_king.initial_cooldown_turn_pending = restored_state.initial_cooldown_turn_pending
	last_move = {}
	if position.last_move != null and position.last_move.is_present:
		var moved_piece: ModelPiece = null
		var target := position.last_move.to
		if is_in_bounds(target.x, target.y):
			var candidate: ModelPiece = board[target.x][target.y]
			if candidate != null and candidate.color == position.last_move.piece_color:
				moved_piece = candidate
		last_move = {
			"from": position.last_move.from,
			"to": target,
			"piece": moved_piece,
			"piece_type": ChessPieceCatalog.normalize_type_id(position.last_move.piece_type_id),
			"piece_color": position.last_move.piece_color,
		}
	pending_reaction.clear()
	pending_movement_type_grant.clear()
	pending_promotion.clear()
	action_in_progress = false
	action_owner_color = ""
	forced_pass_in_progress = false
	consecutive_forced_passes = 0
	is_initialized = true
	position_revision += 1
	_resynchronize_live_authority()
	board_rebuilt.emit(board)
	return true


func set_live_authority(authority: LiveAuthority) -> bool:
	if not is_settled(): return false
	if authority != LiveAuthority.CLASSIC_CORE:
		live_authority_fallback_reason = "Only pure-core authority exists."
		return false
	requested_live_authority = LiveAuthority.CLASSIC_CORE
	return _resynchronize_live_authority()


func _resynchronize_live_authority() -> bool:
	if _classic_core_bridge == null: _classic_core_bridge = ClassicCoreLiveBridge.new(self)
	if _classic_core_bridge.synchronize_from_projection():
		active_live_authority = LiveAuthority.CLASSIC_CORE
		live_authority_fallback_reason = ""
		return true
	active_live_authority = LiveAuthority.CLASSIC_CORE
	live_authority_fallback_reason = _classic_core_bridge.fallback_reason
	return false


func get_live_authority_diagnostics() -> Dictionary:
	return {
		"requested": LiveAuthority.keys()[requested_live_authority].to_lower(),
		"active": LiveAuthority.keys()[active_live_authority].to_lower(),
		"fallback_reason": live_authority_fallback_reason,
		"core_resolutions": _classic_core_bridge.resolution_count if _classic_core_bridge != null else 0,
		"rejected_transitions": _classic_core_bridge.rejected_transition_count if _classic_core_bridge != null else 0,
		"projection_mismatches": _classic_core_bridge.projection_mismatch_count if _classic_core_bridge != null else 0,
		"last_rejection_context": _classic_core_bridge.last_rejection_context if _classic_core_bridge != null else "",
		"last_projection_mismatch_context": _classic_core_bridge.last_projection_mismatch_context if _classic_core_bridge != null else "",
	}

func initialize_board():
	board.clear()
	tile_effects.clear()
	autonomous_entities.clear()
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
	board[7][4] = ArakneKing.new("white", Vector2i(7, 4))
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
	if piece.piece_id.is_empty():
		piece.piece_id = _allocate_state_id("piece")
	piece.model = self
	var instance_id := piece.get_instance_id()
	if not _owned_pieces.has(instance_id):
		_owned_pieces[instance_id] = piece
		owned_piece_registration_count += 1
	if piece is KingPiece:
		var king_piece: KingPiece = piece
		if king_piece.color == current_turn:
			king_piece.mark_initial_turn_entered()
		if active_ability_cooldowns_disabled:
			king_piece.set_cooldown(0)
		king_piece.announce_cooldown_state()

func set_active_ability_cooldowns_disabled(disabled: bool) -> void:
	active_ability_cooldowns_disabled = disabled
	if active_live_authority == LiveAuthority.CLASSIC_CORE and _classic_core_bridge != null:
		_classic_core_bridge.set_cooldowns_disabled(disabled)
	if not disabled:
		return
	for row in board:
		for piece in row:
			if piece is KingPiece:
				(piece as KingPiece).set_cooldown(0)

func unregister_piece(piece: ModelPiece) -> void:
	if not is_instance_valid(piece):
		return
	_owned_pieces.erase(piece.get_instance_id())
	if piece.model == self:
		piece.model = null


func _dispose_owned_pieces() -> int:
	var disposed := 0
	for raw_piece in _owned_pieces.values():
		if not is_instance_valid(raw_piece):
			continue
		var piece := raw_piece as ModelPiece
		unregister_piece(piece)
		piece.model = null
		piece.free()
		disposed += 1
	_owned_pieces.clear()
	owned_piece_disposal_count += disposed
	return disposed


## Releases every Node owned by this authoritative state. Safe to call more than
## once; _notification provides a backstop for callers that only free the model.
func dispose_owned_state() -> int:
	pending_reaction.clear()
	pending_movement_type_grant.clear()
	pending_promotion.clear()
	last_move.clear()
	var disposed := _dispose_owned_pieces()
	board.clear()
	tile_effects.clear()
	autonomous_entities.clear()
	action_in_progress = false
	action_owner_color = ""
	forced_pass_in_progress = false
	return disposed

func announce_ability_started(piece: KingPiece, ability_name: String) -> void:
	var completion := CompletionGate.new()
	ability_started.emit(piece, ability_name, completion)
	completion.close()
	await completion.wait_until_released()

func announce_piece_summoned(piece: ModelPiece) -> void:
	var completion := CompletionGate.new()
	piece_summoned.emit(piece, completion)
	completion.close()
	await completion.wait_until_released()

func _announce_piece_landed(piece: ModelPiece, from: Vector2i, to: Vector2i) -> void:
	var completion := CompletionGate.new()
	piece_landed.emit(piece, from, to, completion)
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
	if piece.piece_id.is_empty(): piece.piece_id = _allocate_state_id("piece")
	board[coord.x][coord.y] = piece
	inject_dependencies(piece)
	piece_added.emit(piece)
	if is_initialized and is_settled(): _resynchronize_live_authority()
	return true


func get_legal_moves(piece: ModelPiece) -> Array:
	return _classic_core_bridge.legal_moves(piece) if is_instance_valid(piece) and _classic_core_bridge != null and _classic_core_bridge.active else []

func get_legal_move_paths(piece: ModelPiece) -> Array:
	return _classic_core_bridge.legal_move_paths(piece) if is_instance_valid(piece) and _classic_core_bridge != null and _classic_core_bridge.active else []

func get_active_ability_targets(piece: KingPiece) -> Array:
	return _classic_core_bridge.active_ability_targets(piece) if is_instance_valid(piece) and _classic_core_bridge != null and _classic_core_bridge.active else []

func is_archer_suppressed(piece: ArcherKing) -> bool:
	return _classic_core_bridge.is_archer_suppressed(piece) if is_instance_valid(piece) and _classic_core_bridge != null and _classic_core_bridge.active else false

func request_movement_type_grant(king: QuarterlyInitiativeKing, target: ModelPiece) -> StringName:
	if not pending_movement_type_grant.is_empty():
		return &""
	var options: Array[StringName] = [&"pawn", &"knight", &"bishop", &"rook"]
	pending_movement_type_grant = {"king": king, "target": target, "options": options}
	movement_type_selection_requested.emit(king, target, options)
	var selected: StringName = await movement_type_selection_resolved
	return selected

func submit_movement_type_grant(movement_type: StringName) -> bool:
	if pending_movement_type_grant.is_empty():
		return false
	var options: Array = pending_movement_type_grant.get("options", [])
	if movement_type not in options:
		return false
	pending_movement_type_grant.clear()
	authoritative_selection_committed.emit(&"movement_type_grant", movement_type)
	movement_type_selection_resolved.emit(movement_type)
	return true


func request_promotion_selection(pawn: ModelPiece) -> StringName:
	if not pending_promotion.is_empty() or not is_piece_active(pawn) or pawn.type != "pawn":
		return &""
	var options: Array[StringName] = [&"queen", &"rook", &"bishop", &"knight"]
	pending_promotion = {"pawn": pawn, "options": options}
	promotion_selection_requested.emit(pawn, options)
	var selected: StringName = await promotion_selection_resolved
	return selected


func submit_promotion_selection(piece_type: StringName) -> bool:
	if pending_promotion.is_empty():
		return false
	var options: Array = pending_promotion.get("options", [])
	if piece_type not in options:
		return false
	pending_promotion.clear()
	authoritative_selection_committed.emit(&"promotion", piece_type)
	promotion_selection_resolved.emit(piece_type)
	return true

## Returns every primary command that color may legally submit right now.
## Command methods remain the final authority and revalidate their inputs.
func get_legal_primary_actions(color: String) -> Array[ChessPrimaryAction]:
	var actions: Array[ChessPrimaryAction] = []
	if color != current_turn or battle_over or action_in_progress or forced_pass_in_progress or has_pending_reaction():
		return actions
	return _collect_legal_primary_actions(color)


## Rule-only action enumeration used while the public command surface is locked.
func _collect_legal_primary_actions(color: String) -> Array[ChessPrimaryAction]:
	var actions: Array[ChessPrimaryAction] = []
	if color != current_turn or battle_over:
		return actions
	if _classic_core_bridge != null and _classic_core_bridge.active:
		actions.assign(_classic_core_bridge.legal_actions(color))
	return actions


func has_legal_primary_action(color: String) -> bool:
	return not _collect_legal_primary_actions(color).is_empty()

## Opens the presentation transaction for one already-validated core action.
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
	consecutive_forced_passes = 0
	_diagnostic("ACTION START — " + action_owner_color)
	action_started.emit(action_owner_color)
	return true

func cancel_action() -> void:
	action_in_progress = false
	action_owner_color = ""
	consecutive_forced_passes = 0
	action_cancelled.emit()

func resolve_unplayable_turns() -> bool:
	if battle_over or action_in_progress or has_pending_reaction() or forced_pass_in_progress:
		return false
	return await _classic_core_bridge.resolve_unplayable_turns() if _classic_core_bridge != null else false

func has_defeated_king() -> bool:
	return not defeated_king_colors.is_empty()

func submit_move(piece: ModelPiece, to: Vector2i) -> bool:
	if not is_piece_active(piece) or piece.color != current_turn or piece.stunned:
		return false
	if action_in_progress or battle_over:
		return false
	primary_action_committed.emit(ActionCodec.describe(ChessPrimaryAction.new(ChessPrimaryAction.Kind.MOVE, piece, to)))
	return await _classic_core_bridge.submit_move(piece, to) if _classic_core_bridge != null else false


func submit_move_path(piece: ModelPiece, path: Array[Vector2i]) -> bool:
	if not is_piece_active(piece) or piece.color != current_turn or piece.stunned:
		return false
	if action_in_progress or battle_over or path.is_empty():
		return false
	var legal := false
	for action in get_legal_primary_actions(current_turn):
		if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece == piece and action.path == path:
			legal = true
			break
	if not legal:
		return false
	primary_action_committed.emit(ActionCodec.describe(ChessPrimaryAction.new(ChessPrimaryAction.Kind.MOVE, piece, path.back(), path)))
	return await _classic_core_bridge.submit_move_path(piece, path) if _classic_core_bridge != null else false


func submit_active_ability(king: KingPiece, target: Vector2i) -> bool:
	if not is_piece_active(king) or king.color != current_turn or king.stunned:
		return false
	if action_in_progress or battle_over:
		return false
	primary_action_committed.emit(ActionCodec.describe(ChessPrimaryAction.new(ChessPrimaryAction.Kind.ACTIVE_ABILITY, king, target)))
	return await _classic_core_bridge.submit_active_ability(king, target) if _classic_core_bridge != null else false

func submit_archer_charge(archer: ArcherKing) -> bool:
	if not is_piece_active(archer) or archer.color != current_turn or archer.stunned:
		return false
	if action_in_progress or battle_over:
		return false
	primary_action_committed.emit(ActionCodec.describe(ChessPrimaryAction.new(ChessPrimaryAction.Kind.ARCHER_CHARGE, archer, archer.coordinate)))
	return await _classic_core_bridge.submit_archer_charge(archer) if _classic_core_bridge != null else false



func set_lunacy_random_seed(seed: int) -> void:
	_projected_random_states[&"lunacy"] = ClassicChessCore.seeded_random_state(seed)
	if _classic_core_bridge != null and _classic_core_bridge.state != null:
		_classic_core_bridge.state.random_states[&"lunacy"] = _projected_random_states[&"lunacy"]
func set_archer_volley_random_seed(seed: int) -> void:
	_projected_random_states[&"archer_volley"] = ClassicChessCore.seeded_random_state(seed)
	if _classic_core_bridge != null and _classic_core_bridge.state != null:
		_classic_core_bridge.state.random_states[&"archer_volley"] = _projected_random_states[&"archer_volley"]
func set_wraith_curse_mark_random_seed(seed: int) -> void:
	var stream := WraithCoreRules.CURSE_MARK_RANDOM_STREAM
	_projected_random_states[stream] = ClassicChessCore.seeded_random_state(seed)
	if _classic_core_bridge != null and _classic_core_bridge.state != null:
		_classic_core_bridge.state.random_states[stream] = _projected_random_states[stream]


func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < board.size() and col >= 0 and col < board[row].size()
	
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
			if piece != null and piece.color == color and piece.is_king:
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
	_diagnostic("white army's back rank is " + str(back_rank))
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
		
	
	piece_destroyed.emit(piece)
	
	
	# Only nullify if requested AND the piece is actually where we think it is
	if nullify_square and is_in_bounds(piece_coord.x, piece_coord.y) and board[piece_coord.x][piece_coord.y] == piece:
		board[piece_coord.x][piece_coord.y] = null
	unregister_piece(piece)

func transform_piece(piece: ModelPiece, transformed_type: StringName, present_promotion := false) -> void:
	if not is_instance_valid(piece):
		printerr("transform_piece: Invalid piece instance provided.")
		return
		
	if transformed_type not in [&"queen", &"rook", &"bishop", &"knight"]:
		return
	var r = piece.coordinate.x
	var c = piece.coordinate.y
	var transformed_piece := ChessPieceCatalog.create_piece(transformed_type, piece.color, Vector2i(r, c))
	if transformed_piece == null:
		return
	unregister_piece(piece)
	inject_dependencies(transformed_piece)
	board[r][c] = transformed_piece
	if present_promotion:
		var completion := CompletionGate.new()
		piece_promotion_committed.emit(piece, transformed_piece, completion)
		completion.close()
		await completion.wait_until_released()
	piece_transformed.emit(piece, transformed_piece)
		

## True only while a piece is alive and still occupies its recorded square.
## A freed visual node or a still-valid GDScript object is not enough.
func is_piece_active(piece: ModelPiece) -> bool:
	if not is_instance_valid(piece) or piece.current_hp <= 0:
		return false
	var coord := piece.coordinate
	return is_in_bounds(coord.x, coord.y) and board[coord.x][coord.y] == piece

func has_pending_reaction() -> bool:
	return not pending_reaction.is_empty()

func get_pending_reaction() -> Dictionary:
	return pending_reaction.duplicate(true)

func submit_reaction_selection(coord: Vector2i) -> bool:
	return await _classic_core_bridge.submit_reaction_selection(coord) if _classic_core_bridge != null else false

func get_other_color(color: String) -> String:
	if color == "white": return "black"
	else: return "white"

func _allocate_state_id(prefix: String) -> String:
	var result := "%s_%s" % [prefix, _next_state_id]
	_next_state_id += 1
	return result

func _reserve_state_id(id: String) -> void:
	var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
	if suffix.is_valid_int(): _next_state_id = maxi(_next_state_id, suffix.to_int() + 1)

func find_piece_by_id(id: String) -> ModelPiece:
	for row in board:
		for piece in row:
			if piece != null and piece.piece_id == id: return piece
	return null

func has_tile_effect(type_id: StringName, coord: Vector2i, source_piece_id := "") -> bool:
	return tile_effects.any(func(effect): return effect.type_id == type_id and effect.coordinate == coord and (source_piece_id.is_empty() or effect.source_piece_id == source_piece_id))

func has_autonomous_entity_from_source(source_piece_id: String, type_id: StringName = &"") -> bool:
	return autonomous_entities.any(func(entity): return entity.source_piece_id == source_piece_id and (type_id == &"" or entity.type_id == type_id))

func get_wraith_entities_from_source(source_piece_id: String) -> Array[ChessAutonomousEntityState]:
	var result: Array[ChessAutonomousEntityState] = []
	for entity in autonomous_entities:
		if entity.type_id == &"wraith" and entity.source_piece_id == source_piece_id:
			result.append(entity)
	return result

func get_wraith_replacement_candidate(source_piece_id: String) -> ChessAutonomousEntityState:
	var owned_wraiths := get_wraith_entities_from_source(source_piece_id)
	if owned_wraiths.size() < WraithKing.MAX_ACTIVE_WRAITHS:
		return null
	return owned_wraiths[0]

func get_mortar_area(anchor: Vector2i) -> Array[Vector2i]:
	return CannonCoreRules.area(anchor)
