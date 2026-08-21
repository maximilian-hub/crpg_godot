extends Node
class_name BoardSandbox

const PresentationPolicy = preload("res://scripts/view/chess_presentation_policy.gd")

enum Mode { EDIT, PLAY }

@onready var game: ChessGame = $ChessGame
@onready var model: ChessBoardModel = $ChessGame/ChessModel
@onready var game_controller: ChessBoardController = $ChessGame/ChessController
@onready var editor: BoardEditorController = $BoardEditorController
@onready var interaction: BoardEditorInteraction = $BoardEditorInteraction
@onready var panel: VBoxContainer = $SandboxLayer/Panel

var mode := Mode.EDIT
var history := BoardPositionHistory.new()
var restoring_history := false
var baseline: ChessPosition
var ai_side := "black"
var ai_mode := ChessCpuPlayer.ExecutionMode.DISABLED
var seed_value := 1

func _ready() -> void:
	editor.model = model
	interaction.configure(model, editor, $ChessGame/CanvasLayer/ChessBoard)
	editor.edit_committed.connect(_on_edit_committed)
	model.settled_action_completed.connect(_on_settled_action_completed)
	_build_panel()
	_set_mode(Mode.EDIT)
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Normal Start")

func _build_panel() -> void:
	_add_button("Edit / Play", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	_add_button("Undo", undo)
	_add_button("Redo", redo)
	_add_button("Reset", reset)
	_add_button("Clear", func(): editor.clear_board())
	_add_button("Copy Position", copy_position)
	_add_button("Paste Position", paste_position)
	_add_button("AI Off", func(): _configure_ai(ChessCpuPlayer.ExecutionMode.DISABLED))
	_add_button("AI Auto", func(): _configure_ai(ChessCpuPlayer.ExecutionMode.AUTO))
	_add_button("AI Manual", func(): _configure_ai(ChessCpuPlayer.ExecutionMode.MANUAL))
	_add_button("AI Side", func():
		ai_side = "white" if ai_side == "black" else "black"
		_configure_ai(ai_mode))
	_add_button("AI Think", think_ai)
	_add_button("AI Execute", execute_ai)
	_add_button("AI Step", step_ai)
	_add_button("Speed Normal", func(): _set_speed(PresentationPolicy.Speed.NORMAL))
	_add_button("Speed Fast", func(): _set_speed(PresentationPolicy.Speed.FAST))
	_add_button("Speed Instant", func(): _set_speed(PresentationPolicy.Speed.INSTANT))
	_add_button("Toggle Grip Anchors", func():
		var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
		board.show_piece_grip_anchors = not board.show_piece_grip_anchors)
	var seed := SpinBox.new()
	seed.min_value = 0
	seed.max_value = 2147483647
	seed.value = seed_value
	seed.value_changed.connect(func(value: float):
		seed_value = int(value)
		_active_cpu().set_random_seed(seed_value))
	panel.add_child(seed)
	var preset := OptionButton.new()
	preset.add_item("Normal Start")
	preset.add_item("Empty Board")
	preset.add_item("Debug Layout")
	preset.item_selected.connect(_on_preset_selected)
	panel.add_child(preset)
	var color := OptionButton.new()
	color.add_item("White")
	color.add_item("Black")
	color.item_selected.connect(func(index: int): editor.select_palette_piece(editor.selected_type_id, "white" if index == 0 else "black"))
	panel.add_child(color)
	var turn := OptionButton.new()
	turn.add_item("White to move")
	turn.add_item("Black to move")
	turn.item_selected.connect(func(index: int): editor.set_current_turn("white" if index == 0 else "black"))
	panel.add_child(turn)
	for type_id in ChessPieceCatalog.get_type_ids(true):
		var definition := ChessPieceCatalog.get_definition(type_id)
		_add_button(definition.get("name", String(type_id)), func(id = type_id): editor.select_palette_piece(id, editor.selected_color))

func _add_button(label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	panel.add_child(button)

func _set_mode(next: Mode) -> void:
	if not model.is_settled(): return
	mode = next
	var editing := mode == Mode.EDIT
	editor.set_enabled(editing)
	var controlled: Array[String] = []
	if not editing:
		controlled.assign(["white", "black"])
	game_controller.configure_player_controlled_colors(controlled)
	if editing:
		_configure_ai(ChessCpuPlayer.ExecutionMode.DISABLED)
	else:
		_apply_play_control()

func _on_edit_committed(_before: ChessPosition, after: ChessPosition, label: String) -> void:
	if not restoring_history: history.push(after, label)

func _on_settled_action_completed() -> void:
	if mode == Mode.PLAY and not restoring_history:
		history.push(model.capture_position(), "Gameplay action")

func undo() -> void:
	_restore(history.undo())

func redo() -> void:
	_restore(history.redo())

func reset() -> void:
	_restore(history.get_baseline())
	if baseline != null: history.establish_baseline(baseline)

func _restore(position: ChessPosition) -> void:
	if position == null or not model.is_settled(): return
	restoring_history = true
	model.load_position(position)
	restoring_history = false

func _on_preset_selected(index: int) -> void:
	var position := ChessPositionPresets.normal_start()
	if index == 1: position = ChessPositionPresets.empty()
	if index == 2: position = ChessPositionPresets.debug_layout()
	if not editor.editor_enabled: _set_mode(Mode.EDIT)
	restoring_history = true
	model.load_position(position)
	restoring_history = false
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Preset")

func _active_cpu() -> ChessCpuPlayer:
	return game.white_cpu_player if ai_side == "white" else game.black_cpu_player

func _inactive_cpu() -> ChessCpuPlayer:
	return game.black_cpu_player if ai_side == "white" else game.white_cpu_player

func _configure_ai(next_mode: ChessCpuPlayer.ExecutionMode) -> void:
	ai_mode = next_mode
	game.white_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "white")
	game.black_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "black")
	if mode == Mode.PLAY and next_mode != ChessCpuPlayer.ExecutionMode.DISABLED:
		_active_cpu().set_random_seed(seed_value)
		_active_cpu().configure_mode(next_mode, ai_side)
	_apply_play_control()

func _apply_play_control() -> void:
	if mode != Mode.PLAY:
		return
	var colors: Array[String] = ["white", "black"]
	if ai_mode != ChessCpuPlayer.ExecutionMode.DISABLED:
		colors.erase(ai_side)
	game_controller.configure_player_controlled_colors(colors)

func think_ai() -> void:
	if mode == Mode.PLAY:
		_active_cpu().think()

func execute_ai() -> void:
	if mode == Mode.PLAY:
		await _active_cpu().execute_thought()

func step_ai() -> void:
	if mode == Mode.PLAY:
		await _active_cpu().step()

func copy_position() -> void:
	DisplayServer.clipboard_set(ChessPositionCodec.to_json(model.capture_position()))

func paste_position() -> void:
	if mode != Mode.EDIT:
		return
	var decoded := ChessPositionCodec.from_json(DisplayServer.clipboard_get())
	if decoded.position != null:
		restoring_history = true
		model.load_position(decoded.position)
		restoring_history = false
		baseline = model.capture_position()
		history.establish_baseline(baseline, "Imported position")

func _set_speed(speed: int) -> void:
	var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
	adapter.set_presentation_speed(speed)
