extends Node
class_name ChessPresentationAdapter

const KingDeathProfile := preload("res://scripts/view/chess_king_death_profile.gd")
const DEFAULT_KING_DEATH_PROFILE := preload("res://assets/chess_king_death.tres")
const DEFAULT_ABILITY_PRESENTATIONS := preload("res://assets/chess_ability_presentations.tres")
const DEFAULT_COOLDOWN_PRESENTATION := preload("res://assets/chess_king_cooldown_presentation.tres")
const SpecialMoveDirector := preload("res://scripts/view/chess_special_move_director.gd")
const SpecialMoveProfile := preload("res://scripts/view/chess_special_move_presentation_profile.gd")
const AbilityHandProfile := preload("res://scripts/view/chess_ability_hand_profile.gd")

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
const SKULL_BURST_SCENE := preload("res://effects/skull_burst.tscn")

@export var model: ChessBoardModel
@export var controller: ChessBoardController
@export var view: ChessBoardView
@export var result_view: BattleResultView
@export var presentation_policy: Resource
@export var king_death_profile: Resource = DEFAULT_KING_DEATH_PROFILE
@export var screen_shake: Node
@export var ability_presentations: Resource = DEFAULT_ABILITY_PRESENTATIONS
@export var cooldown_presentation_profile: Resource = DEFAULT_COOLDOWN_PRESENTATION
@export var arakne_skitter_sound: AudioStream
@export_range(-80.0, 24.0, 0.1) var arakne_skitter_volume_db := 0.0
@export var reaction_trigger_sound: AudioStream
@export_range(-80.0, 24.0, 0.1) var reaction_trigger_volume_db := 0.0
@export_range(0.0, 2.0, 0.05) var nonlocal_ability_reveal_duration := 0.6

var piece_views: Dictionary = {}
var necromancer_auras: Dictionary = {}
var selection_effect_piece: ModelPiece = null
var player_move_submission_active := false
var silently_removed_piece_views: Dictionary = {}
var persistent_king_corpses: Dictionary = {}
var pending_attack_damage_visuals: Dictionary = {}
var king_magic_controllers: Dictionary = {}
var player_color := "white"
var player_presentation: Resource
var opponent_presentation: Resource
var active_king_deaths: Array[Node] = []
var pending_projectile_defeats: Dictionary = {}
var presented_promotions: Dictionary = {}
var skitter_sound_player := AudioStreamPlayer.new()
var reaction_sound_player := AudioStreamPlayer.new()
var reaction_sound_scheduled := false
var pending_skitter_steps: Dictionary = {}
var pending_charge_aura_impacts: Dictionary = {}
var committed_charge_actions: Dictionary = {}
var locally_previewed_abilities: Dictionary = {}
var retained_capture_piece_views: Dictionary = {}
var pending_damage_reactions: Dictionary = {}
var raise_dead_skull_anchors: Dictionary = {}


func _ready() -> void:
	skitter_sound_player.name = "ArakneSkitterSound"
	skitter_sound_player.bus = &"SFX"
	add_child(skitter_sound_player)
	reaction_sound_player.name = "ReactionTriggerSound"
	reaction_sound_player.bus = &"SFX"
	add_child(reaction_sound_player)
	if presentation_policy == null:
		presentation_policy = PresentationPolicy.new()
	_apply_presentation_policy()
	model.board_initialized.connect(_on_board_initialized)
	model.board_rebuilt.connect(_on_board_rebuilt)
	model.piece_added.connect(_on_piece_added)
	model.piece_summoned.connect(_on_piece_summoned)
	model.piece_move_committed.connect(_on_piece_move_committed)
	model.skitter_step_started.connect(_on_skitter_step_started)
	model.piece_castling_committed.connect(_on_piece_castling_committed)
	model.piece_capture_committed.connect(_on_piece_capture_committed)
	model.piece_attack_committed.connect(_on_piece_attack_committed)
	model.piece_promotion_committed.connect(_on_piece_promotion_committed)
	model.piece_destroyed.connect(_on_piece_destroyed)
	model.piece_transformed.connect(_on_piece_transformed)
	model.piece_damaged.connect(_on_piece_damaged)
	model.piece_stunned.connect(_on_piece_stunned)
	model.piece_recovered.connect(_on_piece_recovered)
	model.ability_started.connect(_on_ability_started)
	model.targeted_ability_committed.connect(_on_targeted_ability_committed)
	model.reaction_selection_preparing.connect(_on_reaction_selection_preparing)
	model.reaction_selection_committed.connect(_on_reaction_selection_committed)
	model.reaction_queued.connect(_on_reaction_queued)
	model.reaction_finished.connect(_on_reaction_finished)
	model.ability_effect_resolved.connect(_on_ability_effect_resolved)
	model.battle_finished.connect(_on_battle_finished)
	controller.ability_targeting_started.connect(_on_ability_targeting_started)
	controller.ability_targeting_preparing.connect(_on_ability_targeting_preparing)
	controller.ability_targeting_ended.connect(_on_ability_targeting_ended)
	controller.selection_piece_processing.connect(_on_selection_piece_processing)
	controller.selection_piece_processed.connect(_on_selection_piece_processed)
	controller.selection_targets_changed.connect(_on_selection_targets_changed)
	controller.selection_cleared.connect(_on_selection_cleared)
	controller.piece_selected.connect(_on_piece_selected)
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


func get_king_magic_controller(color: String) -> ChessKingMagicController:
	if model == null:
		return null
	var king := model.get_king(color)
	return _get_king_magic(king) as ChessKingMagicController if king != null else null


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
	persistent_king_corpses.clear()
	pending_attack_damage_visuals.clear()
	pending_charge_aura_impacts.clear()
	committed_charge_actions.clear()
	locally_previewed_abilities.clear()
	retained_capture_piece_views.clear()
	pending_damage_reactions.clear()
	_clear_raise_dead_skull_anchors()
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


func _on_piece_move_committed(piece: ModelPiece, from: Vector2i, to: Vector2i, presentation) -> void:
	committed_charge_actions.erase(piece)
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node):
		pending_charge_aura_impacts.erase(piece)
		printerr("Presentation has no visual node for ", piece.type, " at ", to)
		return
	if not presentation_policy.should_hold_completion_gate():
		view.snap_piece_node(piece_node, to, not (piece is KingPiece))
		_disperse_pending_charge_aura(piece, piece_node)
		pending_skitter_steps.erase(piece)
		return

	presentation.claim()
	var report_arrival := func():
		_disperse_pending_charge_aura(piece, piece_node)
		presentation.mark_arrived(piece)
	if piece.type == "pawn" and (to.x == 0 or to.x == model.board.size() - 1):
		report_arrival.call()
		await view.remove_promoting_pawn_with_hand(piece_node)
		presentation.finish_aftermath()
		return
	if piece is KingPiece:
		var is_skitter_followup := pending_skitter_steps.erase(piece)
		var magic := _get_king_magic(piece)
		if magic != null:
			if is_skitter_followup:
				await magic.play_followup_move(to, report_arrival)
			else:
				await magic.play_move(from, to, false, report_arrival)
		else:
			await _play_unpowered_king_move(piece_node, to, report_arrival)
		presentation.finish_aftermath()
		return
	await view.move_piece_node_with_hand(piece_node, from, to, true, true, &"", report_arrival)
	presentation.finish_aftermath()


func _on_skitter_step_started(piece: ArakneKing, _from: Vector2i, _to: Vector2i) -> void:
	pending_skitter_steps[piece] = true
	if arakne_skitter_sound == null:
		return
	skitter_sound_player.stream = arakne_skitter_sound
	skitter_sound_player.volume_db = arakne_skitter_volume_db
	skitter_sound_player.play()


func _on_piece_castling_committed(king: KingPiece, rook: ModelPiece, king_from: Vector2i, king_to: Vector2i, rook_from: Vector2i, rook_to: Vector2i, presentation) -> void:
	var king_node := get_piece_view(king) as PieceView
	var rook_node := get_piece_view(rook) as PieceView
	if not is_instance_valid(king_node) or not is_instance_valid(rook_node):
		return
	if not presentation_policy.should_hold_completion_gate():
		view.snap_piece_node(rook_node, rook_to)
		view.snap_piece_node(king_node, king_to, false)
		return

	presentation.claim()
	var magic := _get_king_magic(king) as ChessKingMagicController
	var hand := view.get_hand_rig_for_color(rook.color)
	var continue_hand_visit := (
		is_instance_valid(magic)
		and is_instance_valid(hand)
		and hand.can_animate()
		and magic.hand == hand
	)
	await view.move_piece_node_with_hand(rook_node, rook_from, rook_to, true, not continue_hand_visit, ChessHandRig.CARRY_PATH_SLIDE, func(): presentation.mark_arrived(rook))
	if is_instance_valid(magic):
		await magic.play_move(king_from, king_to, continue_hand_visit, func(): presentation.mark_arrived(king))
	else:
		await _play_unpowered_king_move(king_node, king_to, func(): presentation.mark_arrived(king))
	presentation.finish_aftermath()


func _on_piece_capture_committed(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, _captured_at: Vector2i, presentation) -> void:
	var is_committed_charge := committed_charge_actions.erase(attacker)
	var attacker_node: Node = get_piece_view(attacker)
	var defender_node: Node = get_piece_view(defender)
	if not is_instance_valid(attacker_node):
		return
	if not presentation_policy.should_hold_completion_gate():
		view.snap_piece_node(attacker_node, to, not (attacker is KingPiece))
		return

	retained_capture_piece_views[defender] = true
	presentation.claim()
	if defender is KingPiece and is_instance_valid(defender_node):
		var is_charge_impact := is_committed_charge
		var defender_magic := _get_king_magic(defender)
		var death_profile: Resource = king_death_profile if king_death_profile != null else KingDeathProfile.new()
		var death_effect := view.create_king_death_effect(defender_node, death_profile, screen_shake)
		if is_instance_valid(defender_magic):
			death_effect.death_beat_reached.connect(defender_magic.disable_effects, CONNECT_ONE_SHOT)
		var death_contact := func():
			# Lethal captures bypass ModelPiece.take_damage(), so reproduce the
			# ordinary hit feedback explicitly at physical contact. The splatter
			# scene owns the universal hurt sound as well as the blood animation.
			_present_damage_splatter(defender, defender_node)
			presentation.mark_impact()
			if is_charge_impact:
				_disperse_pending_charge_aura(attacker, attacker_node)
			death_effect.play()
			presentation.mark_arrived(attacker)
		if attacker is KingPiece:
			var attacking_magic := _get_king_magic(attacker)
			if is_charge_impact and attacking_magic != null:
				await attacking_magic.play_move(from, to, false, death_contact)
			elif is_charge_impact:
				await _play_unpowered_king_move(attacker_node, to, death_contact)
			elif attacking_magic != null:
				await attacking_magic.play_attack(from, to, death_contact)
			else:
				await view.attack_piece_node(attacker_node, to, death_contact)
		else:
			await view.attack_piece_node_with_hand(attacker_node, from, to, death_contact)
		if not death_effect.running and not death_effect.finished: death_effect.play()
		if not death_effect.result_ready: await death_effect.result_ready_for_display
		persistent_king_corpses[defender] = true
		_finalize_retained_capture_view(defender, defender_node, true)
		presentation.finish_aftermath()
		return
	if attacker is KingPiece:
		var magic := _get_king_magic(attacker)
		if magic != null and is_instance_valid(defender_node):
			magic.capture_impact.connect(func(_defender: PieceView): presentation.mark_impact(), CONNECT_ONE_SHOT)
			if pending_charge_aura_impacts.has(attacker):
				magic.capture_impact.connect(
					func(_defender: PieceView): _disperse_pending_charge_aura(attacker, attacker_node),
					CONNECT_ONE_SHOT
				)
			await magic.play_capture(from, to, defender_node, func(): presentation.mark_arrived(attacker))
		else:
			await _play_unpowered_king_move(attacker_node, to, func():
				presentation.mark_impact()
				presentation.mark_arrived(attacker)
			)
			_disperse_pending_charge_aura(attacker, attacker_node)
		_finalize_retained_capture_view(defender, defender_node, false)
		presentation.finish_aftermath()
		return
	var carried_offscreen := false
	if is_instance_valid(defender_node):
		carried_offscreen = await view.capture_piece_node_with_hand(
			attacker_node, defender_node, from, to,
			func(): presentation.mark_arrived(attacker),
			func(): presentation.mark_impact()
		)
	else:
		await view.move_piece_node(attacker_node, to)
		presentation.mark_impact()
		presentation.mark_arrived(attacker)
	_finalize_retained_capture_view(defender, defender_node, false)
	presentation.finish_aftermath()


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
	pending_charge_aura_impacts.erase(piece)
	committed_charge_actions.erase(piece)
	locally_previewed_abilities.erase(piece)
	if retained_capture_piece_views.has(piece):
		return
	var piece_node: Node = piece_views.get(piece)
	var magic: Node = king_magic_controllers.get(piece)
	var death_profile: Resource = king_death_profile if piece is KingPiece else null
	var magic_cleanup_deferred := false
	king_magic_controllers.erase(piece)
	piece_views.erase(piece)
	necromancer_auras.erase(piece)
	if pending_projectile_defeats.has(piece) and not (piece is KingPiece):
		# The projectile sequence owns this already-defeated view until its
		# ballistic flight has completely cleared the viewport.
		return
	if is_instance_valid(piece_node):
		if not presentation_policy.should_animate():
			view.remove_piece(piece_node)
		elif persistent_king_corpses.has(piece):
			# The model no longer owns this piece, but its awakened body remains as
			# inert stone presentation until the board is rebuilt or battle exits.
			persistent_king_corpses.erase(piece)
		elif silently_removed_piece_views.has(piece):
			silently_removed_piece_views.erase(piece)
			view.remove_piece(piece_node)
		else:
			var death_effect: Node
			if piece is KingPiece:
				death_effect = view.create_king_death_effect(piece_node, death_profile, screen_shake)
				if is_instance_valid(magic):
					death_effect.death_beat_reached.connect(func(): _dispose_king_magic(magic), CONNECT_ONE_SHOT)
					magic_cleanup_deferred = true
				death_effect.play()
			else:
				death_effect = view.destroy_piece(piece_node, death_profile, screen_shake)
			if is_instance_valid(death_effect):
				active_king_deaths.append(death_effect)
	if is_instance_valid(magic) and not magic_cleanup_deferred:
		_dispose_king_magic(magic)


func _dispose_king_magic(magic: Node) -> void:
	if not is_instance_valid(magic):
		return
	magic.disable_effects()
	magic.queue_free()


func _on_battle_finished(winner_color: String) -> void:
	_clear_raise_dead_skull_anchors()
	for effect in active_king_deaths:
		if is_instance_valid(effect) and not effect.result_ready:
			await effect.result_ready_for_display
	active_king_deaths.clear()
	result_view.show_battle_result(winner_color)


func _on_piece_transformed(old_piece: ModelPiece, new_piece: ModelPiece) -> void:
	if presented_promotions.erase(new_piece):
		return
	var old_node: Node = piece_views.get(old_piece)
	piece_views.erase(old_piece)
	var old_magic: Node = king_magic_controllers.get(old_piece)
	king_magic_controllers.erase(old_piece)
	if is_instance_valid(old_magic): old_magic.queue_free()
	if is_instance_valid(old_node):
		view.remove_piece(old_node)
	_register_piece(new_piece, view.draw_piece(new_piece))


func _on_piece_promotion_committed(old_piece: ModelPiece, new_piece: ModelPiece, gate: CompletionGate) -> void:
	var old_node := get_piece_view(old_piece) as Node2D
	if not is_instance_valid(old_node):
		return
	if not presentation_policy.should_hold_completion_gate():
		return

	gate.hold()
	var new_node := view.draw_piece(new_piece) as Node2D
	if not is_instance_valid(new_node):
		gate.release()
		return
	new_node.visible = false
	_register_piece(new_piece, new_node)
	presented_promotions[new_piece] = true
	# A quiet terminal-rank move already carried its pawn offscreen. A capture
	# must first finish its capture choreography, so remove that pawn here.
	if old_node.visible:
		await view.remove_promoting_pawn_with_hand(old_node)
	await view.place_promoted_piece_with_hand(new_node, new_piece.coordinate)
	piece_views.erase(old_piece)
	if is_instance_valid(old_node):
		view.remove_piece(old_node)
	gate.release()


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
	_release_pending_damage_reactions(piece)


func _present_piece_damage(piece: ModelPiece, current_hp: int) -> void:
	var piece_node: Node = get_piece_view(piece)
	if not is_instance_valid(piece_node) or not should_present_damage_feedback(piece):
		return
	_present_damage_splatter(piece, piece_node)
	piece_node.update_hp(current_hp)


static func should_present_damage_feedback(piece: ModelPiece) -> bool:
	return piece != null and (piece.is_king or piece.max_hp > 1)


func _present_damage_splatter(piece: ModelPiece, piece_node: Node2D = null) -> void:
	if not should_present_damage_feedback(piece):
		return
	var resolved_view := piece_node if is_instance_valid(piece_node) else get_piece_view(piece) as Node2D
	if is_instance_valid(resolved_view):
		view.spawn_splatter(resolved_view)


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


func _on_targeted_ability_committed(context) -> void:
	if context.ability_id == MinotaurKing.ACTIVE_ABILITY_ID:
		committed_charge_actions[context.source] = true
	var was_locally_previewed: bool = locally_previewed_abilities.get(context.source, &"") == context.ability_id
	locally_previewed_abilities.erase(context.source)
	if not presentation_policy.should_hold_completion_gate():
		return
	var profile: Resource = null
	var hand_profile := _get_ability_hand_profile(context.source, context.ability_id)
	if ability_presentations != null:
		profile = ability_presentations.find_profile(context.source.get_position_type_id(), context.ability_id)
	var source_view := get_piece_view(context.source) as PieceView
	var target_view := get_piece_view(context.target_piece) as PieceView
	var has_projectile_presentation := profile != null and is_instance_valid(source_view) and is_instance_valid(target_view)
	# Stationary local previews have already completed their hand choreography.
	# Directional previews must continue so the waiting hand can swipe toward the
	# authoritative target instead of falling through to a fresh move gesture.
	if (
		was_locally_previewed
		and hand_profile.command_style == AbilityHandProfile.CommandStyle.STATIONARY
		and not has_projectile_presentation
	):
		return
	context.claim()
	if not was_locally_previewed:
		var magic := _get_king_magic(context.source)
		if is_instance_valid(magic):
			await magic.prepare_ability_hand(hand_profile.pre_reveal_hover_duration)
		_reveal_ability_windup(context.source)
		if hand_profile.command_style == AbilityHandProfile.CommandStyle.STATIONARY and is_instance_valid(magic):
			magic.finish_stationary_ability_hand(hand_profile.post_reveal_hold_duration)
		var reveal_duration: float = nonlocal_ability_reveal_duration * presentation_policy.duration_scale()
		if reveal_duration > 0.0:
			await get_tree().create_timer(reveal_duration).timeout
		_confirm_ability_windup(context.source, false)
	if hand_profile.command_style == AbilityHandProfile.CommandStyle.DIRECTIONAL:
		var directional_magic := _get_king_magic(context.source)
		if is_instance_valid(directional_magic):
			await directional_magic.command_ability_hand(context.source.coordinate, context.target_coordinate)
	if has_projectile_presentation:
		if not (context.target_piece is KingPiece):
			pending_projectile_defeats[context.target_piece] = target_view
		await _play_targeted_projectile(context, source_view, target_view, profile)
		return
	context.mark_impact()
	context.finish_aftermath()


func _play_targeted_projectile(context, source_view: PieceView, target_view: PieceView, profile: Resource) -> void:
	var sequence_profile: ChessSpecialMovePresentationProfile
	if profile is ChessSpecialMovePresentationProfile:
		sequence_profile = profile
	else:
		# Existing projectile-only assets remain playable while being republished.
		sequence_profile = SpecialMoveProfile.new()
		sequence_profile.cry_duration = 0.0
		sequence_profile.wiggle_blink_count = 0
		sequence_profile.projectile_count = 1
		sequence_profile.projectile_profile = profile
	var director: ChessSpecialMoveDirector = SpecialMoveDirector.new()
	director.name = "ChessSpecialMoveDirector"
	view.add_child(director)
	director.configure(view, source_view, target_view, sequence_profile, presentation_policy.duration_scale(), int(model.position_revision) ^ context_seed(source_view.position, target_view.position))
	await director.play_until_gameplay_impact()
	context.mark_impact()
	await context.wait_for_effect()
	await director.play_aftermath(context.target_defeated, context.target_is_king)
	if context.target_defeated and not context.target_is_king:
		pending_projectile_defeats.erase(context.target_piece)
		if is_instance_valid(target_view):
			view.remove_piece(target_view)
	else:
		pending_projectile_defeats.erase(context.target_piece)
	director.queue_free()
	var magic := _get_king_magic(context.source)
	if is_instance_valid(magic):
		await magic.finish_commanded_ability_hand()
	context.finish_aftermath()


func context_seed(source: Vector2, target: Vector2) -> int:
	return int(source.x * 31.0 + source.y * 131.0 + target.x * 521.0 + target.y * 977.0)


func _on_ability_effect_resolved(piece: KingPiece, ability_name: String, affected_coords: Array) -> void:
	if piece is MinotaurKing and ability_name == MinotaurKing.PASSIVE_ABILITY_NAME:
		view.minotaur_retaliate(affected_coords)


func _on_ability_targeting_started(king: KingPiece, _ability_name: String, _targets: Array) -> void:
	locally_previewed_abilities[king] = king.get_active_ability_id()
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_targeting(true)
	view.clear_highlights()
	view.show_legal_moves(_targets)


func _on_ability_targeting_preparing(king: KingPiece, _ability_name: String, _targets: Array, completion: CompletionGate) -> void:
	if not presentation_policy.should_hold_completion_gate():
		_reveal_ability_windup(king)
		return
	completion.hold()
	var hand_profile := _get_ability_hand_profile(king, king.get_active_ability_id())
	var magic := _get_king_magic(king)
	if is_instance_valid(magic):
		await magic.prepare_ability_hand(hand_profile.pre_reveal_hover_duration)
	_reveal_ability_windup(king)
	if hand_profile.command_style == AbilityHandProfile.CommandStyle.STATIONARY and is_instance_valid(magic):
		magic.finish_stationary_ability_hand(hand_profile.post_reveal_hold_duration)
	completion.release()


func _begin_ability_windup(king: KingPiece, show_target_highlights: bool, targets: Array) -> void:
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_targeting(true)
	if show_target_highlights:
		view.clear_highlights()
		view.show_legal_moves(targets)
	_reveal_ability_windup(king)


func _reveal_ability_windup(king: KingPiece) -> void:
	view.flash_screen()
	var piece_node: Node = get_piece_view(king)
	if king is MinotaurKing and is_instance_valid(piece_node):
		view.spawn_ss_aura(piece_node)
	elif king is NecromancerKing:
		_show_necromancer_aura(king)


func _on_ability_targeting_ended(king: KingPiece, _ability_name: String, reason: String) -> void:
	if reason == "confirmed":
		_confirm_ability_windup(king, true)
		return
	locally_previewed_abilities.erase(king)
	_cancel_ability_windup(king, true, reason == "cancelled")


func _confirm_ability_windup(king: KingPiece, clear_target_highlights: bool) -> void:
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_targeting(false)
	if clear_target_highlights:
		view.clear_highlights()
	var piece_node: Node = get_piece_view(king)
	if king is MinotaurKing and is_instance_valid(piece_node):
		pending_charge_aura_impacts[king] = true
	elif king is NecromancerKing:
		_hide_necromancer_aura(king)


func _cancel_ability_windup(king: KingPiece, clear_target_highlights: bool, play_powerdown_sound: bool) -> void:
	var magic := _get_king_magic(king)
	if is_instance_valid(magic):
		magic.set_targeting(false)
		magic.cancel_ability_hand()
	if clear_target_highlights:
		view.clear_highlights()
	var piece_node: Node = get_piece_view(king)
	if king is MinotaurKing and is_instance_valid(piece_node):
		pending_charge_aura_impacts.erase(king)
		view.fade_out_ss_aura(piece_node, play_powerdown_sound)
	elif king is NecromancerKing:
		_hide_necromancer_aura(king)


func _disperse_pending_charge_aura(king: ModelPiece, piece_node: Node) -> void:
	if not pending_charge_aura_impacts.erase(king):
		return
	if is_instance_valid(piece_node):
		view.fade_out_ss_aura(piece_node, false)


func _on_selection_piece_processing(piece: ModelPiece) -> void:
	selection_effect_piece = piece
	if piece is NecromancerKing:
		_show_necromancer_aura(piece)


func _on_reaction_selection_preparing(calling_piece: ModelPiece, action_type: String, _targets: Array, completion: CompletionGate) -> void:
	if action_type != "raise_dead" or not calling_piece is NecromancerKing:
		return
	if not presentation_policy.should_hold_completion_gate():
		_show_necromancer_aura(calling_piece)
		return
	completion.hold()
	var hand_profile := _get_ability_hand_profile(calling_piece, &"raise_dead")
	var magic := _get_king_magic(calling_piece)
	if is_instance_valid(magic):
		await magic.prepare_ability_hand(hand_profile.pre_reveal_hover_duration)
	_show_necromancer_aura(calling_piece)
	if is_instance_valid(magic):
		await magic.finish_stationary_ability_hand(hand_profile.post_reveal_hold_duration)
	completion.release()


func _on_reaction_selection_committed(calling_piece: ModelPiece, action_type: String, _target: Vector2i) -> void:
	if action_type == "raise_dead" and calling_piece is NecromancerKing:
		_hide_necromancer_aura(calling_piece)


func _on_reaction_queued(calling_piece: ModelPiece, action_type: String, event_data, sequence: int) -> void:
	if action_type == "retaliating_rage" and pending_attack_damage_visuals.has(calling_piece):
		var pending: Array = pending_damage_reactions.get(calling_piece, [])
		pending.append({"action_type": action_type, "event_data": event_data, "sequence": sequence})
		pending_damage_reactions[calling_piece] = pending
		return
	_present_queued_reaction(action_type, event_data, sequence)


func _present_queued_reaction(action_type: String, event_data, sequence: int) -> void:
	_schedule_reaction_sound()
	if action_type == "raise_dead" and event_data is Vector2i:
		_spawn_raise_dead_skull_anchor(event_data, sequence)


func _release_pending_damage_reactions(piece: ModelPiece) -> void:
	var pending: Array = pending_damage_reactions.get(piece, [])
	pending_damage_reactions.erase(piece)
	for reaction in pending:
		_present_queued_reaction(reaction.action_type, reaction.event_data, reaction.sequence)


func _on_reaction_finished(calling_piece: ModelPiece, action_type: String, _event_data, sequence: int, _resolved: bool) -> void:
	if action_type != "raise_dead":
		return
	if calling_piece is NecromancerKing:
		_hide_necromancer_aura(calling_piece)
	var anchor: Node = raise_dead_skull_anchors.get(sequence)
	raise_dead_skull_anchors.erase(sequence)
	if is_instance_valid(anchor):
		anchor.dismiss()


func _finalize_retained_capture_view(piece: ModelPiece, piece_node: Node, keep_corpse: bool) -> void:
	retained_capture_piece_views.erase(piece)
	piece_views.erase(piece)
	necromancer_auras.erase(piece)
	var magic: Node = king_magic_controllers.get(piece)
	king_magic_controllers.erase(piece)
	if not keep_corpse and is_instance_valid(piece_node):
		view.remove_piece(piece_node)
	if not keep_corpse and is_instance_valid(magic):
		_dispose_king_magic(magic)


func _schedule_reaction_sound() -> void:
	if reaction_sound_scheduled:
		return
	reaction_sound_scheduled = true
	_play_coalesced_reaction_sound.call_deferred()


func _play_coalesced_reaction_sound() -> void:
	reaction_sound_scheduled = false
	if reaction_trigger_sound == null:
		return
	reaction_sound_player.stream = reaction_trigger_sound
	reaction_sound_player.volume_db = reaction_trigger_volume_db
	reaction_sound_player.play()


func _spawn_raise_dead_skull_anchor(coordinate: Vector2i, sequence: int) -> void:
	if not model.is_in_bounds(coordinate.x, coordinate.y):
		return
	var anchor := SKULL_BURST_SCENE.instantiate() as GPUParticles2D
	view.add_child(anchor)
	var cell_polygon := view.projection.get_cell_polygon(coordinate)
	var cell_bounds := Rect2(cell_polygon[0], Vector2.ZERO)
	for point in cell_polygon:
		cell_bounds = cell_bounds.expand(point)
	anchor.position = view.cell_to_screen_center(coordinate.x, coordinate.y)
	# A broad inset rectangle reads as the whole square without bleeding over the
	# perspective-slanted edges of the projected cell.
	anchor.configure_emission_footprint(cell_bounds.size * Vector2(0.72, 0.68))
	raise_dead_skull_anchors[sequence] = anchor


func _clear_raise_dead_skull_anchors() -> void:
	for anchor in raise_dead_skull_anchors.values():
		if is_instance_valid(anchor):
			anchor.queue_free()
	raise_dead_skull_anchors.clear()


func _get_ability_hand_profile(king: KingPiece, ability_id: StringName) -> Resource:
	if ability_presentations != null and ability_presentations.has_method("find_hand_profile"):
		return ability_presentations.find_hand_profile(king.get_position_type_id(), ability_id)
	return AbilityHandProfile.new()


func _on_selection_piece_processed() -> void:
	if selection_effect_piece is NecromancerKing:
		_hide_necromancer_aura(selection_effect_piece)
	selection_effect_piece = null


func _on_selection_targets_changed(targets: Array) -> void:
	view.clear_highlights()
	view.highlight_squares(targets)


func _on_selection_cleared() -> void:
	view.clear_highlights()
	for magic in king_magic_controllers.values():
		if is_instance_valid(magic): magic.set_selected(false)


func _on_piece_selected(piece: ModelPiece) -> void:
	for registered_piece in king_magic_controllers:
		var magic: Node = king_magic_controllers[registered_piece]
		if is_instance_valid(magic): magic.set_selected(registered_piece == piece)


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
		if not king.cooldown_scheduled.is_connected(_on_cooldown_scheduled):
			king.cooldown_scheduled.connect(_on_cooldown_scheduled)
		if king.cooldown_reset_pending:
			_on_cooldown_scheduled(king)
		elif king.current_cooldown > 0:
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
	magic.configure(view, view.get_hand_rig_for_color(piece.color), piece_node, king_profile, piece.get_position_type_id(), cooldown_presentation_profile)
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


func _play_unpowered_king_move(piece_node: PieceView, to: Vector2i, arrival_callback: Callable = Callable()) -> void:
	var fallback := KingMagicController.new()
	view.add_child(fallback)
	fallback.configure(view, null, piece_node, null)
	await fallback.play_move(piece_node.coordinate, to, false, arrival_callback)
	fallback.queue_free()


func _on_cooldown_changed(king: KingPiece, new_cooldown: int) -> void:
	view.update_cooldown_display(king, new_cooldown)
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_cooldown(new_cooldown, true)


func _on_cooldown_ready(king: KingPiece) -> void:
	view.ready_cooldown_display(king)
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_cooldown(0, true)


func _on_cooldown_scheduled(king: KingPiece) -> void:
	view.pending_cooldown_display(king)
	var magic := _get_king_magic(king)
	if is_instance_valid(magic): magic.set_cooldown_pending(true)

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
