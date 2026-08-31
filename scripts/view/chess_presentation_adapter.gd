extends Node
class_name ChessPresentationAdapter

const PresentationPolicy = preload("res://scripts/view/chess_presentation_policy.gd")
const KingMagicController = preload("res://scripts/view/chess_king_magic_controller.gd")
const KingPresentationProfile = preload("res://scripts/view/chess_king_presentation_profile.gd")

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
@export var presentation_policy: Resource

var piece_views: Dictionary = {}
var necromancer_auras: Dictionary = {}
var selection_effect_piece: ModelPiece = null
var player_move_submission_active := false
var silently_removed_piece_views: Dictionary = {}
var pending_attack_damage_visuals: Dictionary = {}
var king_magic_controllers: Dictionary = {}
var player_color := "white"
var player_presentation: Resource
var opponent_presentation: Resource


func _ready() -> void:
	if presentation_policy == null:
		presentation_policy = PresentationPolicy.new()
	_apply_presentation_policy()
	model.board_initialized.connect(_on_board_initialized)
	model.board_rebuilt.connect(_on_board_rebuilt)
	model.piece_added.connect(_on_piece_added)
	model.piece_summoned.connect(_on_piece_summoned)
	model.piece_move_committed.connect(_on_piece_move_committed)
	model.piece_capture_committed.connect(_on_piece_capture_committed)
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


func configure_army_presentations(color: String, player_profile: Resource, opponent_profile: Resource) -> void:
	player_color = "black" if color == "black" else "white"
	player_presentation = player_profile
	opponent_presentation = opponent_profile
	refresh_magic_controllers()


func refresh_magic_controllers() -> void:
	_clear_magic_controllers()
	for piece in piece_views:
		if piece is KingPiece:
			_register_king_magic(piece, piece_views[piece])


func _on_board_initialized(board: Array) -> void:
	piece_views = view.draw_board(board)
	for row in board:
		for piece in row:
			if piece != null:
					_register_piece(piece, view.get_piece_node(piece.coordinate))

func _on_board_rebuilt(board: Array) -> void:
	_clear_magic_controllers()
	piece_views.clear()
	necromancer_auras.clear()
	silently_removed_piece_views.clear()
	pending_attack_damage_visuals.clear()
	selection_effect_piece = null
	player_move_submission_active = false
	piece_views = view.rebuild_board(board)
	for row in board:
		for piece in row:
			if piece != null:
				_register_piece(piece, view.get_piece_node(piece.coordinate))
				if piece.stunned:
					view.spawn_stun_stars(piece_views.get(piece))
	if result_view != null:
		if model.battle_over:
			result_view.show_battle_result(model.battle_result)
		else:
			result_view.reset_result()


func _on_piece_added(piece: ModelPiece) -> void:
	_register_piece(piece, view.draw_piece(piece))


func _on_piece_summoned(piece: ModelPiece, completion: CompletionGate) -> void:
	if not piece is BonePawn:
		return
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		return
	if not presentation_policy.should_hold_completion_gate():
		return
	completion.hold()
	await view.play_bone_pawn_summon(piece_node)
	completion.release()


func _on_piece_move_committed(piece: ModelPiece, from: Vector2i, to: Vector2i, gate: CompletionGate) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		printerr("Presentation has no visual node for ", piece.type, " at ", to)
		return
	if not presentation_policy.should_hold_completion_gate():
		view.snap_piece_node(piece_node, to)
		return

	gate.hold()
	if piece is KingPiece:
		var magic := _get_king_magic(piece)
		if magic != null:
			await magic.play_move(from, to)
		else:
			await _play_unpowered_king_move(piece_node, to)
		gate.release()
		return
	await view.move_piece_node_with_hand(piece_node, from, to)
	gate.release()


func _on_piece_capture_committed(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, _captured_at: Vector2i, gate: CompletionGate) -> void:
	var attacker_node: Node = get_piece_view(attacker)
	var defender_node: Node = get_piece_view(defender)
	if not is_instance_valid(attacker_node):
		return
	if not presentation_policy.should_hold_completion_gate():
		view.snap_piece_node(attacker_node, to)
		return

	gate.hold()
	if attacker is KingPiece:
		var magic := _get_king_magic(attacker)
		if magic != null and is_instance_valid(defender_node):
			await magic.play_capture(from, to, defender_node)
			silently_removed_piece_views[defender] = true
		else:
			await _play_unpowered_king_move(attacker_node, to)
		gate.release()
		return
	var carried_offscreen := false
	if is_instance_valid(defender_node):
		carried_offscreen = await view.capture_piece_node_with_hand(attacker_node, defender_node, from, to)
	else:
		await view.move_piece_node(attacker_node, to)
	if carried_offscreen:
		silently_removed_piece_views[defender] = true
	gate.release()


func _on_ordinary_move_submission_started(_piece: ModelPiece, _target: Vector2i) -> void:
	player_move_submission_active = true


func _on_ordinary_move_submission_finished(_piece: ModelPiece, _target: Vector2i, _accepted: bool) -> void:
	player_move_submission_active = false


func _on_piece_attack_committed(piece: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, gate: CompletionGate) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		printerr("Presentation has no visual node for attacking ", piece.type)
		return
	if not presentation_policy.should_hold_completion_gate():
		return

	gate.hold()
	pending_attack_damage_visuals[defender] = []
	var contact_callback := func(): _flush_pending_attack_damage(defender)
	if piece is KingPiece:
		var magic := _get_king_magic(piece)
		if magic != null:
			await magic.play_attack(from, to, contact_callback)
		else:
			await view.attack_piece_node(piece_node, to, contact_callback)
	else:
		await view.attack_piece_node_with_hand(piece_node, from, to, contact_callback)
	# Never strand an HP display if an animation implementation exits without
	# invoking its contact callback.
	_flush_pending_attack_damage(defender)
	pending_attack_damage_visuals.erase(defender)
	gate.release()


func _on_piece_destroyed(piece: ModelPiece) -> void:
	pending_attack_damage_visuals.erase(piece)
	var piece_node: Node = piece_views.get(piece)
	var magic: Node = king_magic_controllers.get(piece)
	king_magic_controllers.erase(piece)
	if is_instance_valid(magic): magic.queue_free()
	piece_views.erase(piece)
	necromancer_auras.erase(piece)
	if is_instance_valid(piece_node):
		if not presentation_policy.should_animate():
			view.remove_piece(piece_node)
			return
		if silently_removed_piece_views.has(piece):
			silently_removed_piece_views.erase(piece)
			view.remove_piece(piece_node)
		else:
			view.destroy_piece(piece_node)


func _on_piece_transformed(old_piece: ModelPiece, new_piece: ModelPiece) -> void:
	var old_node: Node = piece_views.get(old_piece)
	piece_views.erase(old_piece)
	var old_magic: Node = king_magic_controllers.get(old_piece)
	king_magic_controllers.erase(old_piece)
	if is_instance_valid(old_magic): old_magic.queue_free()
	if is_instance_valid(old_node):
		view.remove_piece(old_node)
	_register_piece(new_piece, view.draw_piece(new_piece))


func _on_piece_damaged(piece: ModelPiece, _amount: int, current_hp: int, _max_hp: int) -> void:
	if pending_attack_damage_visuals.has(piece):
		var queued_visuals: Array = pending_attack_damage_visuals[piece]
		queued_visuals.append(current_hp)
		return
	_present_piece_damage(piece, current_hp)


func _flush_pending_attack_damage(piece: ModelPiece) -> void:
	if not pending_attack_damage_visuals.has(piece):
		return
	var queued_visuals: Array = pending_attack_damage_visuals[piece]
	while not queued_visuals.is_empty():
		_present_piece_damage(piece, int(queued_visuals.pop_front()))


func _present_piece_damage(piece: ModelPiece, current_hp: int) -> void:
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
	if not presentation_policy.should_hold_completion_gate():
		return
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
		_register_king_magic(piece, piece_node)


func _register_king_magic(piece: KingPiece, piece_node: PieceView) -> void:
	if not is_instance_valid(piece_node) or king_magic_controllers.has(piece):
		return
	var army_profile := player_presentation if piece.color == player_color else opponent_presentation
	var king_profile: Resource = army_profile.king_presentation if army_profile != null else null
	if king_profile == null:
		king_profile = KingPresentationProfile.new()
		king_profile.ensure_defaults()
	var magic := KingMagicController.new()
	view.add_child(magic)
	magic.configure(view, view.get_hand_rig_for_color(piece.color), piece_node, king_profile)
	king_magic_controllers[piece] = magic


func _get_king_magic(piece: ModelPiece) -> Node:
	var magic: Node = king_magic_controllers.get(piece) as Node
	if not is_instance_valid(magic):
		var piece_node := get_piece_view(piece) as PieceView
		if piece is KingPiece and is_instance_valid(piece_node):
			_register_king_magic(piece, piece_node)
			magic = king_magic_controllers.get(piece) as Node
	return magic


func _clear_magic_controllers() -> void:
	for magic in king_magic_controllers.values():
		if is_instance_valid(magic): magic.queue_free()
	king_magic_controllers.clear()


func _play_unpowered_king_move(piece_node: PieceView, to: Vector2i) -> void:
	var fallback := KingMagicController.new()
	view.add_child(fallback)
	fallback.configure(view, null, piece_node, null)
	await fallback.play_move(piece_node.coordinate, to)
	fallback.queue_free()


func _on_cooldown_changed(king: KingPiece, new_cooldown: int) -> void:
	view.update_cooldown_display(king, new_cooldown)


func _on_cooldown_ready(king: KingPiece) -> void:
	view.ready_cooldown_display(king)

func set_presentation_speed(speed: int) -> void:
	presentation_policy.speed = speed
	_apply_presentation_policy()

func _apply_presentation_policy() -> void:
	if view == null:
		return
	view.animation_duration_scale = presentation_policy.duration_scale()
	for hand_rig in [view.near_hand_rig, view.far_hand_rig]:
		if is_instance_valid(hand_rig):
			hand_rig.animation_duration_scale = presentation_policy.duration_scale()
