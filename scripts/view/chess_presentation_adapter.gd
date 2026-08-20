extends Node
class_name ChessPresentationAdapter

## Bridges authoritative Model and Controller events to the visual chess board and UI.
#
# This scene-composed adapter receives its Model, Controller, board View, and result
# View through exported references. It connects their signals, maintains the mapping
# between each ModelPiece and its visual node, and translates domain or interaction
# events into rendering, animation, audio, highlighting, cooldown, and result updates.
#
## Add presentation responses for new game events here rather than placing visual
# behavior in the Model. Gameplay rules and authoritative state must remain in the
# Model; this adapter and the Views only represent that state. When an action must
# wait for presentation, a signal handler may synchronously hold its CompletionGate,
# await the animation, and then release the gate.

const SKULL_AURA_SCENE := preload("res://effects/skull_aura.tscn")

@export var model: ChessBoardModel
@export var controller: ChessBoardController
@export var view: ChessBoardView
@export var result_view: BattleResultView

var piece_views: Dictionary = {}
var necromancer_auras: Dictionary = {}
var selection_effect_piece: ModelPiece = null
var player_move_submission_active := false


func _ready() -> void:
	model.board_initialized.connect(_on_board_initialized)
	model.piece_added.connect(_on_piece_added)
	model.piece_summoned.connect(_on_piece_summoned)
	model.piece_move_committed.connect(_on_piece_move_committed)
	model.piece_attack_committed.connect(_on_piece_attack_committed)
	model.piece_destroyed.connect(_on_piece_destroyed)
	model.piece_transformed.connect(_on_piece_transformed)
	model.piece_damaged.connect(_on_piece_damaged)
	model.piece_stunned.connect(_on_piece_stunned)
	model.piece_recovered.connect(_on_piece_recovered)
	model.ability_started.connect(_on_ability_started)
	model.ability_effect_resolved.connect(_on_ability_effect_resolved)
	model.battle_finished.connect(result_view.show_battle_result)
	controller.ability_targeting_started.connect(_on_ability_targeting_started)
	controller.ability_targeting_ended.connect(_on_ability_targeting_ended)
	controller.selection_piece_processing.connect(_on_selection_piece_processing)
	controller.selection_piece_processed.connect(_on_selection_piece_processed)
	controller.selection_targets_changed.connect(_on_selection_targets_changed)
	controller.selection_cleared.connect(_on_selection_cleared)
	controller.ordinary_move_submission_started.connect(_on_ordinary_move_submission_started)
	controller.ordinary_move_submission_finished.connect(_on_ordinary_move_submission_finished)
	view.square_selected.connect(controller._on_square_clicked)

	if not model.board.is_empty():
		_on_board_initialized(model.board)


func get_piece_view(piece: ModelPiece) -> Node:
	return piece_views.get(piece)


func _on_board_initialized(board: Array) -> void:
	piece_views = view.draw_board(board)
	for row in board:
		for piece in row:
			if piece != null:
				_register_piece(piece, view.get_piece_node(piece.coordinate))


func _on_piece_added(piece: ModelPiece) -> void:
	_register_piece(piece, view.draw_piece(piece))


func _on_piece_summoned(piece: ModelPiece, completion: CompletionGate) -> void:
	if not piece is BonePawn:
		return
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		return
	completion.hold()
	await view.play_bone_pawn_summon(piece_node)
	completion.release()


func _on_piece_move_committed(piece: ModelPiece, from: Vector2i, to: Vector2i, gate: CompletionGate) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		printerr("Presentation has no visual node for ", piece.type, " at ", to)
		return

	gate.hold()
	if player_move_submission_active and piece.color == view.viewing_color and controller.is_player_controlled(piece.color):
		await view.move_piece_node_with_player_hand(piece_node, from, to)
	else:
		await view.move_piece_node(piece_node, to)
	gate.release()


func _on_ordinary_move_submission_started(_piece: ModelPiece, _target: Vector2i) -> void:
	player_move_submission_active = true


func _on_ordinary_move_submission_finished(_piece: ModelPiece, _target: Vector2i, _accepted: bool) -> void:
	player_move_submission_active = false


func _on_piece_attack_committed(piece: ModelPiece, _from: Vector2i, to: Vector2i, gate: CompletionGate) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		printerr("Presentation has no visual node for attacking ", piece.type)
		return

	gate.hold()
	await view.attack_piece_node(piece_node, to)
	gate.release()


func _on_piece_destroyed(piece: ModelPiece) -> void:
	var piece_node: Node = piece_views.get(piece)
	piece_views.erase(piece)
	necromancer_auras.erase(piece)
	if is_instance_valid(piece_node):
		view.destroy_piece(piece_node)


func _on_piece_transformed(old_piece: ModelPiece, new_piece: ModelPiece) -> void:
	var old_node: Node = piece_views.get(old_piece)
	piece_views.erase(old_piece)
	if is_instance_valid(old_node):
		view.remove_piece(old_node)
	_register_piece(new_piece, view.draw_piece(new_piece))


func _on_piece_damaged(piece: ModelPiece, _amount: int, current_hp: int, _max_hp: int) -> void:
	var piece_node: Node = get_piece_view(piece)
	if is_instance_valid(piece_node):
		view.spawn_splatter(piece_node)
		piece_node.update_hp(current_hp)


func _on_piece_stunned(piece: ModelPiece, _duration: int) -> void:
	var piece_node: Node = get_piece_view(piece)
	if is_instance_valid(piece_node):
		view.spawn_stun_stars(piece_node)


func _on_piece_recovered(piece: ModelPiece) -> void:
	var piece_node: Node = get_piece_view(piece)
	if is_instance_valid(piece_node):
		view.remove_stun_stars_from_piece(piece_node)


func _on_ability_started(piece: KingPiece, ability_name: String, gate: CompletionGate) -> void:
	if piece is MinotaurKing and ability_name == MinotaurKing.PASSIVE_ABILITY_NAME:
		var piece_node: Node = get_piece_view(piece)
		if not is_instance_valid(piece_node):
			return
		gate.hold()
		await view.start_minotaur_rage_intro(piece_node)
		gate.release()


func _on_ability_effect_resolved(piece: KingPiece, ability_name: String, affected_coords: Array) -> void:
	if piece is MinotaurKing and ability_name == MinotaurKing.PASSIVE_ABILITY_NAME:
		view.minotaur_retaliate(affected_coords)


func _on_ability_targeting_started(king: KingPiece, _ability_name: String, _targets: Array) -> void:
	view.clear_highlights()
	view.show_legal_moves(_targets)
	view.flash_screen()
	var piece_node: Node = get_piece_view(king)
	if king is MinotaurKing and is_instance_valid(piece_node):
		view.spawn_ss_aura(piece_node)
	elif king is NecromancerKing:
		_show_necromancer_aura(king)


func _on_ability_targeting_ended(king: KingPiece, _ability_name: String, reason: String) -> void:
	view.clear_highlights()
	var piece_node: Node = get_piece_view(king)
	if king is MinotaurKing and is_instance_valid(piece_node):
		view.fade_out_ss_aura(piece_node, reason == "cancelled")
	elif king is NecromancerKing:
		_hide_necromancer_aura(king)


func _on_selection_piece_processing(piece: ModelPiece) -> void:
	selection_effect_piece = piece
	if piece is NecromancerKing:
		_show_necromancer_aura(piece)


func _on_selection_piece_processed() -> void:
	if selection_effect_piece is NecromancerKing:
		_hide_necromancer_aura(selection_effect_piece)
	selection_effect_piece = null


func _on_selection_targets_changed(targets: Array) -> void:
	view.clear_highlights()
	view.highlight_squares(targets)


func _on_selection_cleared() -> void:
	view.clear_highlights()


func _show_necromancer_aura(piece: NecromancerKing) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		return
	var aura: Node = necromancer_auras.get(piece)
	if not is_instance_valid(aura):
		aura = SKULL_AURA_SCENE.instantiate()
		if piece_node.has_method("get_body_anchor"):
			piece_node.get_body_anchor().add_child(aura)
		else:
			piece_node.add_child(aura)
		necromancer_auras[piece] = aura
	aura.restart()
	aura.emitting = true


func _hide_necromancer_aura(piece: NecromancerKing) -> void:
	var aura: Node = necromancer_auras.get(piece)
	if is_instance_valid(aura):
		aura.emitting = false


func _register_piece(piece: ModelPiece, piece_node: Node) -> void:
	if not is_instance_valid(piece_node):
		return
	piece_views[piece] = piece_node
	if piece is KingPiece:
		var king := piece as KingPiece
		if not king.cooldown_changed.is_connected(_on_cooldown_changed):
			king.cooldown_changed.connect(_on_cooldown_changed)
		if not king.cooldown_ready.is_connected(_on_cooldown_ready):
			king.cooldown_ready.connect(_on_cooldown_ready)
		if king.current_cooldown > 0:
			_on_cooldown_changed(king, king.current_cooldown)
		else:
			_on_cooldown_ready(king)


func _on_cooldown_changed(king: KingPiece, new_cooldown: int) -> void:
	view.update_cooldown_display(king, new_cooldown)


func _on_cooldown_ready(king: KingPiece) -> void:
	view.ready_cooldown_display(king)
