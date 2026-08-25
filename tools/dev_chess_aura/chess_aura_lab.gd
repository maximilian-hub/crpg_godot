# DEV PRESENTATION COMPARISON TOOL
# Compares three reusable Chess Energy treatments without entering the game flow.

extends Node2D

const PIECE_SCENE := preload("res://scenes/piece.tscn")
const HAND_STYLE := preload("res://assets/arms/player/skeleton_hand_style.tres")
const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")

var aura_profile: ChessAuraProfile
var king_aura: ChessAura2D
var hand_aura: ChessAura2D
var target_selector: OptionButton
var mode_selector: OptionButton
var power_slider: HSlider
var value_labels: Dictionary = {}


func _ready() -> void:
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	aura_profile = AuraProfile.new()
	_build_stage()
	_build_controls()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("11131d"))
	for row in range(4):
		for column in range(8):
			var color := Color("292d3c") if (row + column) % 2 == 0 else Color("1d2130")
			draw_rect(Rect2(Vector2(300 + column * 120, 520 + row * 62), Vector2(120, 62)), color)
	draw_string(ThemeDB.fallback_font, Vector2(430, 455), "AUTHORED KING", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("d8d9e8"))
	draw_string(ThemeDB.fallback_font, Vector2(950, 455), "LAYERED HAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("d8d9e8"))


func _build_stage() -> void:
	var king := PIECE_SCENE.instantiate() as PieceView
	king.name = "AuraKing"
	king.position = Vector2(570, 700)
	king.scale = Vector2.ONE * 2.5
	king.set_model(MinotaurKing.new("white", Vector2i.ZERO))
	add_child(king)

	var hand_root := Node2D.new()
	hand_root.name = "AuraHand"
	hand_root.position = Vector2(1080, 650)
	hand_root.scale = Vector2.ONE * 1.8
	add_child(hand_root)
	var hand_sprites: Array[Sprite2D] = []
	for entry in [
		{"name": "RearFingers", "texture": HAND_STYLE.open_rear_fingers, "z": 1},
		{"name": "Thumb", "texture": HAND_STYLE.open_thumb, "z": 3},
		{"name": "Arm", "texture": HAND_STYLE.open_arm, "z": 4},
	]:
		var sprite := Sprite2D.new()
		sprite.name = entry["name"]
		sprite.texture = entry["texture"]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(sprite.texture.get_size()) * 0.5 - Vector2(48, 118)
		sprite.z_index = entry["z"]
		hand_root.add_child(sprite)
		hand_sprites.append(sprite)

	king_aura = Aura.new() as ChessAura2D
	king_aura.name = "KingAura"
	king_aura.profile = aura_profile
	add_child(king_aura)
	king_aura.bind_targets([king.sprite])
	hand_aura = Aura.new() as ChessAura2D
	hand_aura.name = "HandAura"
	hand_aura.profile = aura_profile
	add_child(hand_aura)
	hand_aura.bind_targets(hand_sprites)


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(310, 0)
	add_child(panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	panel.add_child(controls)
	var title := Label.new()
	title.text = "Chess Aura Lab"
	title.add_theme_font_size_override("font_size", 22)
	controls.add_child(title)

	mode_selector = _add_option(controls, "Treatment", ["Silhouette Resonance", "Chess-Square Flame", "Hybrid Soulfire"])
	mode_selector.select(Aura.AuraMode.HYBRID)
	mode_selector.item_selected.connect(_set_mode)
	target_selector = _add_option(controls, "Target", ["Both", "King", "Hand"])

	var color_row := HBoxContainer.new()
	controls.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "Core / Accent"
	color_label.custom_minimum_size.x = 120
	color_row.add_child(color_label)
	for property_name in [&"core_color", &"accent_color"]:
		var picker := ColorPickerButton.new()
		picker.color = aura_profile.get(property_name)
		picker.custom_minimum_size = Vector2(72, 28)
		picker.color_changed.connect(func(color: Color): aura_profile.set(property_name, color))
		color_row.add_child(picker)

	power_slider = _add_slider(controls, "Power", 0.0, 1.0, 0.01, aura_profile.idle_power, func(value: float):
		for aura in _selected_auras(): aura.set_power(value)
	)
	_add_slider(controls, "Rise speed", 0.0, 120.0, 1.0, aura_profile.rise_speed, func(value: float): aura_profile.rise_speed = value)
	_add_slider(controls, "Spread", 0.0, 100.0, 1.0, aura_profile.horizontal_spread, func(value: float): aura_profile.horizontal_spread = value)
	_add_slider(controls, "Density", 0.0, 120.0, 1.0, aura_profile.square_density, func(value: float): aura_profile.square_density = value)
	_add_slider(controls, "Square size", 1.0, 6.0, 0.5, aura_profile.square_size, func(value: float): aura_profile.square_size = value)

	var buttons := HBoxContainer.new()
	controls.add_child(buttons)
	for entry in [
		{"label": "Power Up", "callable": _power_up},
		{"label": "Sustain", "callable": _sustain},
		{"label": "Power Down", "callable": _power_down},
		{"label": "Reset", "callable": _reset},
	]:
		var button := Button.new()
		button.text = entry["label"]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry["callable"])
		buttons.add_child(button)


func _add_option(parent: Control, label_text: String, options: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 120
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text in options:
		option.add_item(text)
	row.add_child(option)
	return option


func _add_slider(parent: Control, label_text: String, minimum: float, maximum: float, step: float, initial: float, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 88
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = str(initial)
	value_label.custom_minimum_size.x = 48
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		callback.call(value)
	)
	return slider


func _selected_auras() -> Array[ChessAura2D]:
	match target_selector.selected:
		1:
			return [king_aura]
		2:
			return [hand_aura]
		_:
			return [king_aura, hand_aura]


func _set_mode(selected: int) -> void:
	king_aura.set_mode(selected)
	hand_aura.set_mode(selected)


func _power_up() -> void:
	for aura in _selected_auras():
		aura.power_up()
	power_slider.set_value_no_signal(1.0)


func _sustain() -> void:
	for aura in _selected_auras():
		aura.set_power(1.0)
	power_slider.set_value_no_signal(1.0)


func _power_down() -> void:
	for aura in _selected_auras():
		aura.power_down()
	power_slider.set_value_no_signal(0.0)


func _reset() -> void:
	for aura in [king_aura, hand_aura]:
		aura.reset_effect()
	power_slider.set_value_no_signal(aura_profile.idle_power)

