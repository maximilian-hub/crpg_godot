extends Node
class_name BoardSandbox

const PresentationPolicy = preload("res://scripts/view/chess_presentation_policy.gd")
const BoardPiecePaletteScript = preload("res://scripts/editor/board_piece_palette.gd")
const GameRecordScript = preload("res://scripts/state/chess_game_record.gd")
const GameRecordCodec = preload("res://scripts/state/chess_game_record_codec.gd")
const PerformanceTelemetry = preload("res://scripts/state/chess_ai_performance_telemetry.gd")
const ActionCodec = preload("res://scripts/state/chess_action_codec.gd")
const PureCore = preload("res://scripts/core/pure/classic_chess_core.gd")
const CoreAction = preload("res://scripts/core/pure/chess_core_action.gd")
const CoreStepResult = preload("res://scripts/core/pure/chess_core_step_result.gd")
const RecordExchange = preload("res://scripts/platform/game_record_exchange.gd")
const WATCH_PATH_EXIT := "M14 6 4 16l10 10v-7h9v-6h-9z M21 5h7v22h-7v-4h3V9h-3z"
const WATCH_PATH_PLAY := "M9 5v22l18-11z"
const WATCH_PATH_PAUSE := "M8 5h6v22H8z M18 5h6v22h-6z"
const WATCH_PATH_PREVIOUS := "M7 5h4v22H7z M27 6v20L12 16z"
const WATCH_PATH_NEXT := "M21 5h4v22h-4z M5 6v20l15-10z"

enum Mode { EDIT, PLAY }

@export var force_mobile_layout_for_testing := false

const COLOR_INACTIVE := Color("252331")
const COLOR_EDIT := Color("2878c7")
const COLOR_PLAY := Color("d36a25")
const COLOR_AUTO := Color("2d9b59")
const COLOR_MANUAL := Color("c58a24")
const COLOR_GOLD := Color("d1a43a")
const COLOR_CYAN := Color("28b8c7")
const COLOR_ULTRA_SLOW := Color("7659b8")
const COLOR_SLOW := Color("668dcc")
const COLOR_INSTANT := Color("b34fb5")
const COLOR_WHITE_SIDE := Color("e8e2d2")
const COLOR_BLACK_SIDE := Color("5b5568")

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
var ai_mode := ChessCpuPlayer.ExecutionMode.DISABLED
var ai_sides := {"white": false, "black": true}
var ai_brains := {"white": ChessCpuPlayer.BrainKind.DUPRE, "black": ChessCpuPlayer.BrainKind.DUPRE}
var seed_value := 1

var mode_button: Button
var view_side_button: Button
var undo_button: Button
var redo_button: Button
var reset_button: Button
var clear_button: Button
var ai_mode_buttons := {}
var ai_side_buttons := {}
var ai_brain_options := {}
var ai_brain_status_label: Label
var authority_options: Array[OptionButton] = []
var authority_status_labels: Array[Label] = []
var think_button: Button
var step_button: Button
var speed_slider: HSlider
var speed_value_label: Label
var cooldowns_check: CheckButton
var visibility_check: CheckButton
var visibility_threshold_spin: SpinBox
var grip_check: CheckButton
var grip_profile_option: OptionButton
var grip_x_spin: SpinBox
var grip_y_spin: SpinBox
var grip_save_button: Button
var grip_status_label: Label
var piece_skin_option: OptionButton
var piece_scale_spin: SpinBox
var piece_base_x_spin: SpinBox
var piece_base_y_spin: SpinBox
var seed_spin: SpinBox
var preset_option: OptionButton
var turn_option: OptionButton
var piece_palette
var thought_label: Label
var execute_button: Button
var grip_profile_ids: Array[StringName] = []
var syncing_grip_controls := false
var mobile_layout := false
var mobile_root: Control
var mobile_ai_panel: PanelContainer
var mobile_palette_button: Button
var mobile_toolbar_panel: PanelContainer
var reset_confirmation: ConfirmationDialog
var clear_confirmation: ConfirmationDialog
var mobile_ui_pointer := -1
var mobile_ui_touch_target: Variant = null
var mobile_button_callbacks: Dictionary = {}
var mobile_board_pointer := -1
var mobile_ai_visible_before_play := false
var active_record = GameRecordScript.new()
var replay_record
var replay_mode := false
var replay_cursor := 0
var replay_warnings: Array[String] = []
var pending_action: Dictionary = {}
var pending_ai: Dictionary = {}
var pending_selections: Array[Dictionary] = []
var record_provenance: Dictionary = {}
var record_panel: PanelContainer
var record_status_label: Label
var record_frame_label: Label
var record_note_edit: TextEdit
var replay_previous_button: Button
var replay_next_button: Button
var replay_flag_button: Button
var replay_fork_button: Button
var replay_analyze_button: Button
var record_open_dialog: FileDialog
var record_save_dialog: FileDialog
var record_save_clean := false
var record_exchange
var record_file_buttons: Array[Button] = []
var replay_analysis_running := false
var replay_playing := false
var replay_pause_requested := false
var replay_selection_queue: Array[Dictionary] = []
var replay_play_button: Button
var replay_watch_button: Button
var mobile_watch_controls: VBoxContainer
var mobile_watch_exit_button: Button
var mobile_watch_play_button: Button
var mobile_watch_previous_button: Button
var mobile_watch_next_button: Button
var mobile_watch_mode := false
var mobile_watch_play_icon: Texture2D
var mobile_watch_pause_icon: Texture2D
var replay_compatibility_label: Label
var report_panel: PanelContainer
var report_category_option: OptionButton
var report_urgency_option: OptionButton
var report_observed_edit: TextEdit
var report_expected_edit: TextEdit
var report_reasoning_edit: TextEdit
var report_notes_edit: TextEdit
var report_context_label: Label
var piece_skin_tuning := {
	PieceView.StandardSkin.CLASSIC: {"scale": 1.0, "base_offset": Vector2.ZERO},
	PieceView.StandardSkin.CHUNKY: {"scale": 1.25, "base_offset": Vector2(0.0, 5.0)},
}

func _ready() -> void:
	mobile_layout = force_mobile_layout_for_testing or OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	record_exchange = RecordExchange.new()
	_connect_record_exchange()
	PieceView.standard_skin = PieceView.StandardSkin.CLASSIC
	PieceView.standard_skin_scale = 1.0
	PieceView.standard_skin_base_offset = Vector2.ZERO
	editor.model = model
	var board_view: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	interaction.configure(model, editor, board_view)
	board_view.editor_square_entered.connect(_on_visibility_square_entered)
	board_view.editor_square_exited.connect(_on_visibility_square_exited)
	board_view.square_selected.connect(_release_gui_focus)
	editor.edit_committed.connect(_on_edit_committed)
	editor.tool_selection_changed.connect(func(_tool: BoardEditorController.Tool, _type_id: StringName, _color: String): _refresh_control_states())
	model.settled_action_completed.connect(_on_settled_action_completed)
	model.action_started.connect(func(_owner_color: String): _refresh_control_states())
	model.action_finished.connect(_refresh_control_states)
	model.action_cancelled.connect(_refresh_control_states)
	model.primary_action_committed.connect(_on_primary_action_committed)
	model.authoritative_selection_committed.connect(_on_authoritative_selection_committed)
	model.promotion_selection_requested.connect(_on_replay_promotion_requested)
	model.movement_type_selection_requested.connect(_on_replay_movement_grant_requested)
	model.reaction_selection_requested.connect(_on_replay_reaction_requested)
	model.board_rebuilt.connect(_on_board_rebuilt)
	history.changed.connect(func(_can_undo: bool, _can_redo: bool): _refresh_control_states())
	game.white_cpu_player.thought_changed.connect(func(thought): _on_ai_thought_changed(thought); _refresh_control_states())
	game.black_cpu_player.thought_changed.connect(func(thought): _on_ai_thought_changed(thought); _refresh_control_states())
	game.white_cpu_player.thinking_changed.connect(func(_thinking): _refresh_control_states())
	game.black_cpu_player.thinking_changed.connect(func(_thinking): _refresh_control_states())
	_build_panel()
	_build_record_panel()
	_build_report_panel()
	if mobile_layout: _build_mobile_watch_controls()
	if mobile_layout: _layout_mobile_controls()
	_set_mode(Mode.EDIT)
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Normal Start", {"kind": &"baseline", "context": _capture_record_context()})
	_refresh_control_states()

func _build_panel() -> void:
	if mobile_layout:
		_build_mobile_panel()
	else:
		_build_desktop_panel()

func _build_desktop_panel() -> void:
	mode_button = _add_button("", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	view_side_button = _add_button("", _toggle_viewing_side)
	_add_button("Record / Replay", _toggle_record_panel)
	var history_row := HBoxContainer.new()
	panel.add_child(history_row)
	undo_button = _add_button_to(history_row, "Undo [←]", undo)
	redo_button = _add_button_to(history_row, "Redo [→]", redo)
	reset_button = _add_button("Reset [R]", reset)
	clear_button = _add_button("Clear", func(): editor.clear_board())

	piece_skin_option = OptionButton.new()
	piece_skin_option.add_item("Classic")
	piece_skin_option.add_item("Chunky")
	piece_skin_option.item_selected.connect(_on_piece_skin_selected)
	_add_labeled_control("Piece Skin", piece_skin_option)
	piece_scale_spin = SpinBox.new()
	piece_scale_spin.min_value = 0.25
	piece_scale_spin.max_value = 4.0
	piece_scale_spin.step = 0.05
	piece_scale_spin.value = 1.0
	piece_scale_spin.tooltip_text = "Universal display-scale multiplier for the six standard pieces in the selected skin"
	piece_scale_spin.value_changed.connect(_on_piece_scale_changed)
	_add_labeled_control("Piece Scale", piece_scale_spin)
	var base_row := HBoxContainer.new()
	panel.add_child(base_row)
	piece_base_x_spin = _make_grip_spin_box()
	piece_base_y_spin = _make_grip_spin_box()
	base_row.add_child(_make_compact_labeled_control("Base X", piece_base_x_spin))
	base_row.add_child(_make_compact_labeled_control("Y", piece_base_y_spin))
	piece_base_x_spin.tooltip_text = "Shared horizontal offset from the board contact point"
	piece_base_y_spin.tooltip_text = "Shared vertical offset from the board contact point"
	piece_base_x_spin.value_changed.connect(_on_piece_base_changed)
	piece_base_y_spin.value_changed.connect(_on_piece_base_changed)

	_add_section_label("AI Mode")
	var mode_row := HBoxContainer.new()
	panel.add_child(mode_row)
	_add_ai_mode_button(mode_row, "Off", ChessCpuPlayer.ExecutionMode.DISABLED)
	_add_ai_mode_button(mode_row, "Auto", ChessCpuPlayer.ExecutionMode.AUTO)
	_add_ai_mode_button(mode_row, "Manual", ChessCpuPlayer.ExecutionMode.MANUAL)

	_add_section_label("AI Sides")
	var side_row := HBoxContainer.new()
	panel.add_child(side_row)
	_add_ai_side_button(side_row, "White", "white")
	_add_ai_side_button(side_row, "Black", "black")
	_add_section_label("Army Brains")
	_add_brain_selector(panel, "White", "white")
	_add_brain_selector(panel, "Black", "black")
	ai_brain_status_label = Label.new()
	ai_brain_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(ai_brain_status_label)
	_add_authority_selector(panel)

	think_button = _add_button("AI Think", think_ai)
	execute_button = _add_button("AI Execute", execute_ai)
	step_button = _add_button("AI Step", step_ai)
	thought_label = Label.new()
	thought_label.text = "No prepared action"
	thought_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thought_label.custom_minimum_size.x = 168.0
	panel.add_child(thought_label)

	_add_section_label("Animation Speed")
	var speed_row := HBoxContainer.new()
	panel.add_child(speed_row)
	speed_slider = HSlider.new()
	speed_slider.min_value = PresentationPolicy.Speed.ULTRA_SLOW
	speed_slider.max_value = PresentationPolicy.Speed.INSTANT
	speed_slider.step = 1.0
	speed_slider.value = PresentationPolicy.Speed.NORMAL
	speed_slider.custom_minimum_size.x = 104.0
	speed_slider.value_changed.connect(func(value: float): _set_speed(int(value)))
	speed_row.add_child(speed_slider)
	speed_value_label = Label.new()
	speed_value_label.custom_minimum_size.x = 72.0
	speed_row.add_child(speed_value_label)

	cooldowns_check = CheckButton.new()
	cooldowns_check.text = "Disable Cooldowns"
	cooldowns_check.tooltip_text = "Keep King active abilities ready for sandbox testing"
	cooldowns_check.toggled.connect(_on_cooldowns_toggled)
	panel.add_child(cooldowns_check)

	visibility_check = CheckButton.new()
	visibility_check.text = "Visibility Viewer"
	visibility_check.tooltip_text = "Show visible squares in yellow and obscured squares in red"
	visibility_check.toggled.connect(_on_visibility_toggled)
	panel.add_child(visibility_check)
	visibility_threshold_spin = SpinBox.new()
	visibility_threshold_spin.min_value = 0.0
	visibility_threshold_spin.max_value = 1.0
	visibility_threshold_spin.step = 0.01
	visibility_threshold_spin.value = ChessLineOfSight.DEFAULT_VISIBILITY_THRESHOLD
	visibility_threshold_spin.tooltip_text = "Minimum LOS score required for a square to appear visible"
	visibility_threshold_spin.value_changed.connect(_on_visibility_threshold_changed)
	_add_labeled_control("LOS Cutoff", visibility_threshold_spin)

	grip_check = CheckButton.new()
	grip_check.text = "Grip Anchors"
	grip_check.toggled.connect(_on_grip_toggled)
	panel.add_child(grip_check)

	_add_section_label("Piece Grip Tuning")
	grip_profile_option = OptionButton.new()
	for profile_id in PieceView.PIECE_ART_PROFILES.keys():
		grip_profile_ids.append(profile_id)
	grip_profile_ids.sort()
	for profile_id in grip_profile_ids:
		grip_profile_option.add_item(String(profile_id).capitalize())
	grip_profile_option.item_selected.connect(_load_grip_profile_controls)
	_add_labeled_control("Piece", grip_profile_option)
	var grip_row := HBoxContainer.new()
	panel.add_child(grip_row)
	grip_x_spin = _make_grip_spin_box()
	grip_y_spin = _make_grip_spin_box()
	grip_row.add_child(_make_compact_labeled_control("X", grip_x_spin))
	grip_row.add_child(_make_compact_labeled_control("Y", grip_y_spin))
	grip_x_spin.value_changed.connect(func(_value: float): _apply_live_piece_grip())
	grip_y_spin.value_changed.connect(func(_value: float): _apply_live_piece_grip())
	grip_save_button = _add_button("Save Piece Grip", _save_piece_grip)
	grip_status_label = Label.new()
	grip_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(grip_status_label)
	_load_grip_profile_controls(0)

	seed_spin = SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 2147483647
	seed_spin.value = seed_value
	seed_spin.value_changed.connect(_on_seed_changed)
	_add_labeled_control("AI Seed", seed_spin)

	preset_option = OptionButton.new()
	preset_option.add_item("Normal Start")
	preset_option.add_item("Empty Board")
	preset_option.add_item("Debug Layout")
	preset_option.item_selected.connect(_on_preset_selected)
	_add_labeled_control("Preset", preset_option)

	turn_option = OptionButton.new()
	turn_option.add_item("White")
	turn_option.add_item("Black")
	turn_option.item_selected.connect(func(index: int): editor.set_current_turn("white" if index == 0 else "black"))
	_add_labeled_control("Side to Move", turn_option)

	piece_palette = BoardPiecePaletteScript.new()
	piece_palette.name = "PiecePalette"
	piece_palette.cursor_selected.connect(editor.select_cursor_tool)
	piece_palette.delete_selected.connect(editor.select_delete_tool)
	piece_palette.piece_selected.connect(editor.select_palette_piece)
	piece_palette.piece_drag_requested.connect(_on_palette_piece_drag_requested)
	$SandboxLayer.add_child(piece_palette)
	piece_palette.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	piece_palette.offset_left = -180.0
	piece_palette.offset_top = 140.0
	piece_palette.offset_right = -12.0
	piece_palette.offset_bottom = 140.0

func _exit_tree() -> void:
	PieceView.standard_skin = PieceView.StandardSkin.CLASSIC
	PieceView.standard_skin_scale = 1.0
	PieceView.standard_skin_base_offset = Vector2.ZERO

func _on_piece_skin_selected(index: int) -> void:
	PieceView.standard_skin = PieceView.StandardSkin.CHUNKY if index == 1 else PieceView.StandardSkin.CLASSIC
	_load_piece_skin_tuning()
	_refresh_piece_art()

func _on_piece_scale_changed(value: float) -> void:
	var tuning: Dictionary = piece_skin_tuning[PieceView.standard_skin]
	tuning["scale"] = value
	PieceView.standard_skin_scale = value
	_refresh_piece_art()

func _on_piece_base_changed(_value: float) -> void:
	if piece_base_x_spin == null or piece_base_y_spin == null:
		return
	var offset := Vector2(piece_base_x_spin.value, piece_base_y_spin.value)
	var tuning: Dictionary = piece_skin_tuning[PieceView.standard_skin]
	tuning["base_offset"] = offset
	PieceView.standard_skin_base_offset = offset
	_refresh_piece_art()

func _load_piece_skin_tuning() -> void:
	var tuning: Dictionary = piece_skin_tuning[PieceView.standard_skin]
	PieceView.standard_skin_scale = float(tuning["scale"])
	PieceView.standard_skin_base_offset = tuning["base_offset"]
	if piece_scale_spin != null:
		piece_scale_spin.set_value_no_signal(PieceView.standard_skin_scale)
		piece_base_x_spin.set_value_no_signal(PieceView.standard_skin_base_offset.x)
		piece_base_y_spin.set_value_no_signal(PieceView.standard_skin_base_offset.y)

func _refresh_piece_art() -> void:
	for piece_view in find_children("*", "PieceView", true, false):
		piece_view.update_sprite()
		var palette_item := piece_view.get_parent()
		if palette_item is BoardPiecePaletteItem:
			palette_item._layout_content()

func _build_record_panel() -> void:
	record_panel = PanelContainer.new()
	record_panel.name = "RecordReplayPanel"
	if mobile_layout:
		record_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		record_panel.offset_left = 12.0
		record_panel.offset_top = 70.0
		record_panel.offset_right = -12.0
		record_panel.offset_bottom = -12.0
	else:
		record_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		record_panel.offset_left = -472.0
		record_panel.offset_top = 360.0
		record_panel.offset_right = -12.0
		record_panel.offset_bottom = 960.0
	record_panel.visible = false
	$SandboxLayer.add_child(record_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	record_panel.add_child(scroll)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.text = "Game Record / Replay"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	record_frame_label = Label.new()
	record_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(record_frame_label)
	var nav := HBoxContainer.new()
	column.add_child(nav)
	replay_previous_button = _add_button_to(nav, "◀ Previous Turn", _replay_previous_turn)
	replay_next_button = _add_button_to(nav, "Next Turn ▶", _replay_next_turn)
	var playback := HBoxContainer.new()
	column.add_child(playback)
	replay_watch_button = _add_button_to(playback, "Watch from Start", _watch_replay_from_start)
	replay_play_button = _add_button_to(playback, "Play", _toggle_replay_playback)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	record_file_buttons.append(_add_button_to(actions, "Save Game", _save_clean_game_record))
	if record_exchange.is_available():
		record_file_buttons.append(_add_button_to(actions, "Share Game", _share_clean_game_record))
	_add_button_to(actions, "Report Issue", _open_report_panel)
	var import_actions := HBoxContainer.new()
	column.add_child(import_actions)
	record_file_buttons.append(_add_button_to(import_actions, "Open Game", _open_game_record))
	var replay_actions := HBoxContainer.new()
	column.add_child(replay_actions)
	replay_flag_button = _add_button_to(replay_actions, "Flag Frame", _flag_replay_frame)
	replay_fork_button = _add_button_to(replay_actions, "Fork Here", fork_replay_here)
	replay_analyze_button = _add_button_to(replay_actions, "Analyze Again", analyze_replay_again)
	var note_label := Label.new()
	note_label.text = "Imported report note"
	column.add_child(note_label)
	record_note_edit = TextEdit.new()
	record_note_edit.custom_minimum_size.y = 92.0
	record_note_edit.placeholder_text = "What looked wrong at the flagged frame?"
	record_note_edit.editable = false
	record_note_edit.text_changed.connect(_on_record_note_changed)
	column.add_child(record_note_edit)
	record_status_label = Label.new()
	record_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_status_label.custom_minimum_size.y = 58.0
	column.add_child(record_status_label)
	replay_compatibility_label = Label.new()
	replay_compatibility_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	replay_compatibility_label.modulate = Color("d6b35a")
	column.add_child(replay_compatibility_label)
	_add_button_to(column, "Close", _toggle_record_panel)
	if not mobile_layout:
		record_open_dialog = FileDialog.new()
		record_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
		record_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		record_open_dialog.add_filter("*.crpggame", "CRPG Chess Game")
		record_open_dialog.file_selected.connect(_open_game_record_file)
		add_child(record_open_dialog)
		record_save_dialog = FileDialog.new()
		record_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		record_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		record_save_dialog.add_filter("*.crpggame", "CRPG Chess Game")
		record_save_dialog.file_selected.connect(_save_game_record_file)
		add_child(record_save_dialog)
		get_viewport().size_changed.connect(_layout_record_panel)
		call_deferred(&"_layout_record_panel")
	_refresh_record_panel()

func _build_report_panel() -> void:
	report_panel = PanelContainer.new()
	report_panel.name = "GameIssueReportPanel"
	report_panel.visible = false
	report_panel.z_index = 200
	if mobile_layout:
		report_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		report_panel.offset_left = 12.0
		report_panel.offset_top = 12.0
		report_panel.offset_right = -12.0
		report_panel.offset_bottom = -12.0
	else:
		report_panel.set_anchors_preset(Control.PRESET_CENTER)
		report_panel.offset_left = -330.0
		report_panel.offset_top = -340.0
		report_panel.offset_right = 330.0
		report_panel.offset_bottom = 340.0
	$SandboxLayer.add_child(report_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	var title := Label.new()
	title.text = "Report an Interesting Turn"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	report_context_label = Label.new()
	report_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(report_context_label)
	report_category_option = OptionButton.new()
	for label in ["Tactical mistake", "Strategic mistake", "Ability use", "Repetition / no plan", "Endgame", "Good play", "Other"]:
		report_category_option.add_item(label)
	_add_report_field(column, "Type", report_category_option)
	report_urgency_option = OptionButton.new()
	report_urgency_option.add_item("Immediate / tactical")
	report_urgency_option.add_item("Slower / strategic")
	_add_report_field(column, "Urgency", report_urgency_option)
	report_observed_edit = _make_report_text_edit("What did Dupre do?", 82.0)
	_add_report_field(column, "What happened? *", report_observed_edit)
	report_expected_edit = _make_report_text_edit("What should Dupre have considered instead?", 82.0)
	_add_report_field(column, "What did you expect?", report_expected_edit)
	report_reasoning_edit = _make_report_text_edit("Why was the move bad, good, or interesting?", 82.0)
	_add_report_field(column, "Why was it interesting?", report_reasoning_edit)
	report_notes_edit = _make_report_text_edit("Anything else that may help reproduce or understand it.", 70.0)
	_add_report_field(column, "Additional notes", report_notes_edit)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	record_file_buttons.append(_add_button_to(actions, "Save Report", _save_issue_report))
	if record_exchange.is_available():
		record_file_buttons.append(_add_button_to(actions, "Share Report", _share_issue_report))
	_add_button_to(actions, "Cancel", _close_report_panel)

func _build_mobile_watch_controls() -> void:
	mobile_watch_controls = VBoxContainer.new()
	mobile_watch_controls.name = "ReplayWatchControls"
	mobile_watch_controls.visible = false
	mobile_watch_controls.z_index = 300
	mobile_watch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_watch_controls.add_theme_constant_override("separation", 8)
	$SandboxLayer.add_child(mobile_watch_controls)
	mobile_watch_play_icon = _make_watch_icon(WATCH_PATH_PLAY)
	mobile_watch_pause_icon = _make_watch_icon(WATCH_PATH_PAUSE)
	mobile_watch_exit_button = _add_watch_icon_button(_make_watch_icon(WATCH_PATH_EXIT), "Return to replay controls", _exit_mobile_watch_mode)
	mobile_watch_play_button = _add_watch_icon_button(mobile_watch_pause_icon, "Pause replay", _toggle_replay_playback)
	mobile_watch_next_button = _add_watch_icon_button(_make_watch_icon(WATCH_PATH_NEXT), "Next turn", _replay_next_turn)
	mobile_watch_previous_button = _add_watch_icon_button(_make_watch_icon(WATCH_PATH_PREVIOUS), "Previous turn", _replay_previous_turn)

func _make_watch_icon(path_data: String) -> Texture2D:
	var image := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><path fill="#fff" d="%s"/></svg>' % path_data
	if image.load_svg_from_string(svg, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _add_watch_icon_button(icon: Texture2D, description: String, callback: Callable) -> Button:
	var button := _add_button_to(mobile_watch_controls, "", callback)
	button.icon = icon
	button.custom_minimum_size = Vector2(52.0, 52.0)
	button.tooltip_text = description
	button.set_meta(&"accessibility_name", description)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button

func _add_report_field(column: VBoxContainer, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	column.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(control)

func _make_report_text_edit(placeholder: String, height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.placeholder_text = placeholder
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit

func _open_report_panel() -> void:
	var record = replay_record if replay_mode else _record_from_history()
	if record == null:
		return
	if record.flagged_frame < 0:
		record_status_label.text = "Flag the interesting turn before creating a report."
		return
	var report: Dictionary = record.issue_report
	_select_option_text(report_category_option, String(report.get("category", "Tactical mistake")))
	_select_option_text(report_urgency_option, String(report.get("urgency", "Immediate / tactical")))
	report_observed_edit.text = String(report.get("observed", record.issue_note))
	report_expected_edit.text = String(report.get("expected", ""))
	report_reasoning_edit.text = String(report.get("reasoning", ""))
	report_notes_edit.text = record.issue_note if not record.issue_note.is_empty() and record.issue_note != report_observed_edit.text else ""
	report_context_label.text = _report_context(record, record.flagged_frame)
	report_panel.visible = true
	record_panel.visible = false

func _close_report_panel() -> void:
	report_panel.visible = false
	record_panel.visible = true

func _select_option_text(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if option.get_item_text(index) == value:
			option.select(index)
			return
	option.select(0)

func _store_issue_report() -> bool:
	var record = replay_record if replay_mode else _record_from_history()
	if record == null or record.flagged_frame < 0:
		report_context_label.text = "Flag an interesting turn before exporting a report."
		return false
	var observed := report_observed_edit.text.strip_edges()
	if observed.is_empty():
		report_context_label.text = "Please briefly describe what happened."
		report_observed_edit.grab_focus()
		return false
	record.issue_report = {
		"category": report_category_option.get_item_text(report_category_option.selected),
		"urgency": report_urgency_option.get_item_text(report_urgency_option.selected),
		"observed": observed,
		"expected": report_expected_edit.text.strip_edges(),
		"reasoning": report_reasoning_edit.text.strip_edges(),
	}
	record.issue_note = report_notes_edit.text.strip_edges()
	if record.issue_note.is_empty():
		record.issue_note = observed
	return true

func _save_clean_game_record() -> void:
	var record = _clean_export_record()
	if record_exchange.is_available():
		_begin_native_record_operation("Saving game…")
		record_exchange.save_document(RecordExchange.suggested_filename(false), GameRecordCodec.to_json(record))
		return
	record_save_clean = true
	record_save_dialog.current_file = RecordExchange.suggested_filename(false)
	record_save_dialog.popup_centered_ratio(0.7)

func _share_clean_game_record() -> void:
	var record = _clean_export_record()
	_begin_native_record_operation("Opening share sheet…")
	record_exchange.share_document(RecordExchange.suggested_filename(false), GameRecordCodec.to_json(record))

func _save_issue_report() -> void:
	if not _store_issue_report(): return
	var record = replay_record if replay_mode else _record_from_history()
	_close_report_after_export()
	if record_exchange.is_available():
		_begin_native_record_operation("Saving report…")
		record_exchange.save_document(RecordExchange.suggested_filename(true), GameRecordCodec.to_json(record))
		return
	record_save_clean = false
	record_save_dialog.current_file = RecordExchange.suggested_filename(true)
	record_save_dialog.popup_centered_ratio(0.7)

func _share_issue_report() -> void:
	if not _store_issue_report(): return
	var record = replay_record if replay_mode else _record_from_history()
	_close_report_after_export()
	_begin_native_record_operation("Opening share sheet…")
	record_exchange.share_document(RecordExchange.suggested_filename(true), GameRecordCodec.to_json(record))

func _open_game_record() -> void:
	if record_exchange.is_available():
		_begin_native_record_operation("Opening document picker…")
		record_exchange.open_document()
		return
	record_open_dialog.popup_centered_ratio(0.7)

func _close_report_after_export() -> void:
	report_panel.visible = false
	record_panel.visible = true

func _clean_export_record():
	var source = replay_record if replay_mode else _record_from_history()
	var record = source.copy()
	record.clear_issue_report()
	_strip_detailed_ai_diagnostics(record)
	return record

func _strip_detailed_ai_diagnostics(record) -> void:
	for frame in record.frames:
		var ai: Dictionary = frame.get("ai", {})
		if ai.is_empty(): continue
		ai.erase("search_profile")
		ai.erase("candidates")

func _connect_record_exchange() -> void:
	record_exchange.document_saved.connect(func(display_name: String):
		_finish_native_record_operation("Saved %s." % display_name)
	)
	record_exchange.document_shared.connect(func(display_name: String):
		_finish_native_record_operation("Shared %s." % display_name)
	)
	record_exchange.document_opened.connect(func(contents: String, display_name: String):
		for button in record_file_buttons: button.disabled = false
		if import_record_text(contents):
			record_status_label.text = "Opened %s." % display_name
	)
	record_exchange.operation_cancelled.connect(func(operation: String):
		_finish_native_record_operation("%s cancelled." % operation.capitalize())
	)
	record_exchange.operation_failed.connect(func(operation: String, message: String):
		_finish_native_record_operation("%s failed: %s" % [operation.capitalize(), message])
	)

func _begin_native_record_operation(message: String) -> void:
	for button in record_file_buttons: button.disabled = true
	record_status_label.text = message

func _finish_native_record_operation(message: String) -> void:
	for button in record_file_buttons: button.disabled = false
	record_status_label.text = message

func _report_context(record, frame_index: int) -> String:
	if frame_index < 0 or frame_index >= record.frames.size(): return "Unknown turn"
	var frame: Dictionary = record.frames[frame_index]
	var position: ChessPosition = record.frames[maxi(0, frame_index - 1)].get("position")
	var round_number := maxi(1, int(ceili(float(position.global_turn_number) / 2.0))) if position != null else 0
	var action: Dictionary = frame.get("action", {})
	var color := String(action.get("color", "Unknown")).capitalize()
	var context: Dictionary = frame.get("context", {})
	var cpu: Dictionary = context.get(String(action.get("color", "")), {})
	var brain := String(cpu.get("brain", frame.get("ai", {}).get("brain_id", "Unknown")))
	var matchup := "%s vs %s" % [_king_label(position, "white"), _king_label(position, "black")]
	return "Frame %d · Round %d · %s · %s · Seed %s\n%s · %s" % [frame_index + 1, round_number, color, brain, context.get("seed", "?"), matchup, String(frame.get("label", "Recorded turn"))]

func _king_label(position: ChessPosition, color: String) -> String:
	if position == null: return color.capitalize()
	for piece in position.pieces:
		if piece.color == color and (String(piece.type_id).ends_with("king") or String(piece.type_id).contains("archer")):
			return "%s %s" % [color.capitalize(), String(piece.type_id).replace("_", " ").capitalize()]
	return color.capitalize()

func _layout_record_panel() -> void:
	if mobile_layout or record_panel == null or piece_palette == null: return
	var palette_bottom: float = piece_palette.position.y + piece_palette.size.y
	var top: float = palette_bottom + 12.0
	var available_height: float = get_viewport().get_visible_rect().size.y - top - 12.0
	record_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	record_panel.offset_left = -472.0
	record_panel.offset_top = top
	record_panel.offset_right = -12.0
	record_panel.offset_bottom = top + minf(640.0, maxf(320.0, available_height))

func _toggle_record_panel() -> void:
	if record_panel == null: return
	record_panel.visible = not record_panel.visible
	if record_panel.visible:
		if mobile_ai_panel != null: mobile_ai_panel.visible = false
		if piece_palette != null and mobile_layout: piece_palette.visible = false
		_refresh_record_panel()
	elif mobile_layout and mode == Mode.EDIT and piece_palette != null:
		piece_palette.visible = true

func _refresh_record_panel() -> void:
	if record_frame_label == null: return
	var count: int = replay_record.frames.size() if replay_mode and replay_record != null else history.entries.size()
	var cursor: int = replay_cursor if replay_mode else history.cursor
	record_frame_label.text = "%s — Frame %d / %d" % ["Replay" if replay_mode else "Live Recording", cursor + 1, count]
	replay_previous_button.disabled = not replay_mode or replay_cursor <= 0
	replay_next_button.disabled = not replay_mode or replay_record == null or replay_playing or _next_replay_turn_index(replay_cursor) < 0
	replay_previous_button.disabled = not replay_mode or replay_playing or _previous_replay_turn_index(replay_cursor) < 0
	if replay_play_button != null:
		replay_play_button.text = "Pausing…" if replay_pause_requested else ("Pause after Turn" if replay_playing else "Play")
		replay_play_button.disabled = not replay_mode or replay_pause_requested or (not replay_playing and _next_replay_turn_index(replay_cursor) < 0)
	if replay_watch_button != null:
		replay_watch_button.disabled = not replay_mode or replay_playing or _first_replay_turn_index() < 0
	replay_flag_button.disabled = count <= 0 or replay_playing
	replay_fork_button.disabled = not replay_mode or replay_playing
	replay_analyze_button.disabled = not replay_mode or replay_cursor <= 0 or replay_playing
	for button in record_file_buttons:
		button.disabled = record_exchange.operation_pending or (mobile_layout and not record_exchange.is_available())
	_refresh_mobile_watch_controls()
	var record = replay_record if replay_mode else _record_from_history()
	var note: String = record.issue_note if record != null else ""
	if record_note_edit.text != note:
		record_note_edit.set_text(note)
	replay_flag_button.text = "Flagged ✓" if record != null and record.flagged_frame == cursor else "Flag Frame"
	if replay_mode and replay_record != null:
		var frame: Dictionary = replay_record.frames[replay_cursor]
		var details := String(frame.get("label", ""))
		var ai: Dictionary = frame.get("ai", {})
		if not ai.is_empty():
			var candidates: Array = ai.get("candidates", [])
			var telemetry: Dictionary = ai.get("performance", {})
			if telemetry.is_empty(): telemetry = PerformanceTelemetry.from_search_profile(ai.get("search_profile", {}))
			details += "\n%s score %.2f" % [ai.get("brain_id", "AI"), float(ai.get("score", 0.0))]
			if not telemetry.is_empty():
				var thinking_ms := float(telemetry.get("thinking_usec", 0)) / 1000.0
				var replies := int(telemetry.get("evaluated_reply_count", 0))
				var rate := float(replies) * 1000000.0 / maxf(1.0, float(telemetry.get("thinking_usec", 0)))
				details += "\n%.1f ms · %d replies (%.1f/s) · roots %d exact / %d incomplete / %d pruned" % [
					thinking_ms, replies, rate, int(telemetry.get("exact_root_candidates", 0)),
					int(telemetry.get("incomplete_root_candidates", 0)), int(telemetry.get("pruned_root_candidates", 0)),
				]
				details += "\n%s · max uninterrupted %.2f ms%s" % [
					String(telemetry.get("selected_status", "unknown")),
					float(telemetry.get("maximum_uninterrupted_usec", 0)) / 1000.0,
					" · UNVERIFIED" if bool(telemetry.get("unverified", false)) else "",
				]
			if not candidates.is_empty(): details += " — %d detailed candidates" % candidates.size()
			for candidate_index in range(mini(candidates.size(), 12)):
				var candidate: Dictionary = candidates[candidate_index]
				var action: Dictionary = candidate.get("action", {})
				var candidate_score := float(candidate.get("search_score", candidate.get("score", candidate.get("policy_score", 0.0))))
				details += "\n%d. %s → %s  %.2f%s" % [candidate_index + 1, action.get("from", action.get("piece_type", "?")), action.get("target", "?"), candidate_score, "  " + String(candidate.get("reason", "")) if candidate.has("reason") else ""]
		if not replay_warnings.is_empty():
			details += "\n⚠ " + "\n⚠ ".join(replay_warnings)
		var summary := PerformanceTelemetry.summarize_frames(replay_record.frames)
		if int(summary.get("turns", 0)) > 0:
			details += "\n\nMatch: %d AI turns · %.1f replies/s · %d fallbacks · %d unverified" % [
				int(summary.turns), float(summary.replies_per_second), int(summary.fallback_turns), int(summary.unverified_turns),
			]
		record_status_label.text = details


func _build_mobile_panel() -> void:
	panel.visible = false
	mobile_root = Control.new()
	mobile_root.name = "MobileSandboxControls"
	mobile_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SandboxLayer.add_child(mobile_root)

	mobile_toolbar_panel = PanelContainer.new()
	mobile_toolbar_panel.name = "Toolbar"
	mobile_toolbar_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mobile_root.add_child(mobile_toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	mobile_toolbar_panel.add_child(toolbar)
	mode_button = _add_button_to(toolbar, "", func(): _set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT))
	undo_button = _add_button_to(toolbar, "Back", undo)
	redo_button = _add_button_to(toolbar, "Forward", redo)
	reset_button = _add_button_to(toolbar, "Reset", reset)
	clear_button = _add_button_to(toolbar, "Clear", func(): editor.clear_board())
	mobile_palette_button = _add_button_to(toolbar, "Pieces", _toggle_mobile_palette)
	_add_button_to(toolbar, "AI", _toggle_mobile_ai_panel)
	_add_button_to(toolbar, "Replay", _toggle_record_panel)

	mobile_ai_panel = PanelContainer.new()
	mobile_ai_panel.name = "AISettings"
	mobile_ai_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mobile_ai_panel.offset_left = -286.0
	mobile_ai_panel.offset_top = 74.0
	mobile_ai_panel.offset_right = -16.0
	mobile_ai_panel.offset_bottom = 238.0
	mobile_ai_panel.visible = false
	mobile_root.add_child(mobile_ai_panel)
	var ai_column := VBoxContainer.new()
	ai_column.add_theme_constant_override("separation", 6)
	mobile_ai_panel.add_child(ai_column)
	var ai_title := Label.new()
	ai_title.text = "AI Mode"
	ai_column.add_child(ai_title)
	var mode_row := HBoxContainer.new()
	ai_column.add_child(mode_row)
	_add_ai_mode_button(mode_row, "Off", ChessCpuPlayer.ExecutionMode.DISABLED)
	_add_ai_mode_button(mode_row, "Auto", ChessCpuPlayer.ExecutionMode.AUTO)
	var sides_title := Label.new()
	sides_title.text = "AI Sides"
	ai_column.add_child(sides_title)
	var side_row := HBoxContainer.new()
	ai_column.add_child(side_row)
	_add_ai_side_button(side_row, "White", "white")
	_add_ai_side_button(side_row, "Black", "black")
	_add_brain_selector(ai_column, "White Brain", "white")
	_add_brain_selector(ai_column, "Black Brain", "black")
	ai_brain_status_label = Label.new()
	ai_brain_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_column.add_child(ai_brain_status_label)
	_add_authority_selector(ai_column)
	cooldowns_check = CheckButton.new()
	cooldowns_check.text = "Disable Cooldowns"
	cooldowns_check.toggled.connect(_on_cooldowns_toggled)
	ai_column.add_child(cooldowns_check)

	piece_palette = BoardPiecePaletteScript.new()
	piece_palette.name = "PiecePalette"
	piece_palette.configure_mobile_layout()
	piece_palette.cursor_selected.connect(editor.select_cursor_tool)
	piece_palette.delete_selected.connect(editor.select_delete_tool)
	piece_palette.piece_selected.connect(editor.select_palette_piece)
	piece_palette.piece_drag_requested.connect(_on_palette_piece_drag_requested)
	mobile_root.add_child(piece_palette)
	piece_palette.set_mobile_overlay_host(mobile_root)
	piece_palette.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	piece_palette.offset_left = 16.0
	piece_palette.offset_top = -108.0
	piece_palette.offset_right = -16.0
	piece_palette.offset_bottom = -12.0

	reset_confirmation = _make_confirmation("Reset position?", "Restore the normal starting position and discard position history.", reset)
	clear_confirmation = _make_confirmation("Clear position?", "Remove every piece from the board? This can be undone.", func(): editor.clear_board())
	get_viewport().size_changed.connect(_layout_mobile_controls)
	_layout_mobile_controls()

func _layout_mobile_controls() -> void:
	if mobile_root == null:
		return
	var left := 16.0
	var right := 16.0
	var top := 12.0
	var bottom := 12.0
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var viewport_size := get_viewport().get_visible_rect().size
	if screen_size.x > 0.0 and screen_size.y > 0.0 and viewport_size.x > 0.0 and viewport_size.y > 0.0:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var scale := viewport_size / screen_size
		left = maxf(left, safe.position.x * scale.x)
		right = maxf(right, (screen_size.x - safe.end.x) * scale.x)
		top = maxf(top, safe.position.y * scale.y)
		bottom = maxf(bottom, (screen_size.y - safe.end.y) * scale.y)
	if mode == Mode.PLAY:
		mobile_toolbar_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		mobile_toolbar_panel.offset_left = left
		mobile_toolbar_panel.offset_top = top
		mobile_toolbar_panel.offset_right = left + 112.0
		mobile_toolbar_panel.offset_bottom = top + 54.0
	else:
		mobile_toolbar_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
		mobile_toolbar_panel.offset_left = left
		mobile_toolbar_panel.offset_top = top
		mobile_toolbar_panel.offset_right = -right
		mobile_toolbar_panel.offset_bottom = top + 54.0
	mobile_ai_panel.offset_left = -(right + 270.0)
	mobile_ai_panel.offset_top = top + 62.0
	mobile_ai_panel.offset_right = -right
	mobile_ai_panel.offset_bottom = top + 330.0
	piece_palette.offset_left = left
	piece_palette.offset_top = -(bottom + 96.0)
	piece_palette.offset_right = -right
	piece_palette.offset_bottom = -bottom
	piece_palette._layout_king_picker()
	if record_panel != null:
		record_panel.offset_left = left
		record_panel.offset_top = top + 58.0
		record_panel.offset_right = -right
		record_panel.offset_bottom = -bottom
	if report_panel != null:
		report_panel.offset_left = left
		report_panel.offset_top = top
		report_panel.offset_right = -right
		report_panel.offset_bottom = -bottom
	if mobile_watch_controls != null:
		var controls_height := mobile_watch_controls.get_combined_minimum_size().y
		mobile_watch_controls.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		mobile_watch_controls.offset_left = -(right + 52.0)
		mobile_watch_controls.offset_top = -controls_height * 0.5
		mobile_watch_controls.offset_right = -right
		mobile_watch_controls.offset_bottom = controls_height * 0.5

func _make_confirmation(title: String, message: String, callback: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.confirmed.connect(callback)
	mobile_root.add_child(dialog)
	_enable_mobile_touch_activation(dialog.get_ok_button())
	_enable_mobile_touch_activation(dialog.get_cancel_button())
	return dialog

func _request_reset() -> void:
	reset_confirmation.popup_centered(Vector2i(460, 190))

func _request_clear() -> void:
	clear_confirmation.popup_centered(Vector2i(460, 190))

func _toggle_mobile_palette() -> void:
	piece_palette.visible = not piece_palette.visible
	if piece_palette.visible:
		mobile_ai_panel.visible = false

func _toggle_mobile_ai_panel() -> void:
	mobile_ai_panel.visible = not mobile_ai_panel.visible
	if mobile_ai_panel.visible:
		piece_palette.visible = false

func _on_palette_piece_drag_requested(type_id: StringName, color: String) -> void:
	if editor.select_palette_piece(type_id, color):
		var pointer_index: int = piece_palette.last_drag_pointer_index
		var initial_position: Vector2 = piece_palette.last_drag_viewport_position if pointer_index >= 0 else Vector2.INF
		interaction.begin_palette_drag(type_id, color, pointer_index, initial_position)

func _release_gui_focus(_coordinate := Vector2i.ZERO) -> void:
	get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if mobile_layout:
		if _route_mobile_ui_touch(event):
			return
		if _route_mobile_board_touch(event):
			return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_release_text_focus_if_scene_clicked(get_viewport().gui_get_hovered_control())

func _route_mobile_ui_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if mobile_ui_pointer >= 0:
				return false
			mobile_ui_touch_target = null
			var touch_is_in_king_picker: bool = piece_palette != null and piece_palette.king_picker != null and piece_palette.king_picker.visible and piece_palette.king_picker.get_global_rect().has_point(touch.position)
			if touch_is_in_king_picker and piece_palette.handle_mobile_touch_pressed(touch.position, touch.index):
				mobile_ui_touch_target = piece_palette
			else:
				var mobile_button := _mobile_button_at(touch.position)
				if mobile_button != null:
					mobile_ui_touch_target = mobile_button
				elif piece_palette != null and piece_palette.mobile_contains(touch.position):
					if not piece_palette.handle_mobile_touch_pressed(touch.position, touch.index):
						return false
					mobile_ui_touch_target = piece_palette
				else:
					mobile_ui_touch_target = _mobile_text_edit_at(touch.position)
					if mobile_ui_touch_target != null:
						(mobile_ui_touch_target as TextEdit).grab_focus()
			if mobile_ui_touch_target == null:
				return false
			mobile_ui_pointer = touch.index
			get_viewport().set_input_as_handled()
			return true
		if touch.index != mobile_ui_pointer:
			return false
		if mobile_ui_touch_target == piece_palette:
			if interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
				interaction._input(touch)
			piece_palette.handle_mobile_touch_released(touch.index, touch.position)
		elif mobile_ui_touch_target is Button:
			var button := mobile_ui_touch_target as Button
			if not button.disabled and button.get_global_rect().has_point(touch.position):
				var callback: Callable = mobile_button_callbacks.get(button, Callable())
				if callback.is_valid():
					callback.call()
				else:
					button.pressed.emit()
		mobile_ui_pointer = -1
		mobile_ui_touch_target = null
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != mobile_ui_pointer:
			return false
		if mobile_ui_touch_target == piece_palette:
			piece_palette.handle_mobile_touch_drag(drag.position, drag.index)
			if interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
				interaction._input(drag)
		get_viewport().set_input_as_handled()
		return true
	return false

func _mobile_button_at(position: Vector2) -> Button:
	for candidate: Button in mobile_button_callbacks:
		if candidate.is_visible_in_tree() and candidate.get_global_rect().has_point(position):
			return candidate
	var report_panel_node := report_panel if report_panel != null else get_node_or_null("SandboxLayer/GameIssueReportPanel")
	if report_panel_node != null and report_panel_node.visible:
		for child in report_panel_node.find_children("*", "Button", true, false):
			var candidate := child as Button
			if candidate.is_visible_in_tree() and not candidate.disabled and candidate.get_global_rect().has_point(position):
				return candidate
	if mobile_layout:
		for candidate in $SandboxLayer.find_children("*", "Button", true, false):
			var button := candidate as Button
			if piece_palette != null and piece_palette.is_ancestor_of(button):
				continue
			if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(position):
				return button
	var presentation_adapter: Node = game.get_node_or_null("ChessPresentationAdapter")
	var archer_draw_button := presentation_adapter.get("archer_draw_button") as Button if presentation_adapter != null else null
	if archer_draw_button != null and archer_draw_button.is_visible_in_tree() and archer_draw_button.get_global_rect().has_point(position):
		return archer_draw_button
	var grant_panel := game.get_node_or_null("LunacyLayer/LunacyUI/MovementGrantPanel")
	if grant_panel != null:
		for child in grant_panel.find_children("*", "Button", true, false):
			var candidate := child as Button
			if candidate.is_visible_in_tree() and candidate.get_global_rect().has_point(position):
				return candidate
	var promotion_panel := game.get_node_or_null("LunacyLayer/LunacyUI/PromotionPanel")
	if promotion_panel != null:
		for child in promotion_panel.find_children("*", "Button", true, false):
			var candidate := child as Button
			if candidate.is_visible_in_tree() and not candidate.disabled and candidate.get_global_rect().has_point(position):
				return candidate
	return null

func _mobile_text_edit_at(position: Vector2) -> TextEdit:
	if not mobile_layout:
		return null
	for candidate in $SandboxLayer.find_children("*", "TextEdit", true, false):
		var edit := candidate as TextEdit
		if edit.is_visible_in_tree() and edit.get_global_rect().has_point(position):
			return edit
	return null

func _route_mobile_board_touch(event: InputEvent) -> bool:
	var board := $ChessGame/CanvasLayer/ChessBoard as ChessBoardView
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if mobile_board_pointer >= 0:
				return false
			var coordinate := board.coordinate_at_viewport_position(touch.position)
			if coordinate.x < 0:
				return false
			if piece_palette != null and piece_palette.king_picker != null:
				piece_palette.king_picker.visible = false
			mobile_board_pointer = touch.index
			if mode == Mode.EDIT:
				interaction._input(touch)
				interaction._on_square_pressed(coordinate)
			else:
				board.select_square_at_viewport_position(touch.position)
			get_viewport().set_input_as_handled()
			return true
		if touch.index != mobile_board_pointer:
			return false
		if mode == Mode.EDIT and interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
			interaction._input(touch)
		mobile_board_pointer = -1
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != mobile_board_pointer:
			return false
		if mode == Mode.EDIT and interaction.drag_source != BoardEditorInteraction.DragSource.NONE:
			interaction._input(drag)
		get_viewport().set_input_as_handled()
		return true
	return false


func _release_text_focus_if_scene_clicked(hovered_control: Control) -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if _is_text_input(focus_owner) and hovered_control == null:
		_release_gui_focus()


func _is_text_input(control: Control) -> bool:
	return control is LineEdit or control is TextEdit


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		if key_event.keycode == KEY_ESCAPE and mode == Mode.EDIT:
			_release_gui_focus()
			_restore_cursor_tool()
			get_viewport().set_input_as_handled()
			return
		if _is_text_input(focus_owner):
			return

	match key_event.keycode:
		KEY_LEFT:
			if not undo_button.disabled:
				undo()
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if not redo_button.disabled:
				redo()
				get_viewport().set_input_as_handled()
		KEY_P:
			if not mode_button.disabled:
				_set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT)
				get_viewport().set_input_as_handled()
		KEY_R:
			if not reset_button.disabled:
				reset()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if mode == Mode.EDIT:
				_restore_cursor_tool()
				get_viewport().set_input_as_handled()

func _restore_cursor_tool() -> void:
	interaction.cancel_drag()
	editor.select_cursor_tool()


func _toggle_viewing_side() -> void:
	if not model.is_settled():
		return
	_restore_cursor_tool()
	var board_view: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	game.set_viewing_color("black" if board_view.viewing_color == "white" else "white")
	_refresh_control_states()

func _add_ai_mode_button(parent: Control, label: String, value: ChessCpuPlayer.ExecutionMode) -> void:
	var button := _add_button_to(parent, label, func(): _configure_ai(value))
	button.toggle_mode = true
	ai_mode_buttons[value] = button

func _add_ai_side_button(parent: Control, label: String, color: String) -> void:
	var button := _add_button_to(parent, label, func(): _toggle_ai_side(color))
	button.toggle_mode = true
	ai_side_buttons[color] = button

func _add_labeled_control(label_text: String, control: Control) -> void:
	_add_labeled_control_to(panel, label_text, control)


func _add_labeled_control_to(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 76.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)

func _make_compact_labeled_control(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _make_grip_spin_box() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -256.0
	spin.max_value = 256.0
	spin.step = 1.0
	spin.allow_lesser = true
	spin.allow_greater = true
	return spin

func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("d8c6a0"))
	panel.add_child(label)

func _add_button(label: String, callback: Callable) -> Button:
	return _add_button_to(panel, label, callback)

func _add_button_to(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	_style_button(button, false, COLOR_INACTIVE)
	if mobile_layout:
		mobile_button_callbacks[button] = callback
		_enable_mobile_touch_activation(button)
	return button

func _enable_mobile_touch_activation(button: Button) -> void:
	if button == null or button.has_meta(&"mobile_touch_enabled"):
		return
	button.set_meta(&"mobile_touch_enabled", true)
	button.gui_input.connect(func(event: InputEvent):
		if not event is InputEventScreenTouch:
			return
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			button.set_meta(&"mobile_touch_index", touch.index)
			button.accept_event()
			return
		if int(button.get_meta(&"mobile_touch_index", -1)) != touch.index:
			return
		button.set_meta(&"mobile_touch_index", -1)
		button.accept_event()
		if not button.disabled and Rect2(Vector2.ZERO, button.size).has_point(touch.position):
			button.pressed.emit()
	)

func _set_mode(next: Mode) -> void:
	if replay_mode:
		return
	if _any_cpu_thinking():
		return
	if not model.is_settled():
		return
	if next == Mode.PLAY and not _brain_configuration_error().is_empty():
		_refresh_control_states()
		return
	if mobile_layout and mode == Mode.EDIT and next == Mode.PLAY:
		mobile_ai_visible_before_play = mobile_ai_panel.visible
	mode = next
	if mobile_layout:
		_apply_mobile_mode_visibility()
	if mode != Mode.EDIT and visibility_check != null:
		visibility_check.set_pressed_no_signal(false)
		_clear_visibility_overlay()
	editor.set_enabled(mode == Mode.EDIT)
	if piece_palette != null:
		piece_palette.set_palette_enabled(mode == Mode.EDIT)
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()
	if mode == Mode.PLAY:
		model.resolve_unplayable_turns()

func _apply_mobile_mode_visibility() -> void:
	if not mobile_layout or mobile_toolbar_panel == null:
		return
	var toolbar := mobile_toolbar_panel.get_child(0) as HBoxContainer
	for child in toolbar.get_children():
		if child is Control:
			(child as Control).visible = child == mode_button or mode == Mode.EDIT
	if piece_palette != null:
		piece_palette.visible = mode == Mode.EDIT
		if piece_palette.king_picker != null and mode == Mode.PLAY:
			piece_palette.king_picker.visible = false
	if mobile_ai_panel != null:
		mobile_ai_panel.visible = mobile_ai_visible_before_play if mode == Mode.EDIT else false
	_layout_mobile_controls()

func _on_edit_committed(_before: ChessPosition, after: ChessPosition, label: String) -> void:
	if not restoring_history:
		_invalidate_flag_on_history_branch()
		history.push(after, label, {"kind": &"edit", "context": _capture_record_context()})
	_refresh_record_panel()
	_refresh_control_states()

func _on_settled_action_completed() -> void:
	_clear_ai_thoughts()
	if mode == Mode.PLAY and not restoring_history and not replay_mode:
		var label: String = ActionCodec.label(pending_action)
		_invalidate_flag_on_history_branch()
		history.push(model.capture_position(), label, {
			"kind": &"gameplay", "action": pending_action.duplicate(true),
			"transition": &"action" if not pending_action.is_empty() else &"forced_pass",
			"selections": pending_selections.duplicate(true),
			"ai": pending_ai.duplicate(true), "context": _capture_record_context(),
		})
		pending_action.clear()
		pending_ai.clear()
		pending_selections.clear()
	_refresh_record_panel()
	_refresh_control_states()

func _on_primary_action_committed(descriptor: Dictionary) -> void:
	if not replay_mode and not replay_analysis_running:
		pending_selections.clear()
		pending_action = descriptor.duplicate(true)

func _on_authoritative_selection_committed(kind: StringName, option: Variant) -> void:
	if replay_mode or replay_analysis_running:
		return
	pending_selections.append({"kind": String(kind), "option": _encode_record_value(option)})

func _invalidate_flag_on_history_branch() -> void:
	if active_record != null and active_record.flagged_frame > history.cursor:
		active_record.flagged_frame = -1

func _on_ai_thought_changed(thought) -> void:
	if thought == null or replay_mode or replay_analysis_running: return
	pending_ai = thought.to_dictionary()
	var cpu := game.white_cpu_player if thought.color == "white" else game.black_cpu_player
	pending_ai["pre_decision_context"] = _compact_cpu_context(cpu.last_pre_decision_context)

func _on_board_rebuilt(_board: Array) -> void:
	_clear_ai_thoughts()
	call_deferred("_refresh_visibility_overlay")
	_refresh_control_states()

func undo() -> void:
	if not _can_navigate_live_history(): return
	_restore(history.undo())

func redo() -> void:
	if not _can_navigate_live_history(): return
	_restore(history.redo())

func reset() -> void:
	if not _can_navigate_live_history(): return
	_restore(history.get_baseline())
	if baseline != null:
		history.establish_baseline(baseline, "Baseline", {"kind": &"baseline", "context": _capture_record_context()})

func _restore(position: ChessPosition) -> void:
	if position == null or not _can_navigate_live_history():
		return
	var keep_cooldowns_disabled := model.active_ability_cooldowns_disabled
	restoring_history = true
	model.load_position(position)
	model.set_active_ability_cooldowns_disabled(keep_cooldowns_disabled)
	restoring_history = false
	_refresh_control_states()

func _any_cpu_thinking() -> bool:
	return game.white_cpu_player.is_thinking or game.black_cpu_player.is_thinking

func _can_navigate_live_history() -> bool:
	return mode == Mode.EDIT and not replay_mode and model.is_settled() and not _any_cpu_thinking()

func _on_preset_selected(index: int) -> void:
	var position := ChessPositionPresets.normal_start()
	if index == 1:
		position = ChessPositionPresets.empty()
	if index == 2:
		position = ChessPositionPresets.debug_layout()
	if not editor.editor_enabled:
		_set_mode(Mode.EDIT)
	restoring_history = true
	model.load_position(position)
	restoring_history = false
	baseline = model.capture_position()
	history.establish_baseline(baseline, "Preset", {"kind": &"baseline", "context": _capture_record_context()})
	editor.select_cursor_tool()
	_refresh_control_states()

func _toggle_ai_side(color: String) -> void:
	ai_sides[color] = not ai_sides[color]
	_clear_ai_thoughts()
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()

func _configure_ai(next_mode: ChessCpuPlayer.ExecutionMode) -> void:
	if next_mode != ChessCpuPlayer.ExecutionMode.DISABLED and not _brain_configuration_error(next_mode).is_empty():
		_refresh_control_states()
		return
	ai_mode = next_mode
	_clear_ai_thoughts()
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()

func _apply_ai_configuration() -> void:
	game.white_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "white")
	game.black_cpu_player.configure_mode(ChessCpuPlayer.ExecutionMode.DISABLED, "black")
	game.white_cpu_player.set_brain(ai_brains.white)
	game.black_cpu_player.set_brain(ai_brains.black)
	if mode != Mode.PLAY or ai_mode == ChessCpuPlayer.ExecutionMode.DISABLED:
		return
	for color in ["white", "black"]:
		if ai_sides[color]:
			var cpu := game.white_cpu_player if color == "white" else game.black_cpu_player
			cpu.set_random_seed(seed_value)
			cpu.configure_mode(ai_mode, color)


func _add_brain_selector(parent: Control, label_text: String, color: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 76.0
	row.add_child(label)
	var option := OptionButton.new()
	option.add_item("Ryck", ChessCpuPlayer.BrainKind.RYCK)
	option.add_item("LeMay", ChessCpuPlayer.BrainKind.LEMAY)
	option.add_item("Dupre", ChessCpuPlayer.BrainKind.DUPRE)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(index: int): _on_brain_selected(color, option.get_item_id(index)))
	row.add_child(option)
	parent.add_child(row)
	ai_brain_options[color] = option


func _on_brain_selected(color: String, kind: ChessCpuPlayer.BrainKind) -> void:
	ai_brains[color] = kind
	_clear_ai_thoughts()
	_apply_ai_configuration()
	_apply_play_control()
	_refresh_control_states()


func _add_authority_selector(parent: Control) -> void:
	var option := OptionButton.new()
	option.add_item("Pure Core", ChessBoardModel.LiveAuthority.CLASSIC_CORE)
	option.tooltip_text = "Pure Core is the authoritative live-rules engine"
	option.disabled = true
	authority_options.append(option)
	_add_labeled_control_to(parent, "Rules", option)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(status)
	authority_status_labels.append(status)


func _brain_configuration_error(requested_mode: int = -1) -> String:
	if requested_mode < 0:
		requested_mode = ai_mode
	if requested_mode == ChessCpuPlayer.ExecutionMode.DISABLED:
		return ""
	var unsupported: Array[StringName] = []
	for color in ["white", "black"]:
		if not ai_sides.get(color, false):
			continue
		var brain: ChessCpuPlayer.BrainKind = ai_brains.get(color, ChessCpuPlayer.BrainKind.DUPRE)
		var rejected: Array[StringName] = []
		if brain == ChessCpuPlayer.BrainKind.LEMAY:
			rejected = LeMayAiBrain.unsupported_king_ids(model)
		elif brain == ChessCpuPlayer.BrainKind.DUPRE:
			rejected = DupreAiBrain.unsupported_king_ids(model)
		for type_id in rejected:
			if type_id not in unsupported:
				unsupported.append(type_id)
	if unsupported.is_empty():
		return ""
	var labels := PackedStringArray()
	for type_id in unsupported:
		labels.append(String(type_id))
	return "Selected tactical brain unavailable: unsupported King layer%s %s" % ["s" if labels.size() != 1 else "", ", ".join(labels)]

func _apply_play_control() -> void:
	var colors: Array[String] = []
	if mode == Mode.PLAY:
		colors.assign(["white", "black"])
		if ai_mode != ChessCpuPlayer.ExecutionMode.DISABLED:
			for color in ["white", "black"]:
				if ai_sides[color]:
					colors.erase(color)
	game_controller.configure_player_controlled_colors(colors)

func _manual_cpu() -> ChessCpuPlayer:
	if not ai_sides.get(model.current_turn, false):
		return null
	return game.white_cpu_player if model.current_turn == "white" else game.black_cpu_player

func think_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		await cpu.think()
	_refresh_control_states()

func execute_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		await cpu.execute_thought()
	_refresh_control_states()

func step_ai() -> void:
	var cpu := _manual_cpu()
	if mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and cpu != null:
		await cpu.step()
	_refresh_control_states()

func _on_seed_changed(value: float) -> void:
	seed_value = int(value)
	game.white_cpu_player.set_random_seed(seed_value)
	game.black_cpu_player.set_random_seed(seed_value)
	_refresh_control_states()

func _capture_record_context() -> Dictionary:
	return {
		"ai_mode": ai_mode, "ai_sides": ai_sides.duplicate(true), "seed": seed_value,
		"white": _compact_cpu_context(game.white_cpu_player.capture_debug_context()),
		"black": _compact_cpu_context(game.black_cpu_player.capture_debug_context()),
	}

func _compact_cpu_context(source: Dictionary) -> Dictionary:
	return {
		"brain": String(source.get("brain", "")),
		"brain_kind": int(source.get("brain_kind", 0)),
		"color": String(source.get("color", "")),
		"rng_state": String(source.get("rng_state", "0")),
		"king_safety_turns": int(source.get("king_safety_turns", 0)),
	}

func _compact_record_ai(source: Dictionary, include_diagnostics: bool) -> Dictionary:
	if source.is_empty(): return {}
	var result := source.duplicate(true)
	if result.get("performance", {}).is_empty():
		result["performance"] = PerformanceTelemetry.from_search_profile(result.get("search_profile", {}))
	result["pre_decision_context"] = _compact_cpu_context(result.get("pre_decision_context", {}))
	if not include_diagnostics:
		result.erase("search_profile")
		result.erase("candidates")
	return result

func _record_from_history():
	active_record.frames.clear()
	if active_record.flagged_frame >= history.entries.size():
		active_record.flagged_frame = -1
	active_record.provenance = record_provenance.duplicate(true)
	for index in range(history.entries.size()):
		var meta: Dictionary = history.metadata[index] if index < history.metadata.size() else {}
		var keep_diagnostics: bool = active_record.flagged_frame >= 0 and absi(index - active_record.flagged_frame) <= 1
		active_record.frames.append({
			"position": history.entries[index].copy(), "label": history.labels[index],
			"kind": meta.get("kind", &"gameplay"), "action": meta.get("action", {}).duplicate(true),
			"transition": meta.get("transition", &"action" if not meta.get("action", {}).is_empty() else &"snapshot"),
			"selections": meta.get("selections", []).duplicate(true),
			"ai": _compact_record_ai(meta.get("ai", {}), keep_diagnostics), "context": meta.get("context", {}).duplicate(true),
		})
	return active_record

func import_record_text(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		_set_record_error("Selected file does not contain valid JSON.")
		return false
	if json.data.get("schema", "") == "crpg_chess_position":
		var decoded := ChessPositionCodec.from_dictionary(json.data)
		if decoded.position == null:
			_set_record_error("Position import failed: %s" % "; ".join(decoded.errors))
			return false
		_start_live_from_position(decoded.position, "Imported position")
		return true
	var decoded_record: Dictionary = GameRecordCodec.from_dictionary(json.data)
	if decoded_record.record == null:
		_set_record_error("Game import failed: %s" % "; ".join(decoded_record.errors))
		return false
	_enter_replay(decoded_record.record, decoded_record.warnings)
	return true

func _enter_replay(record, warnings: Array) -> void:
	_stop_replay_playback()
	if replay_compatibility_label != null: replay_compatibility_label.text = ""
	replay_record = record
	replay_mode = true
	replay_warnings.assign(warnings)
	replay_cursor = clampi(record.flagged_frame if record.flagged_frame >= 0 else 0, 0, record.frames.size() - 1)
	mode = Mode.EDIT
	_apply_ai_configuration()
	editor.set_enabled(false)
	if piece_palette != null: piece_palette.set_palette_enabled(false)
	_load_replay_frame(replay_cursor)
	record_note_edit.set_text(record.issue_note)
	record_status_label.text = "\n".join(warnings) if not warnings.is_empty() else "Replay loaded."
	_refresh_record_panel()

func _load_replay_frame(index: int) -> void:
	if replay_record == null or index < 0 or index >= replay_record.frames.size() or not model.is_settled() or replay_playing: return
	replay_cursor = index
	restoring_history = true
	model.load_position((replay_record.frames[index].position as ChessPosition).copy())
	restoring_history = false
	_refresh_record_panel()

func _replay_previous() -> void:
	_load_replay_frame(replay_cursor - 1)

func _replay_next() -> void:
	_load_replay_frame(replay_cursor + 1)

func _is_replay_turn(index: int) -> bool:
	if replay_record == null or index <= 0 or index >= replay_record.frames.size(): return false
	var frame: Dictionary = replay_record.frames[index]
	return not frame.get("action", {}).is_empty() or StringName(frame.get("transition", &"snapshot")) == &"forced_pass"

func _first_replay_turn_index() -> int:
	if replay_record == null: return -1
	for index in range(1, replay_record.frames.size()):
		if _is_replay_turn(index): return index
	return -1

func _next_replay_turn_index(after_index: int) -> int:
	if replay_record == null: return -1
	for index in range(maxi(1, after_index + 1), replay_record.frames.size()):
		if _is_replay_turn(index): return index
	return -1

func _previous_replay_turn_index(before_index: int) -> int:
	if replay_record == null: return -1
	for index in range(before_index - 1, 0, -1):
		if _is_replay_turn(index): return index
	var first := _first_replay_turn_index()
	return first - 1 if first > 0 and before_index >= first else -1

func _watch_replay_from_start() -> void:
	if replay_record == null or replay_playing: return
	var first := _first_replay_turn_index()
	if first < 0: return
	_load_replay_frame(first - 1)
	if mobile_layout:
		_enter_mobile_watch_mode()
	_start_replay_playback()

func _enter_mobile_watch_mode() -> void:
	mobile_watch_mode = true
	record_panel.visible = false
	report_panel.visible = false
	mobile_toolbar_panel.visible = false
	mobile_ai_panel.visible = false
	piece_palette.visible = false
	mobile_watch_controls.visible = true
	_refresh_mobile_watch_controls()

func _exit_mobile_watch_mode() -> void:
	if not mobile_watch_mode: return
	if replay_playing:
		replay_pause_requested = true
	mobile_watch_mode = false
	mobile_watch_controls.visible = false
	mobile_toolbar_panel.visible = true
	record_panel.visible = true
	_refresh_record_panel()

func _refresh_mobile_watch_controls() -> void:
	if mobile_watch_controls == null: return
	mobile_watch_play_button.icon = mobile_watch_pause_icon if replay_playing else mobile_watch_play_icon
	mobile_watch_play_button.tooltip_text = "Pause replay" if replay_playing else "Play replay"
	mobile_watch_play_button.disabled = replay_pause_requested or (not replay_playing and _next_replay_turn_index(replay_cursor) < 0)
	mobile_watch_previous_button.disabled = replay_playing or _previous_replay_turn_index(replay_cursor) < 0
	mobile_watch_next_button.disabled = replay_playing or _next_replay_turn_index(replay_cursor) < 0

func _toggle_replay_playback() -> void:
	if replay_playing:
		replay_pause_requested = true
		_refresh_record_panel()
	else:
		_start_replay_playback()

func _start_replay_playback() -> void:
	if replay_record == null or replay_playing: return
	replay_playing = true
	replay_pause_requested = false
	game_controller.configure_player_controlled_colors([])
	_refresh_record_panel()
	while replay_playing:
		var next := _next_replay_turn_index(replay_cursor)
		if next < 0: break
		await _play_replay_turn(next)
		if replay_pause_requested: break
	_stop_replay_playback()

func _stop_replay_playback() -> void:
	replay_playing = false
	replay_pause_requested = false
	replay_selection_queue.clear()
	if replay_mode:
		game_controller.configure_player_controlled_colors([])
	_refresh_record_panel()

func _replay_previous_turn() -> void:
	if not replay_mode or replay_playing: return
	var previous := _previous_replay_turn_index(replay_cursor)
	if previous >= 0: _load_replay_frame(previous)

func _replay_next_turn() -> void:
	if not replay_mode or replay_playing: return
	var next := _next_replay_turn_index(replay_cursor)
	if next < 0: return
	replay_playing = true
	game_controller.configure_player_controlled_colors([])
	_refresh_record_panel()
	await _play_replay_turn(next)
	_stop_replay_playback()

func _play_replay_turn(target_index: int) -> void:
	if replay_record == null or target_index <= 0 or target_index >= replay_record.frames.size(): return
	if replay_compatibility_label != null:
		replay_compatibility_label.text = ""
	var source_index := target_index - 1
	# A turn may follow setup/edit snapshots that are not themselves theatrical.
	if replay_cursor != source_index:
		var was_playing := replay_playing
		replay_playing = false
		_load_replay_frame(source_index)
		replay_playing = was_playing
	var validation := _validate_replay_turn(source_index, target_index)
	if not bool(validation.get("ok", false)):
		_replay_snapshot_fallback(target_index, String(validation.get("error", "Recorded transition is not executable.")))
		return
	var frame: Dictionary = replay_record.frames[target_index]
	replay_selection_queue.assign(frame.get("selections", []).duplicate(true))
	var accepted := false
	if StringName(frame.get("transition", &"action")) == &"forced_pass":
		accepted = await model.resolve_unplayable_turns()
	else:
		accepted = await _execute_recorded_action(frame.get("action", {}))
	if accepted and not model.is_settled():
		await model.settled_action_completed
	if not accepted or not model.is_settled():
		_replay_snapshot_fallback(target_index, "The live model rejected the recorded turn.")
		return
	var expected: ChessPosition = frame.get("position")
	if _canonical_position(model.capture_position()) != _canonical_position(expected):
		_replay_snapshot_fallback(target_index, "The animated result differed from the recorded position. %s" % _position_difference_summary(expected, model.capture_position()))
		return
	replay_cursor = target_index
	replay_selection_queue.clear()
	_refresh_record_panel()

func _execute_recorded_action(raw: Dictionary) -> bool:
	var descriptor := _normalized_action_descriptor(raw)
	var piece: ModelPiece = model.find_piece_by_id(String(descriptor.get("piece_id", "")))
	if piece == null: return false
	var matching: ChessPrimaryAction
	for candidate in model.get_legal_primary_actions(model.current_turn):
		if candidate.piece == piece and candidate.kind == int(descriptor.kind) and candidate.target == descriptor.target and candidate.path == descriptor.path:
			matching = candidate
			break
	if matching == null: return false
	match matching.kind:
		ChessPrimaryAction.Kind.MOVE:
			return await model.submit_move_path(piece, matching.path) if matching.path.size() > 1 else await model.submit_move(piece, matching.target)
		ChessPrimaryAction.Kind.ACTIVE_ABILITY:
			return await model.submit_active_ability(piece as KingPiece, matching.target)
		ChessPrimaryAction.Kind.ARCHER_CHARGE:
			return await model.submit_archer_charge(piece as ArcherKing)
	return false

func _validate_replay_turn(source_index: int, target_index: int) -> Dictionary:
	var source: ChessPosition = replay_record.frames[source_index].get("position")
	var target: ChessPosition = replay_record.frames[target_index].get("position")
	var imported: Dictionary = PureCore.import_position(source)
	if not bool(imported.get("ok", false)):
		return {"ok": false, "error": "The recorded source position is unsupported by the current rules."}
	var frame: Dictionary = replay_record.frames[target_index]
	var result
	if StringName(frame.get("transition", &"action")) == &"forced_pass":
		result = PureCore.resolve_forced_passes(imported.state, false)
	else:
		var descriptor := _normalized_action_descriptor(frame.get("action", {}))
		var submitted: CoreAction
		for candidate in PureCore.legal_actions(imported.state, imported.state.current_turn):
			if candidate.kind == int(descriptor.get("kind", -1)) and candidate.piece_id == String(descriptor.get("piece_id", "")) and candidate.from == descriptor.from and candidate.target == descriptor.target and candidate.path == descriptor.path:
				submitted = candidate
				break
		if submitted == null:
			return {"ok": false, "error": "The recorded action is no longer legal."}
		result = PureCore.resolve_action(imported.state, submitted, false)
	var selections: Array = frame.get("selections", [])
	var selection_index := 0
	while result.status == CoreStepResult.Status.PENDING_CHOICE:
		if result.choice == null or selection_index >= selections.size():
			return {"ok": false, "error": "This recording does not contain every secondary choice."}
		var selection: Dictionary = selections[selection_index]
		if StringName(selection.get("kind", &"")) != result.choice.kind:
			return {"ok": false, "error": "A recorded secondary choice no longer matches the rules."}
		var option: Variant = _decode_record_value(selection.get("option"))
		if option not in result.choice.options:
			return {"ok": false, "error": "A recorded secondary choice is no longer legal."}
		result = PureCore.resolve_choice(result.state, option, false)
		selection_index += 1
	if result.status != CoreStepResult.Status.COMPLETED or selection_index != selections.size():
		return {"ok": false, "error": "The recorded turn did not settle cleanly."}
	var actual: ChessPosition = PureCore.export_position(result.state)
	if _canonical_position(actual) != _canonical_position(target):
		return {
			"ok": false,
			"error": "Current rules produce a different result for this recorded turn. %s" % _position_difference_summary(target, actual),
		}
	return {"ok": true}

func _replay_snapshot_fallback(target_index: int, reason: String) -> void:
	replay_selection_queue.clear()
	if reason not in replay_warnings: replay_warnings.append(reason)
	replay_playing = false
	_load_replay_frame(target_index)
	replay_playing = true
	if replay_compatibility_label != null:
		replay_compatibility_label.text = "Compatibility fallback: %s" % reason

func _normalized_action_descriptor(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result["from"] = _decode_coordinate(raw.get("from", [-1, -1]))
	result["target"] = _decode_coordinate(raw.get("target", [-1, -1]))
	var path: Array[Vector2i] = []
	for value in raw.get("path", []): path.append(_decode_coordinate(value))
	result["path"] = path
	return result

func _canonical_position(position: ChessPosition) -> String:
	if position == null:
		return ""
	var dictionary := ChessPositionCodec.to_dictionary(position)
	# The allocator cursor is replay infrastructure rather than board state.
	# Generated IDs themselves remain part of the comparison.
	dictionary.erase("next_state_id")
	return JSON.stringify(_canonical_comparison_value(dictionary))

func _canonical_comparison_value(value):
	if value is float and is_equal_approx(value, roundf(value)):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _canonical_comparison_value(value[key])
		return result
	if value is Array:
		return value.map(func(item): return _canonical_comparison_value(item))
	return value

func _position_difference_summary(expected: ChessPosition, actual: ChessPosition) -> String:
	if expected == null or actual == null:
		return "One position was unavailable."
	var differences: Array[String] = []
	var expected_dictionary := ChessPositionCodec.to_dictionary(expected)
	var actual_dictionary := ChessPositionCodec.to_dictionary(actual)
	expected_dictionary.erase("next_state_id")
	actual_dictionary.erase("next_state_id")
	_collect_value_differences(
		expected_dictionary,
		actual_dictionary,
		"position",
		differences,
		3
	)
	return "Difference: %s" % "; ".join(differences) if not differences.is_empty() else "Canonical encodings differed."

func _collect_value_differences(expected, actual, path: String, differences: Array[String], limit: int) -> void:
	if differences.size() >= limit:
		return
	if typeof(expected) != typeof(actual):
		differences.append("%s expected %s, got %s" % [path, str(expected), str(actual)])
		return
	if expected is Dictionary:
		var keys: Array = expected.keys()
		for key in actual.keys():
			if key not in keys:
				keys.append(key)
		keys.sort_custom(func(a, b): return String(a) < String(b))
		for key in keys:
			if differences.size() >= limit:
				return
			var child_path := "%s.%s" % [path, key]
			if not expected.has(key):
				differences.append("%s was added as %s" % [child_path, str(actual[key])])
			elif not actual.has(key):
				differences.append("%s expected %s, but was absent" % [child_path, str(expected[key])])
			else:
				_collect_value_differences(expected[key], actual[key], child_path, differences, limit)
		return
	if expected is Array:
		if expected.size() != actual.size():
			differences.append("%s expected %d items, got %d" % [path, expected.size(), actual.size()])
			return
		for index in range(expected.size()):
			_collect_value_differences(expected[index], actual[index], "%s[%d]" % [path, index], differences, limit)
			if differences.size() >= limit:
				return
		return
	if expected != actual:
		differences.append("%s expected %s, got %s" % [path, str(expected), str(actual)])

func _encode_record_value(value: Variant) -> Variant:
	if value is Vector2i: return [value.x, value.y]
	if value is StringName: return String(value)
	return value

func _decode_record_value(value: Variant) -> Variant:
	if value is Array and value.size() == 2: return Vector2i(int(value[0]), int(value[1]))
	return StringName(value) if value is String else value

func _decode_coordinate(value: Variant) -> Vector2i:
	if value is Vector2i: return value
	if value is Array and value.size() == 2: return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)

func _take_replay_selection(kind: StringName, options: Array) -> Variant:
	if replay_selection_queue.is_empty(): return options[0] if not options.is_empty() else null
	var selection: Dictionary = replay_selection_queue.pop_front()
	var option: Variant = _decode_record_value(selection.get("option"))
	if StringName(selection.get("kind", &"")) != kind or option not in options:
		return options[0] if not options.is_empty() else null
	return option

func _on_replay_promotion_requested(_pawn: ModelPiece, options: Array[StringName]) -> void:
	if not replay_playing: return
	var option: Variant = _take_replay_selection(&"promotion", options)
	if option != null: model.call_deferred(&"submit_promotion_selection", option)

func _on_replay_movement_grant_requested(_king: QuarterlyInitiativeKing, _target: ModelPiece, options: Array[StringName]) -> void:
	if not replay_playing: return
	var option: Variant = _take_replay_selection(&"movement_type_grant", options)
	if option != null: model.call_deferred(&"submit_movement_type_grant", option)

func _on_replay_reaction_requested(_piece: ModelPiece, _action_type: String, targets: Array) -> void:
	if not replay_playing: return
	var kind := StringName(replay_selection_queue[0].get("kind", &"")) if not replay_selection_queue.is_empty() else &"raise_dead"
	var option: Variant = _take_replay_selection(kind, targets)
	if option != null: model.call_deferred(&"submit_reaction_selection", option)

func _flag_replay_frame() -> void:
	var record = replay_record if replay_mode else active_record
	if record == null: return
	var cursor: int = replay_cursor if replay_mode else history.cursor
	if cursor < 0: return
	record.flagged_frame = -1 if record.flagged_frame == cursor else cursor
	_refresh_record_panel()

func _on_record_note_changed() -> void:
	var record = replay_record if replay_mode else active_record
	if record != null: record.issue_note = record_note_edit.text

func fork_replay_here() -> void:
	if replay_record == null: return
	var parent_id: String = replay_record.record_id
	var parent_frame := replay_cursor
	var position: ChessPosition = replay_record.frames[replay_cursor].position
	replay_mode = false
	replay_record = null
	replay_warnings.clear()
	record_provenance = {"parent_record_id": parent_id, "parent_frame": parent_frame}
	_start_live_from_position(position, "Forked replay frame %d" % (parent_frame + 1))
	record_status_label.text = "Forked frame %d into a new live recording." % (parent_frame + 1)

func _start_live_from_position(position: ChessPosition, label: String) -> void:
	replay_mode = false
	replay_warnings.clear()
	restoring_history = true
	model.load_position(position.copy())
	restoring_history = false
	baseline = model.capture_position()
	history.establish_baseline(baseline, label, {"kind": &"baseline", "context": _capture_record_context()})
	active_record = GameRecordScript.new()
	_apply_ai_configuration()
	editor.set_enabled(true)
	if piece_palette != null: piece_palette.set_palette_enabled(true)
	_refresh_record_panel()

func analyze_replay_again() -> void:
	if replay_record == null or replay_cursor <= 0: return
	var recorded_ai: Dictionary = replay_record.frames[replay_cursor].get("ai", {})
	if recorded_ai.is_empty():
		record_status_label.text = "This frame has no recorded AI decision."
		return
	replay_analysis_running = true
	var shown_position: ChessPosition = replay_record.frames[replay_cursor].position
	restoring_history = true
	model.load_position((replay_record.frames[replay_cursor - 1].position as ChessPosition).copy())
	restoring_history = false
	var color := String(recorded_ai.get("color", model.current_turn))
	var cpu := game.white_cpu_player if color == "white" else game.black_cpu_player
	var previous_enabled: bool = cpu.is_enabled
	var previous_execution_mode: int = cpu.execution_mode
	var previous_color: String = cpu.controlled_color
	var previous_rng_state: int = cpu.rng.state
	var previous_safety: int = cpu.king_safety_turns_remaining
	# Replay deliberately disables both players. Temporarily make only the chosen
	# player think without calling configure_mode(), which would reset its brain.
	cpu.is_enabled = true
	cpu.execution_mode = ChessCpuPlayer.ExecutionMode.MANUAL
	cpu.controlled_color = color
	var recorded_context: Dictionary = recorded_ai.get("pre_decision_context", {})
	if not recorded_context.is_empty():
		cpu.rng.state = int(String(recorded_context.get("rng_state", previous_rng_state)))
		cpu.king_safety_turns_remaining = int(recorded_context.get("king_safety_turns", previous_safety))
	var current = await cpu.think()
	var recorded_target = recorded_ai.get("selected", {}).get("target", [])
	var current_target: Array = [current.target.x, current.target.y] if current != null else []
	cpu.rng.state = previous_rng_state
	cpu.king_safety_turns_remaining = previous_safety
	cpu.controlled_color = previous_color
	cpu.execution_mode = previous_execution_mode
	cpu.is_enabled = previous_enabled
	restoring_history = true
	model.load_position(shown_position.copy())
	restoring_history = false
	replay_analysis_running = false
	pending_action.clear()
	pending_ai.clear()
	record_status_label.text = "Recorded target: %s\nCurrent %s target: %s%s" % [recorded_target, cpu.get_brain_name(), current_target, " (same)" if recorded_target == current_target else " (changed)"]

func _save_game_record_file(path: String) -> void:
	var final_path: String = path if path.ends_with(".crpggame") else path + ".crpggame"
	var record = replay_record if replay_mode else _record_from_history()
	if record_save_clean:
		record = record.copy()
		record.clear_issue_report()
	var error: Error = GameRecordCodec.save_file(record, final_path)
	record_status_label.text = "Saved: %s" % final_path if error == OK else "Save failed (%s)." % error

func _open_game_record_file(path: String) -> void:
	var decoded: Dictionary = GameRecordCodec.load_file(path)
	if decoded.record == null:
		_set_record_error("Open failed: %s" % "; ".join(decoded.errors))
		return
	_enter_replay(decoded.record, decoded.warnings)

func _set_record_error(message: String) -> void:
	if record_status_label != null: record_status_label.text = message

func _set_speed(speed: int) -> void:
	var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
	adapter.set_presentation_speed(speed)
	_refresh_control_states()

func _on_grip_toggled(enabled: bool) -> void:
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.show_piece_grip_anchors = enabled
	_refresh_control_states()

func _on_cooldowns_toggled(disabled: bool) -> void:
	model.set_active_ability_cooldowns_disabled(disabled)
	_clear_ai_thoughts()
	_refresh_control_states()

func _on_visibility_toggled(enabled: bool) -> void:
	if not enabled or mode != Mode.EDIT:
		_clear_visibility_overlay()
		_refresh_control_states()
		return
	_refresh_visibility_overlay()
	_refresh_control_states()

func _on_visibility_threshold_changed(_value: float) -> void:
	_refresh_visibility_overlay()

func _on_visibility_square_entered(coordinate: Vector2i) -> void:
	if visibility_check == null or not visibility_check.button_pressed or mode != Mode.EDIT:
		return
	_show_visibility_overlay(coordinate)

func _on_visibility_square_exited(coordinate: Vector2i) -> void:
	if visibility_check != null and visibility_check.button_pressed and mode == Mode.EDIT:
		call_deferred("_refresh_visibility_overlay")

func _refresh_visibility_overlay() -> void:
	if visibility_check == null or not visibility_check.button_pressed or mode != Mode.EDIT:
		return
	if model.is_in_bounds(interaction.hovered.x, interaction.hovered.y):
		_show_visibility_overlay(interaction.hovered)
	else:
		_clear_visibility_overlay()

func _show_visibility_overlay(origin: Vector2i) -> void:
	var cutoff := visibility_threshold_spin.value if visibility_threshold_spin != null else ChessLineOfSight.DEFAULT_VISIBILITY_THRESHOLD
	var visibility := model.get_visibility_map(origin, cutoff)
	var visible_coordinates: Array = visibility.keys()
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.show_visibility_overlay(visible_coordinates)

func _clear_visibility_overlay() -> void:
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.clear_visibility_overlay()

func _selected_grip_profile() -> PieceArtProfile:
	if grip_profile_option == null or grip_profile_option.selected < 0 or grip_profile_option.selected >= grip_profile_ids.size():
		return null
	return PieceView.PIECE_ART_PROFILES.get(grip_profile_ids[grip_profile_option.selected]) as PieceArtProfile

func _load_grip_profile_controls(index: int) -> void:
	if index < 0 or index >= grip_profile_ids.size():
		return
	grip_profile_option.select(index)
	var profile := _selected_grip_profile()
	if profile == null:
		return
	syncing_grip_controls = true
	grip_x_spin.set_value_no_signal(profile.grip_anchor.x)
	grip_y_spin.set_value_no_signal(profile.grip_anchor.y)
	syncing_grip_controls = false
	grip_status_label.text = profile.resource_path

func _apply_live_piece_grip() -> void:
	if syncing_grip_controls:
		return
	var profile := _selected_grip_profile()
	if profile == null:
		return
	profile.grip_anchor = Vector2(grip_x_spin.value, grip_y_spin.value)
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	board.show_piece_grip_anchors = true
	for piece in board.get_node("Pieces").get_children():
		if piece is PieceView and piece.art_profile == profile:
			piece.refresh_grip_anchor_from_profile()
	grip_check.set_pressed_no_signal(true)
	grip_status_label.text = "Unsaved: %s" % profile.resource_path

func _save_piece_grip() -> void:
	var profile := _selected_grip_profile()
	if profile == null or profile.resource_path.is_empty():
		grip_status_label.text = "Save failed: profile has no resource path"
		return
	var error := ResourceSaver.save(profile, profile.resource_path)
	grip_status_label.text = "Saved: %s" % profile.resource_path if error == OK else "Save failed (%s): %s" % [error, profile.resource_path]

func _clear_ai_thoughts() -> void:
	game.white_cpu_player.clear_thought()
	game.black_cpu_player.clear_thought()

func _refresh_control_states() -> void:
	if mode_button == null:
		return
	var settled := model.is_settled()
	var ai_thinking := _any_cpu_thinking()
	var editing := mode == Mode.EDIT and settled and not replay_mode and not ai_thinking
	if mobile_layout:
		mode_button.text = "Edit" if mode == Mode.EDIT else "Play"
	else:
		mode_button.text = "Mode: Edit [P]" if mode == Mode.EDIT else "Mode: Play [P]"
	mode_button.disabled = not settled or replay_mode or ai_thinking
	_style_button(mode_button, true, COLOR_EDIT if mode == Mode.EDIT else COLOR_PLAY)
	var board: ChessBoardView = $ChessGame/CanvasLayer/ChessBoard
	if view_side_button != null:
		view_side_button.text = "View: White" if board.viewing_color == "white" else "View: Black"
		view_side_button.disabled = not settled
		_style_button(view_side_button, true, COLOR_WHITE_SIDE if board.viewing_color == "white" else COLOR_BLACK_SIDE, board.viewing_color == "white")
	undo_button.disabled = not editing or not history.can_undo()
	redo_button.disabled = not editing or not history.can_redo()
	reset_button.disabled = not editing or not history.can_undo()
	clear_button.disabled = not editing
	if preset_option != null:
		preset_option.disabled = replay_mode or not settled
	if turn_option != null:
		turn_option.disabled = not editing
	for value in ai_mode_buttons:
		ai_mode_buttons[value].disabled = replay_mode or not settled
		var active: bool = value == ai_mode
		var color := Color("67626f")
		if value == ChessCpuPlayer.ExecutionMode.AUTO:
			color = COLOR_AUTO
		elif value == ChessCpuPlayer.ExecutionMode.MANUAL:
			color = COLOR_MANUAL
		ai_mode_buttons[value].set_pressed_no_signal(active)
		_style_button(ai_mode_buttons[value], active, color)
	for color_name in ai_side_buttons:
		ai_side_buttons[color_name].disabled = replay_mode or not settled
		var active: bool = ai_sides[color_name]
		ai_side_buttons[color_name].set_pressed_no_signal(active)
		_style_button(ai_side_buttons[color_name], active, COLOR_WHITE_SIDE if color_name == "white" else COLOR_BLACK_SIDE, color_name == "white")
	var unsupported_lemay := not LeMayAiBrain.unsupported_king_ids(model).is_empty()
	var unsupported_dupre := not DupreAiBrain.unsupported_king_ids(model).is_empty()
	for color_name in ai_brain_options:
		var option: OptionButton = ai_brain_options[color_name]
		option.disabled = replay_mode or not settled
		option.set_item_disabled(1, unsupported_lemay)
		option.set_item_disabled(2, unsupported_dupre)
		option.select(option.get_item_index(int(ai_brains[color_name])))
	if ai_brain_status_label != null:
		var brain_error := _brain_configuration_error()
		ai_brain_status_label.text = brain_error
		ai_brain_status_label.modulate = Color("e87568") if not brain_error.is_empty() else Color("9a96a3")
	var authority_diagnostics := model.get_live_authority_diagnostics()
	for option in authority_options:
		option.disabled = true
		option.select(option.get_item_index(model.requested_live_authority))
	for status in authority_status_labels:
		var active_authority := String(authority_diagnostics.active)
		var fallback := String(authority_diagnostics.fallback_reason)
		status.text = "Active: Pure Core"
		if not fallback.is_empty(): status.text += "\nFallback: " + fallback
		status.modulate = Color("e87568") if not fallback.is_empty() else (COLOR_CYAN if active_authority == "classic_core" else Color("9a96a3"))
	if speed_slider != null:
		var adapter: ChessPresentationAdapter = $ChessGame/ChessPresentationAdapter
		var speed: int = adapter.presentation_policy.speed
		speed_slider.set_value_no_signal(speed)
		var speed_names := ["Ultra Slow", "Slow", "Normal", "Fast", "Instant"]
		var speed_colors := [COLOR_ULTRA_SLOW, COLOR_SLOW, COLOR_EDIT, COLOR_MANUAL, COLOR_INSTANT]
		speed_value_label.text = speed_names[speed]
		speed_value_label.add_theme_color_override("font_color", speed_colors[speed])
	cooldowns_check.set_pressed_no_signal(model.active_ability_cooldowns_disabled)
	cooldowns_check.add_theme_color_override("font_color", COLOR_CYAN if model.active_ability_cooldowns_disabled else Color.WHITE)
	if grip_check != null:
		grip_check.set_pressed_no_signal(board.show_piece_grip_anchors)
		grip_check.add_theme_color_override("font_color", COLOR_CYAN if board.show_piece_grip_anchors else Color.WHITE)
	if visibility_check != null:
		visibility_check.disabled = not editing
		visibility_check.add_theme_color_override("font_color", COLOR_CYAN if visibility_check.button_pressed else Color.WHITE)
	if visibility_threshold_spin != null:
		visibility_threshold_spin.editable = editing
	if turn_option != null:
		turn_option.select(0 if model.current_turn == "white" else 1)
	piece_palette.set_palette_enabled(editing)
	piece_palette.sync_selection(editor.selected_tool, editor.selected_type_id, editor.selected_color)
	if grip_profile_option != null:
		grip_profile_option.disabled = not settled
		grip_x_spin.editable = settled
		grip_y_spin.editable = settled
		grip_save_button.disabled = not settled
	var manual_ai_available := not replay_mode and mode == Mode.PLAY and ai_mode == ChessCpuPlayer.ExecutionMode.MANUAL and _manual_cpu() != null and settled and not model.battle_over
	if think_button != null:
		think_button.disabled = not manual_ai_available
		step_button.disabled = not manual_ai_available
		_refresh_thought_state()
	_sync_disabled_focus_states()

func _refresh_thought_state() -> void:
	if execute_button == null or thought_label == null:
		return
	var cpu := _manual_cpu()
	var thought = cpu.get_last_thought() if cpu != null else null
	var valid: bool = thought != null and thought.model_revision == model.position_revision and thought.color == model.current_turn
	execute_button.disabled = not valid or mode != Mode.PLAY or ai_mode != ChessCpuPlayer.ExecutionMode.MANUAL
	if not valid:
		thought_label.text = "No prepared action"
		thought_label.add_theme_color_override("font_color", Color("9a96a3"))
		return
	var kind := "Move" if thought.action_kind == ChessPrimaryAction.Kind.MOVE else "Ability"
	thought_label.text = "%s • %s: %s %s → %s • %.1f%s" % [
		String(thought.brain_id).capitalize(),
		kind,
		thought.piece_type_id,
		thought.piece_coordinate,
		thought.target,
		thought.score,
		" • %d leaves" % thought.analyzed_leaf_count if thought.analyzed_leaf_count > 0 else "",
	]
	thought_label.add_theme_color_override("font_color", COLOR_MANUAL)

func _style_button(button: Button, active: bool, color: Color, dark_text := false) -> void:
	var background := color if active else COLOR_INACTIVE
	var normal := StyleBoxFlat.new()
	normal.bg_color = background
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = color if active else Color("494553")
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", normal)
	var hover := normal.duplicate()
	hover.bg_color = background.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var disabled_style := normal.duplicate()
	disabled_style.bg_color = Color("36353a")
	disabled_style.border_color = Color("494553")
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_color", Color("181620") if active and dark_text else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("181620") if active and dark_text else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("85818b"))

func _sync_disabled_focus_states() -> void:
	var controls: Array[Control] = [
		mode_button, view_side_button, undo_button, redo_button, reset_button, clear_button,
		think_button, execute_button, step_button,
		preset_option, turn_option,
	]
	for button in ai_mode_buttons.values():
		controls.append(button)
	for button in ai_side_buttons.values():
		controls.append(button)
	for control in controls:
		if control == null:
			continue
		var disabled: bool = control.get("disabled")
		if disabled:
			control.release_focus()
			control.focus_mode = Control.FOCUS_NONE
		else:
			control.focus_mode = Control.FOCUS_ALL
