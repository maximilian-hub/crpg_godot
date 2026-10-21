extends Node
class_name ChessPresentationAdapter

const ArcherKing := preload("res://scripts/pieces/archer_king.gd")

signal king_fatal_impact_presented()
signal archer_volley_projectile_presented(phase: StringName, index: int)
signal archer_volley_knockoff_state_changed(piece: ModelPiece, active: bool)
signal archer_volley_target_presented(target: Vector2i, index: int)
signal archer_volley_fall_state_changed(active: bool)

const KingDeathProfile := preload("res://scripts/view/chess_king_death_profile.gd")
const DEFAULT_KING_DEATH_PROFILE := preload("res://assets/chess_king_death.tres")
const DEFAULT_ABILITY_PRESENTATIONS := preload("res://assets/chess_ability_presentations.tres")
const DEFAULT_COOLDOWN_PRESENTATION := preload("res://assets/chess_king_cooldown_presentation.tres")
const SpecialMoveDirector := preload("res://scripts/view/chess_special_move_director.gd")
const SpecialMoveProfile := preload("res://scripts/view/chess_special_move_presentation_profile.gd")
const AbilityHandProfile := preload("res://scripts/view/chess_ability_hand_profile.gd")
const VOLLEY_MAGIC_SHADER_CODE := "shader_type canvas_item; uniform vec4 magic_tint : source_color = vec4(0.45, 0.85, 1.0, 1.0); void fragment(){ vec4 source = texture(TEXTURE, UV); COLOR = vec4(source.rgb * magic_tint.rgb * 1.35, source.a * magic_tint.a) * COLOR; }"

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
@export_range(0.1, 4.0, 0.05) var wraith_move_duration := 1.35
@export_range(0.0, 48.0, 1.0) var wraith_float_height := 12.0
@export_range(0.0, 32.0, 1.0) var wraith_sway_distance := 7.0
@export_range(1.0, 8.0, 0.1) var wraith_idle_cycle_duration := 3.6
@export_range(0.0, 24.0, 0.5) var wraith_idle_float_height := 9.0
@export_range(0.0, 16.0, 0.5) var wraith_idle_sway_distance := 2.5

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
var playable_turn_colors: Dictionary = {}
var tile_effect_views: Dictionary = {}
var autonomous_entity_views: Dictionary = {}
var wraith_replacement_preview_sprite: Sprite2D
var wraith_replacement_preview_tween: Tween
var archer_targeting_visuals: Dictionary = {}
var archer_draw_button: Button
var _volley_magic_material: ShaderMaterial


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
	model.archer_attack_committed.connect(_on_archer_attack_committed)
	model.piece_promotion_committed.connect(_on_piece_promotion_committed)
	model.piece_destroyed.connect(_on_piece_destroyed)
	model.piece_transformed.connect(_on_piece_transformed)
	model.piece_damaged.connect(_on_piece_damaged)
	model.piece_stunned.connect(_on_piece_stunned)
	model.piece_recovered.connect(_on_piece_recovered)
	model.ability_started.connect(_on_ability_started)
	model.targeted_ability_committed.connect(_on_targeted_ability_committed)
	model.archer_volley_committed.connect(_on_archer_volley_committed)
	model.archer_state_changed.connect(_on_archer_state_changed)
	model.archer_arrow_collected.connect(_on_archer_arrow_collected)
	model.reaction_selection_preparing.connect(_on_reaction_selection_preparing)
	model.reaction_selection_committed.connect(_on_reaction_selection_committed)
	model.reaction_queued.connect(_on_reaction_queued)
	model.reaction_finished.connect(_on_reaction_finished)
	model.ability_effect_resolved.connect(_on_ability_effect_resolved)
	model.battle_finished.connect(_on_battle_finished)
	model.tile_effect_added.connect(_on_tile_effect_added)
	model.tile_effect_removed.connect(_on_tile_effect_removed)
	model.autonomous_entity_added.connect(_on_autonomous_entity_added)
	model.autonomous_entity_moved.connect(_on_autonomous_entity_moved)
	model.autonomous_entity_removed.connect(_on_autonomous_entity_removed)
	model.arc_mortar_impact.connect(_on_arc_mortar_impact)
	model.settled_action_completed.connect(_on_archer_board_state_settled)
	controller.ability_targeting_started.connect(_on_ability_targeting_started)
	controller.ability_targeting_preparing.connect(_on_ability_targeting_preparing)
	controller.ability_targeting_ended.connect(_on_ability_targeting_ended)
	controller.ability_footprint_preview_changed.connect(_on_ability_footprint_preview_changed)
	controller.selection_piece_processing.connect(_on_selection_piece_processing)
	controller.selection_piece_processed.connect(_on_selection_piece_processed)
	controller.selection_targets_changed.connect(_on_selection_targets_changed)
	controller.selection_cleared.connect(_on_selection_cleared)
	controller.piece_selected.connect(_on_piece_selected)
	controller.ordinary_move_submission_started.connect(_on_ordinary_move_submission_started)
	controller.ordinary_move_submission_finished.connect(_on_ordinary_move_submission_finished)
	controller.contextual_archer_draw_changed.connect(_on_contextual_archer_draw_changed)
	view.square_selected.connect(controller._on_square_clicked)
	view.square_touch_selected.connect(controller._on_touch_square_clicked)
	view.editor_square_entered.connect(_on_board_square_entered)

	if not model.board.is_empty():
		_on_board_initialized(model.board)
	_create_archer_draw_button()


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


func present_playable_turn(color: String) -> void:
	playable_turn_colors[color] = true
	var magic := get_king_magic_controller(color)
	if is_instance_valid(magic):
		magic.release_initial_cooldown_motes()


func _on_board_initialized(board: Array) -> void:
	_clear_all_archer_targeting()
	piece_views = view.draw_board(board)
	for row in board:
		for piece in row:
			if piece != null:
					_register_piece(piece, view.get_piece_node(piece.coordinate))
					if piece is ArcherKing:
						(piece_views[piece] as PieceView).refresh_status_icons()
	_rebuild_nonphysical_views()

func _on_board_rebuilt(board: Array) -> void:
	_clear_all_archer_targeting()
	if is_instance_valid(archer_draw_button): archer_draw_button.visible = false
	_clear_nonphysical_views()
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
		result_view.reset_result()
	_rebuild_nonphysical_views()

func _clear_nonphysical_views() -> void:
	for node in tile_effect_views.values():
		if is_instance_valid(node): node.queue_free()
	for node in autonomous_entity_views.values():
		if is_instance_valid(node): node.queue_free()
	tile_effect_views.clear(); autonomous_entity_views.clear()

func _rebuild_nonphysical_views() -> void:
	for effect in model.tile_effects: _on_tile_effect_added(effect)
	for entity in model.autonomous_entities: _create_autonomous_entity_view(entity)

func _on_tile_effect_added(effect: ChessTileEffectState) -> void:
	if tile_effect_views.has(effect.effect_id): return
	if effect.type_id == &"archer_arrow":
		var arrow := AnimatedSprite2D.new()
		arrow.name = "ArcherArrow_%s" % effect.effect_id
		var spike_profile := ability_presentations.find_profile(&"arakne_king", &"spike_burst") as ChessSpecialMovePresentationProfile
		var projectile_profile := spike_profile.resolved_projectile_profile() if spike_profile != null else null
		if projectile_profile != null:
			arrow.sprite_frames = projectile_profile.projectile_frames
			arrow.animation = projectile_profile.projectile_animation
			arrow.scale = Vector2.ONE * projectile_profile.projectile_scale * view.get_world_scale()
			arrow.rotation = deg_to_rad(projectile_profile.rotation_offset_degrees) - 0.55
			arrow.pause()
		var polygon := view.projection.get_cell_polygon(effect.coordinate)
		var bottom_right := polygon[0]
		for point in polygon:
			if point.x + point.y > bottom_right.x + bottom_right.y: bottom_right = point
		var center := view.cell_to_screen_center(effect.coordinate.x, effect.coordinate.y)
		arrow.position = center.lerp(bottom_right, 0.62)
		arrow.z_index = view.get_piece_depth(effect.coordinate) - 1
		view.add_child(arrow)
		tile_effect_views[effect.effect_id] = arrow
		return
	if effect.type_id != &"cursed_mark": return
	var mark := Node2D.new()
	mark.name = "CursedMark_%s" % effect.effect_id
	var center := view.cell_to_screen_center(effect.coordinate.x, effect.coordinate.y)
	var cell_polygon := view.projection.get_cell_polygon(effect.coordinate)
	var inset_polygon := PackedVector2Array()
	for point in cell_polygon:
		inset_polygon.append(center + (point - center) * 0.82)
	var stain := Polygon2D.new()
	stain.name = "Stain"
	stain.polygon = inset_polygon
	stain.color = Color(0.34, 0.02, 0.52, 0.48)
	mark.add_child(stain)
	var outline := Line2D.new()
	outline.name = "Outline"
	outline.points = PackedVector2Array([inset_polygon[0], inset_polygon[1], inset_polygon[2], inset_polygon[3], inset_polygon[0]])
	outline.width = 2.0
	outline.default_color = Color(0.86, 0.32, 1.0, 0.92)
	outline.antialiased = true
	mark.add_child(outline)
	var rune := Line2D.new()
	rune.name = "Rune"
	var rune_x := (cell_polygon[1].x - cell_polygon[3].x) * 0.14
	var rune_y := (cell_polygon[2].y - cell_polygon[0].y) * 0.22
	rune.points = PackedVector2Array([
		center + Vector2(-rune_x, -rune_y), center + Vector2(rune_x, rune_y),
		center, center + Vector2(rune_x, -rune_y), center + Vector2(-rune_x, rune_y),
	])
	rune.width = 2.5
	rune.default_color = Color(0.95, 0.72, 1.0, 0.95)
	rune.antialiased = true
	mark.add_child(rune)
	mark.z_index = view.get_piece_depth(effect.coordinate) - 1
	view.add_child(mark); tile_effect_views[effect.effect_id] = mark

func _on_tile_effect_removed(effect: ChessTileEffectState) -> void:
	var node: Node = tile_effect_views.get(effect.effect_id)
	tile_effect_views.erase(effect.effect_id)
	if is_instance_valid(node): node.queue_free()

func _create_autonomous_entity_view(entity: ChessAutonomousEntityState) -> Node2D:
	if autonomous_entity_views.has(entity.entity_id): return autonomous_entity_views[entity.entity_id]
	if entity.type_id == &"arc_mortar":
		var marker := Node2D.new()
		marker.name = "ArcMortar_%s" % entity.entity_id
		for coord in model.get_mortar_area(entity.coordinate):
			var cell := Polygon2D.new()
			cell.polygon = view.projection.get_cell_polygon(coord)
			cell.color = Color(0.95, 0.22, 0.08, 0.28)
			marker.add_child(cell)
		var outline := Line2D.new()
		var area := model.get_mortar_area(entity.coordinate)
		var a := view.projection.get_cell_polygon(area[0])
		var b := view.projection.get_cell_polygon(area[3])
		outline.points = PackedVector2Array([a[0], a[1], b[1], b[2], b[3], a[3], a[0]])
		outline.width = 3.0
		outline.default_color = Color(1.0, 0.42, 0.12, 0.9)
		marker.add_child(outline)
		marker.z_index = ChessBoardView.BOARD_EFFECT_Z - 1
		view.add_child(marker)
		autonomous_entity_views[entity.entity_id] = marker
		return marker
	var sprite := Sprite2D.new()
	sprite.name = "Wraith_%s" % entity.entity_id
	sprite.texture = load("res://assets/pieces/kings/%s_wraith.png" % entity.owner_color)
	if sprite.texture != null:
		sprite.scale = Vector2.ONE * (64.0 / float(sprite.texture.get_height())) * view.get_world_scale()
		# The autonomous entity's position is a ground contact point, just like a
		# PieceView origin. Offset centered artwork upward so its base rests there.
		sprite.offset = Vector2(0.0, -float(sprite.texture.get_height()) * 0.5)
	sprite.modulate.a = 0.5
	sprite.position = view.grid_to_screen(entity.coordinate.x, entity.coordinate.y)
	sprite.z_index = view.get_piece_depth(entity.coordinate) + 1
	view.add_child(sprite)
	_start_wraith_idle_float(sprite)
	autonomous_entity_views[entity.entity_id] = sprite
	return sprite

func _start_wraith_idle_float(sprite: Sprite2D) -> void:
	if sprite == null or sprite.has_meta(&"wraith_idle_float"):
		return
	sprite.set_meta(&"wraith_idle_float", true)
	var resting_offset := sprite.offset
	sprite.set_meta(&"wraith_resting_offset", resting_offset)
	var idle_tween := sprite.create_tween().set_loops()
	idle_tween.tween_method(
		func(progress: float):
			if not is_instance_valid(sprite):
				return
			var angle := TAU * progress
			sprite.offset = resting_offset + Vector2(
				sin(angle) * wraith_idle_sway_distance,
				-(0.5 - 0.5 * cos(angle)) * wraith_idle_float_height
			),
		0.0,
		1.0,
		wraith_idle_cycle_duration
	).set_trans(Tween.TRANS_LINEAR)

func _on_autonomous_entity_added(entity: ChessAutonomousEntityState, completion: CompletionGate) -> void:
	_create_autonomous_entity_view(entity)
	# Creation is immediate; the gate remains available for future authored summon animation.

func _on_autonomous_entity_moved(entity: ChessAutonomousEntityState, _from: Vector2i, to: Vector2i, completion: CompletionGate) -> void:
	var sprite := _create_autonomous_entity_view(entity) as Sprite2D
	if sprite == null:
		return
	var destination := view.grid_to_screen(to.x, to.y)
	if not presentation_policy.should_hold_completion_gate():
		sprite.position = destination
		sprite.z_index = view.get_piece_depth(to) + 1
		return
	completion.hold()
	var origin := sprite.position
	var original_scale := sprite.scale
	var original_alpha := sprite.modulate.a
	var original_rotation := sprite.rotation
	var motion_scale := view.get_world_scale()
	var tween := create_tween()
	tween.tween_method(
		func(progress: float):
			if not is_instance_valid(sprite):
				return
			sprite.position = wraith_float_position(
				origin,
				destination,
				progress,
				wraith_float_height * motion_scale,
				wraith_sway_distance * motion_scale
			)
			var spectral_pulse := sin(PI * progress)
			sprite.scale = original_scale * (1.0 + spectral_pulse * 0.06)
			sprite.modulate.a = original_alpha * (1.0 - spectral_pulse * 0.18)
			sprite.rotation = original_rotation + sin(TAU * progress) * 0.035,
		0.0,
		1.0,
		wraith_move_duration * presentation_policy.duration_scale()
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if not is_instance_valid(sprite):
		completion.release()
		return
	sprite.position = destination
	sprite.scale = original_scale
	sprite.modulate.a = original_alpha
	sprite.rotation = original_rotation
	sprite.z_index = view.get_piece_depth(to) + 1
	completion.release()

static func wraith_float_position(from: Vector2, to: Vector2, progress: float, float_height: float, sway_distance: float) -> Vector2:
	var t := clampf(progress, 0.0, 1.0)
	var travel := to - from
	var perpendicular := Vector2(-travel.y, travel.x).normalized() if not travel.is_zero_approx() else Vector2.RIGHT
	var envelope := sin(PI * t)
	var vertical_bob := sin(TAU * 2.0 * t) * float_height * 0.20
	return from.lerp(to, t) + perpendicular * envelope * sway_distance + Vector2.UP * (envelope * float_height + vertical_bob)

func _on_autonomous_entity_removed(entity: ChessAutonomousEntityState, _reason: StringName, completion: CompletionGate) -> void:
	var sprite: Node = autonomous_entity_views.get(entity.entity_id)
	autonomous_entity_views.erase(entity.entity_id)
	if sprite == wraith_replacement_preview_sprite:
		_clear_wraith_replacement_preview()
	if is_instance_valid(sprite): sprite.queue_free()

func _on_arc_mortar_impact(_entity: ChessAutonomousEntityState, affected_coords: Array, completion: CompletionGate) -> void:
	if affected_coords.is_empty() or not presentation_policy.should_hold_completion_gate():
		return
	completion.hold()
	var center := Vector2.ZERO
	for coord in affected_coords:
		center += view.cell_to_screen_center(coord.x, coord.y)
	center /= affected_coords.size()
	var ball := Polygon2D.new()
	ball.name = "ArcMortarBall"
	ball.polygon = PackedVector2Array([
		Vector2(-10, -8), Vector2(-4, -13), Vector2(5, -12), Vector2(11, -5),
		Vector2(12, 5), Vector2(5, 12), Vector2(-5, 12), Vector2(-12, 5)
	])
	ball.color = Color(0.08, 0.07, 0.06, 1.0)
	ball.position = Vector2(center.x, -32.0)
	ball.z_index = ChessBoardView.BOARD_EFFECT_Z + 5
	view.add_child(ball)
	var tween := create_tween()
	tween.tween_property(ball, "position", center, 0.48 * view.animation_duration_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	view.play_default_capture_clack_sound()
	ball.queue_free()
	completion.release()


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
	_refresh_all_archer_statuses()
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
	if presentation.self_propelled:
		await view.move_piece_node(piece_node, to)
		report_arrival.call()
		presentation.finish_aftermath()
		return
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
	if presentation.self_propelled:
		await view.capture_piece_node_self_propelled(
			attacker_node, defender_node, to,
			func(): presentation.mark_arrived(attacker),
			func(): presentation.mark_impact()
		)
		_finalize_retained_capture_view(defender, defender_node, false)
		presentation.finish_aftermath()
		return
	if defender is KingPiece and is_instance_valid(defender_node):
		var is_charge_impact := is_committed_charge
		var defender_magic := _get_king_magic(defender)
		var death_profile: Resource = king_death_profile if king_death_profile != null else KingDeathProfile.new()
		var death_effect := view.create_king_death_effect(defender_node, death_profile, screen_shake)
		if is_instance_valid(defender_magic):
			death_effect.death_beat_reached.connect(defender_magic.disable_effects, CONNECT_ONE_SHOT)
		var death_contact := func():
			# Lethal captures bypass ModelPiece.take_damage(), so reproduce the
			# ordinary hit feedback explicitly at physical contact, including an
			# HP display of zero. The splatter scene owns the universal hurt sound
			# as well as the blood animation.
			_present_piece_damage(defender, 0)
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


func _on_archer_attack_committed(attacker: ArcherKing, defender: ModelPiece, _from: Vector2i, _to: Vector2i, presentation) -> void:
	var attacker_view := get_piece_view(attacker) as PieceView
	var defender_view := get_piece_view(defender) as PieceView
	var spike_profile := ability_presentations.find_profile(&"arakne_king", &"spike_burst") as ChessSpecialMovePresentationProfile
	if not presentation_policy.should_hold_completion_gate() or not is_instance_valid(attacker_view) or not is_instance_valid(defender_view) or spike_profile == null:
		return
	presentation.claim()
	var lethal := defender.current_hp <= 1
	if lethal and not defender is KingPiece:
		pending_projectile_defeats[defender] = defender_view
	pending_attack_damage_visuals[defender] = []
	var projectile_profile := spike_profile.resolved_projectile_profile().duplicate(true) as ChessProjectilePresentationProfile
	var projectile := ChessProjectileEffect.new()
	projectile.name = "ArcherSharpshooterArrow"
	view.add_child(projectile)
	projectile.configure(projectile_profile, view.get_world_scale())
	var start := attacker_view.get_anchor_position_in(view, attacker_view.get_body_anchor())
	var finish := defender_view.get_anchor_position_in(view, defender_view.get_body_anchor())
	var lift := Vector2(0.0, -maxf(48.0, start.distance_to(finish) * 0.3))
	await projectile.fly_arc(start, finish, lift, presentation_policy.duration_scale())
	projectile.play_impact(view, finish, presentation_policy.duration_scale(), true)
	presentation.mark_impact()
	await get_tree().process_frame
	_flush_pending_attack_damage(defender)
	pending_attack_damage_visuals.erase(defender)
	var knockoff_completion: CompletionGate = null
	if lethal and not defender is KingPiece and is_instance_valid(defender_view):
		knockoff_completion = CompletionGate.new()
		knockoff_completion.hold()
		knockoff_completion.close()
		_play_archer_volley_knockoff(defender, defender_view, attacker_view, projectile_profile, 0, knockoff_completion)
	await projectile.wait_for_impact()
	projectile.queue_free()
	if knockoff_completion != null:
		await knockoff_completion.wait_until_released()
		pending_projectile_defeats.erase(defender)
		if is_instance_valid(defender_view): view.remove_piece(defender_view)
	presentation.finish_aftermath()


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


func _on_battle_finished(_winner_color: String) -> void:
	_clear_raise_dead_skull_anchors()
	for effect in active_king_deaths:
		if is_instance_valid(effect) and not effect.result_ready:
			await effect.result_ready_for_display
	active_king_deaths.clear()


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
	if piece is KingPiece and current_hp <= 0:
		king_fatal_impact_presented.emit()
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


func _on_archer_volley_committed(king: ArcherKing, targets: Array[Vector2i], completion: CompletionGate) -> void:
	if not presentation_policy.should_hold_completion_gate():
		return
	var source_view := get_piece_view(king) as PieceView
	var spike_profile := ability_presentations.find_profile(&"arakne_king", &"spike_burst") as ChessSpecialMovePresentationProfile
	if not is_instance_valid(source_view) or spike_profile == null:
		return
	completion.hold()
	var projectile_profile := spike_profile.resolved_projectile_profile().duplicate(true) as ChessProjectilePresentationProfile
	projectile_profile.travel_speed = maxf(projectile_profile.travel_speed, 1400.0)
	var world_scale := view.get_world_scale()
	var launch_origin := source_view.get_anchor_position_in(view, source_view.get_body_anchor())
	var presented_targets: Array[Vector2i] = targets.duplicate()
	presented_targets.sort_custom(func(a: Vector2i, b: Vector2i):
		var a_position := view.grid_to_screen(a.x, a.y)
		var b_position := view.grid_to_screen(b.x, b.y)
		return a_position.x < b_position.x if not is_equal_approx(a_position.x, b_position.x) else a_position.y < b_position.y
	)
	var launch_projectiles: Array[ChessProjectileEffect] = []
	for index in range(presented_targets.size()):
		var projectile := ChessProjectileEffect.new()
		projectile.name = "ArcherVolleyLaunch"
		view.add_child(projectile)
		archer_volley_projectile_presented.emit(&"launch", index)
		projectile.configure(projectile_profile, world_scale)
		projectile.projectile_material_override = _make_volley_magic_material()
		launch_projectiles.append(projectile)
		var spread := (float(index) - float(presented_targets.size() - 1) * 0.5) * 18.0 * world_scale
		projectile.fly(launch_origin, Vector2(launch_origin.x + spread, -80.0), presentation_policy.duration_scale())
	await get_tree().create_timer(0.28 * presentation_policy.duration_scale()).timeout
	for projectile in launch_projectiles:
		if is_instance_valid(projectile): projectile.queue_free()
	await get_tree().create_timer(0.18 * presentation_policy.duration_scale()).timeout
	var fall_completions: Array[CompletionGate] = []
	for index in range(presented_targets.size()):
		var target := presented_targets[index]
		archer_volley_target_presented.emit(target, index)
		var fall_completion := CompletionGate.new()
		fall_completion.hold()
		fall_completion.close()
		fall_completions.append(fall_completion)
		_play_archer_volley_fall(target, index, source_view, projectile_profile, fall_completion)
		if index < presented_targets.size() - 1:
			await get_tree().create_timer(0.055 * presentation_policy.duration_scale()).timeout
	for fall_completion in fall_completions:
		await fall_completion.wait_until_released()
	completion.release()


func _play_archer_volley_fall(target: Vector2i, index: int, source_view: PieceView, projectile_profile: ChessProjectilePresentationProfile, completion: CompletionGate) -> void:
	var finish := view.grid_to_screen(target.x, target.y)
	var falling := ChessProjectileEffect.new()
	falling.name = "ArcherVolleyArrow"
	view.add_child(falling)
	archer_volley_projectile_presented.emit(&"fall", index)
	archer_volley_fall_state_changed.emit(true)
	falling.configure(projectile_profile, view.get_world_scale())
	falling.projectile_material_override = _make_volley_magic_material()
	await falling.fly(Vector2(finish.x, -70.0), finish, presentation_policy.duration_scale())
	falling.play_impact(view, finish, presentation_policy.duration_scale(), true)
	var occupant: ModelPiece = model.board[target.x][target.y]
	var occupant_view := get_piece_view(occupant) as PieceView
	var knockoff_completion: CompletionGate = null
	if occupant != null and occupant.current_hp <= 1 and not occupant is KingPiece and is_instance_valid(occupant_view):
		silently_removed_piece_views[occupant] = true
		knockoff_completion = CompletionGate.new()
		knockoff_completion.hold()
		knockoff_completion.close()
		_play_archer_volley_knockoff(occupant, occupant_view, source_view, projectile_profile, index, knockoff_completion)
	await falling.wait_for_impact()
	falling.queue_free()
	archer_volley_fall_state_changed.emit(false)
	if knockoff_completion != null:
		await knockoff_completion.wait_until_released()
	completion.release()

func _make_volley_magic_material() -> ShaderMaterial:
	if _volley_magic_material != null:
		return _volley_magic_material
	var shader := Shader.new()
	shader.code = VOLLEY_MAGIC_SHADER_CODE
	_volley_magic_material = ShaderMaterial.new()
	_volley_magic_material.shader = shader
	return _volley_magic_material


func _play_archer_volley_knockoff(piece: ModelPiece, piece_view: PieceView, source_view: PieceView, projectile_profile: ChessProjectilePresentationProfile, index: int, completion: CompletionGate) -> void:
	if not is_instance_valid(piece_view):
		completion.release()
		return
	archer_volley_knockoff_state_changed.emit(piece, true)
	var world_scale := view.get_world_scale()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(model.position_revision) * 7919 + index * 104729 + 17
	var trajectory := ChessKingMagicController.build_ballistic_knockoff(
		source_view.position, piece_view.position, piece_view.position, view.get_viewport_rect().size,
		ChessKingMagicController.piece_visual_radius(piece_view), projectile_profile.knockoff_horizontal_speed * world_scale,
		projectile_profile.knockoff_upward_speed * world_scale, projectile_profile.knockoff_gravity * world_scale, rng)
	var origin := piece_view.position
	var rotation_start := piece_view.rotation
	var side: int = trajectory.side
	piece_view.z_index = ChessBoardView.BOARD_EFFECT_Z + 1
	var knockoff := create_tween()
	knockoff.tween_method(func(time: float):
		if not is_instance_valid(piece_view): return
		piece_view.position = ChessKingMagicController.ballistic_position(origin, trajectory.initial_velocity, trajectory.gravity, time).round()
		piece_view.rotation = rotation_start + deg_to_rad(projectile_profile.knockoff_angular_speed * side) * time
	, 0.0, trajectory.duration, trajectory.duration * presentation_policy.duration_scale())
	await knockoff.finished
	archer_volley_knockoff_state_changed.emit(piece, false)
	completion.release()


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
	view.clear_area_preview()
	if king is WraithKing:
		_show_wraith_replacement_preview(king as WraithKing)

func _show_wraith_replacement_preview(king: WraithKing) -> void:
	_clear_wraith_replacement_preview()
	var replacement := model.get_wraith_replacement_candidate(king.piece_id)
	if replacement == null:
		return
	wraith_replacement_preview_sprite = autonomous_entity_views.get(replacement.entity_id) as Sprite2D
	if not is_instance_valid(wraith_replacement_preview_sprite):
		wraith_replacement_preview_sprite = null
		return
	wraith_replacement_preview_tween = wraith_replacement_preview_sprite.create_tween().set_loops()
	wraith_replacement_preview_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wraith_replacement_preview_tween.tween_property(wraith_replacement_preview_sprite, "self_modulate", Color(1.0, 0.12, 0.12, 1.0), 0.42)
	wraith_replacement_preview_tween.tween_property(wraith_replacement_preview_sprite, "self_modulate", Color.WHITE, 0.42)

func _clear_wraith_replacement_preview() -> void:
	if wraith_replacement_preview_tween != null and wraith_replacement_preview_tween.is_valid():
		wraith_replacement_preview_tween.kill()
	wraith_replacement_preview_tween = null
	if is_instance_valid(wraith_replacement_preview_sprite):
		wraith_replacement_preview_sprite.self_modulate = Color.WHITE
	wraith_replacement_preview_sprite = null

func _on_board_square_entered(coord: Vector2i) -> void:
	if not controller.active_ability_selected or not controller.active_king is CannonKing:
		return
	if coord not in controller.legal_moves:
		view.clear_area_preview()
		return
	view.preview_area(model.get_mortar_area(coord))

func _on_ability_footprint_preview_changed(area: Array) -> void:
	if area.is_empty():
		view.clear_area_preview()
	else:
		view.preview_area(area)


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
	view.clear_area_preview()
	if king is WraithKing:
		_clear_wraith_replacement_preview()
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
	view.clear_area_preview()
	for magic in king_magic_controllers.values():
		if is_instance_valid(magic): magic.set_selected(false)


func _on_piece_selected(piece: ModelPiece) -> void:
	for registered_piece in king_magic_controllers:
		var magic: Node = king_magic_controllers[registered_piece]
		if is_instance_valid(magic): magic.set_selected(registered_piece == piece)

func _create_archer_draw_button() -> void:
	archer_draw_button = Button.new()
	archer_draw_button.name = "ArcherDrawButton"
	archer_draw_button.text = "Draw"
	archer_draw_button.visible = false
	archer_draw_button.z_index = 200
	archer_draw_button.custom_minimum_size = Vector2(280.0, 88.0)
	archer_draw_button.add_theme_font_size_override("font_size", 34)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.07, 0.055, 0.10, 0.95)
	normal_style.border_color = Color(0.66, 0.52, 0.24, 0.95)
	normal_style.set_border_width_all(3)
	normal_style.set_corner_radius_all(21)
	normal_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	normal_style.shadow_size = 15
	archer_draw_button.add_theme_stylebox_override("normal", normal_style)
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.16, 0.12, 0.20, 0.98)
	hover_style.border_color = Color(1.0, 0.80, 0.32, 1.0)
	archer_draw_button.add_theme_stylebox_override("hover", hover_style)
	archer_draw_button.add_theme_stylebox_override("pressed", hover_style)
	archer_draw_button.pressed.connect(controller.submit_selected_archer_charge)
	var screen_ui := get_node_or_null("../LunacyLayer/LunacyUI") as Control
	if screen_ui != null:
		screen_ui.add_child(archer_draw_button)
		archer_draw_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		archer_draw_button.offset_left = -140.0
		archer_draw_button.offset_top = -158.0
		archer_draw_button.offset_right = 140.0
		archer_draw_button.offset_bottom = -70.0
	else:
		view.add_child(archer_draw_button)

func _on_contextual_archer_draw_changed(_archer: ArcherKing, visible: bool) -> void:
	if archer_draw_button == null:
		return
	archer_draw_button.visible = visible

func _on_archer_state_changed(king: ArcherKing, _state: StringName, message: String) -> void:
	var piece_view := get_piece_view(king) as PieceView
	if is_instance_valid(piece_view):
		piece_view.refresh_status_icons()
	_clear_archer_targeting(king)
	if king.draw_target != Vector2i(-1, -1) and is_instance_valid(piece_view):
		_show_archer_targeting(king, piece_view)
	if not message.is_empty() and is_instance_valid(piece_view):
		_show_archer_float_text(piece_view, message)
	_refresh_all_archer_statuses()

func _on_archer_board_state_settled() -> void:
	_refresh_all_archer_statuses()
	for piece in piece_views:
		if piece is ArcherKing:
			var archer := piece as ArcherKing
			if archer.draw_target != Vector2i(-1, -1) and not archer_targeting_visuals.has(archer):
				var piece_view := get_piece_view(archer) as PieceView
				if is_instance_valid(piece_view): _show_archer_targeting(archer, piece_view)

func _on_archer_arrow_collected(piece: ModelPiece, _king: ArcherKing) -> void:
	var piece_view := get_piece_view(piece) as PieceView
	if is_instance_valid(piece_view):
		_show_archer_float_text(piece_view, "Arrow Picked Up")

func _show_archer_float_text(piece_view: PieceView, message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.position = piece_view.position + piece_view.get_head_anchor().position - Vector2(90, 20)
	label.size = Vector2(180, 30)
	label.z_index = 250
	view.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)

func _show_archer_targeting(king: ArcherKing, piece_view: PieceView) -> void:
	var root := Node2D.new()
	root.name = "ArcherTargeting"
	root.z_index = 90
	var start := piece_view.position + piece_view.get_body_anchor().position
	var finish := view.cell_to_screen_center(king.draw_target.x, king.draw_target.y)
	var arc_height := maxf(45.0, start.distance_to(finish) * 0.3)
	for index in range(0, 16, 2):
		var dash := Line2D.new()
		dash.width = 2.0
		dash.default_color = Color(1.0, 0.12, 0.12, 0.9)
		var first_t := float(index) / 16.0
		var second_t := float(index + 1) / 16.0
		dash.points = PackedVector2Array([
			start.lerp(finish, first_t) + Vector2(0, -sin(first_t * PI) * arc_height),
			start.lerp(finish, second_t) + Vector2(0, -sin(second_t * PI) * arc_height),
		])
		root.add_child(dash)
	var reticle := Line2D.new()
	var radius := 18.0
	var ring := PackedVector2Array()
	for index in 17: ring.append(finish + Vector2.RIGHT.rotated(TAU * index / 16.0) * radius)
	reticle.points = ring
	reticle.width = 2.0
	reticle.default_color = Color(1.0, 0.15, 0.15, 0.95)
	root.add_child(reticle)
	view.add_child(root)
	archer_targeting_visuals[king] = root

func _clear_archer_targeting(king: ArcherKing) -> void:
	var node: Node = archer_targeting_visuals.get(king)
	archer_targeting_visuals.erase(king)
	if is_instance_valid(node): node.queue_free()

func _clear_all_archer_targeting() -> void:
	for node in archer_targeting_visuals.values():
		if is_instance_valid(node): node.queue_free()
	archer_targeting_visuals.clear()

func _refresh_all_archer_statuses() -> void:
	for piece in piece_views:
		if piece is ArcherKing:
			var piece_view := piece_views[piece] as PieceView
			if is_instance_valid(piece_view): piece_view.refresh_status_icons()


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
		if not king.active_availability_changed.is_connected(_on_active_availability_changed):
			king.active_availability_changed.connect(_on_active_availability_changed)
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
	if playable_turn_colors.has(piece.color):
		magic.release_initial_cooldown_motes()


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

func _on_active_availability_changed(king: KingPiece, available: bool, reason: String) -> void:
	view.update_active_availability_display(king, available, reason)

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
