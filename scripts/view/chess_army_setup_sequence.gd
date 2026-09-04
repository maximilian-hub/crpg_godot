extends Node
class_name ChessArmySetupSequence

const PresentationTransform = preload("res://scripts/view/chess_presentation_transform.gd")

signal cue_started(cue: ChessSetupCue)
signal piece_placed(cue: ChessSetupCue, piece: Node2D)
signal setup_completed()
signal elapsed_changed(seconds: float)

var profile: ChessArmySetupProfile
var board_view: ChessBoardView
var left_hand: ChessHandRig
var right_hand: ChessHandRig
var piece_views: Dictionary = {}
var running := false
var paused := false
var playback_speed := 1.0
var elapsed := 0.0
var _generation := 0
var _finished_tracks := 0
var seat := ChessHandRig.Seat.NEAR
var opening_seed := 1
var resolved_tracks: Dictionary = {}
var _king_barrier_cue: ChessSetupCue


func configure(setup_profile: ChessArmySetupProfile, view: ChessBoardView, left: ChessHandRig, right: ChessHandRig, views: Dictionary, target_seat := ChessHandRig.Seat.NEAR, seed := 1) -> void:
	profile = setup_profile
	board_view = view
	left_hand = left
	right_hand = right
	piece_views = views
	seat = target_seat
	opening_seed = seed
	restart(false)


func play() -> void:
	if running and paused:
		resume()
		return
	if running:
		return
	_generation += 1
	running = true
	paused = false
	_finished_tracks = 0
	_resolve_tracks()
	var token := _generation
	_run_track(ChessSetupCue.HandSide.LEFT, token)
	_run_track(ChessSetupCue.HandSide.RIGHT, token)


func pause() -> void:
	if not running:
		return
	paused = true
	left_hand.set_setup_paused(true)
	right_hand.set_setup_paused(true)


func resume() -> void:
	if not running:
		return
	paused = false
	left_hand.set_setup_paused(false)
	right_hand.set_setup_paused(false)


func set_playback_speed(value: float) -> void:
	playback_speed = maxf(value, 0.01)
	left_hand.animation_duration_scale = 1.0 / playback_speed
	right_hand.animation_duration_scale = 1.0 / playback_speed


func restart(autoplay := false) -> void:
	_generation += 1
	running = false
	paused = false
	elapsed = 0.0
	_finished_tracks = 0
	left_hand.cancel_setup_placement()
	right_hand.cancel_setup_placement()
	for piece in piece_views.values():
		if is_instance_valid(piece):
			piece.visible = false
	elapsed_changed.emit(elapsed)
	if autoplay:
		play()


func _process(delta: float) -> void:
	if running and not paused:
		elapsed += delta * playback_speed
		elapsed_changed.emit(elapsed)


func _run_track(side: int, token: int) -> void:
	for cue in resolved_tracks.get(side, []):
		if not await _wait_interruptible(cue.gap_before, token):
			return
		var board_size := Vector2i(board_view.projection.rows, board_view.projection.columns)
		var display_coordinate := PresentationTransform.authored_display_coordinate(cue.display_coordinate, seat, board_size)
		var model_coordinate := board_view.projection.get_model_coordinate(display_coordinate)
		var piece: Node2D = piece_views.get(model_coordinate)
		if not is_instance_valid(piece):
			continue
		cue_started.emit(cue)
		var hand := left_hand if side == ChessSetupCue.HandSide.LEFT else right_hand
		await hand.play_setup_placement(
			piece,
			board_view.grid_to_screen(model_coordinate.x, model_coordinate.y),
			board_view.get_world_scale(),
			profile.motion_for(cue),
			board_view.get_piece_depth(model_coordinate)
		)
		if token != _generation:
			return
		piece_placed.emit(cue, piece)
	_finished_tracks += 1
	if _finished_tracks == 2 and token == _generation:
		if _king_barrier_cue != null:
			var king_cue := _king_barrier_cue
			_king_barrier_cue = null
			await _run_single_cue(king_cue, token)
		if token == _generation:
			running = false
			setup_completed.emit()


func _resolve_tracks() -> void:
	resolved_tracks = {
		ChessSetupCue.HandSide.LEFT: [],
		ChessSetupCue.HandSide.RIGHT: [],
	}
	_king_barrier_cue = null
	for cue in profile.cues:
		if profile.order_mode == ChessArmySetupProfile.OrderMode.SEEDED_RANDOM_KING_LAST and cue.display_coordinate == Vector2i(7, 4):
			_king_barrier_cue = cue
		else:
			resolved_tracks[cue.hand_side].append(cue)
	if profile.order_mode == ChessArmySetupProfile.OrderMode.SEEDED_RANDOM_KING_LAST:
		_shuffle_track(resolved_tracks[ChessSetupCue.HandSide.LEFT], opening_seed ^ 0x4c454654)
		_shuffle_track(resolved_tracks[ChessSetupCue.HandSide.RIGHT], opening_seed ^ 0x52474854)


func _shuffle_track(track: Array, seed: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed
	for index in range(track.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var value = track[index]
		track[index] = track[swap_index]
		track[swap_index] = value


func _run_single_cue(cue: ChessSetupCue, token: int) -> void:
	if not await _wait_interruptible(cue.gap_before, token):
		return
	var board_size := Vector2i(board_view.projection.rows, board_view.projection.columns)
	var display_coordinate := PresentationTransform.authored_display_coordinate(cue.display_coordinate, seat, board_size)
	var model_coordinate := board_view.projection.get_model_coordinate(display_coordinate)
	var piece: Node2D = piece_views.get(model_coordinate)
	if not is_instance_valid(piece):
		return
	cue_started.emit(cue)
	var hand := left_hand if cue.hand_side == ChessSetupCue.HandSide.LEFT else right_hand
	await hand.play_setup_placement(piece, board_view.grid_to_screen(model_coordinate.x, model_coordinate.y), board_view.get_world_scale(), profile.motion_for(cue), board_view.get_piece_depth(model_coordinate))
	if token == _generation:
		piece_placed.emit(cue, piece)


func _wait_interruptible(seconds: float, token: int) -> bool:
	var remaining := seconds
	while remaining > 0.0:
		await get_tree().process_frame
		if token != _generation:
			return false
		if not paused:
			remaining -= get_process_delta_time() * playback_speed
	return token == _generation
