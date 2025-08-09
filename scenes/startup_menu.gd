extends Control

@onready var friend_button = $VBoxContainer/FriendButton
@onready var cpu_button = $VBoxContainer/CpuButton
@onready var white_king_option_button = $VBoxContainer/WhiteKingOptionButton
@onready var black_king_option_button = $VBoxContainer/BlackKingOptionButton
@onready var start_game_button = $VBoxContainer/StartGameButton

const KING_TYPES = {
	"Classic": preload("res://scripts/pieces/classic_king.gd"),
	"Minotaur": preload("res://scripts/pieces/minotaur_king.gd"),
	"Necromancer": preload("res://scripts/pieces/necromancer_king.gd"),
	"Arakne": preload("res://scripts/pieces/arakne_king.gd")
}

func _ready():
	friend_button.pressed.connect(_on_friend_button_pressed)
	cpu_button.pressed.connect(_on_cpu_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)

	for king_name in KING_TYPES:
		white_king_option_button.add_item(king_name)
		black_king_option_button.add_item(king_name)

	white_king_option_button.selected = 0
	black_king_option_button.selected = 0
	GameSettings.white_king = white_king_option_button.get_item_text(0)
	GameSettings.black_king = black_king_option_button.get_item_text(0)

func _on_friend_button_pressed():
	GameSettings.game_mode = "friend"
	friend_button.disabled = true
	cpu_button.disabled = false

func _on_cpu_button_pressed():
	GameSettings.game_mode = "cpu"
	friend_button.disabled = false
	cpu_button.disabled = true

func _on_start_game_button_pressed():
	GameSettings.white_king = white_king_option_button.get_item_text(white_king_option_button.selected)
	GameSettings.black_king = black_king_option_button.get_item_text(black_king_option_button.selected)
	get_tree().change_scene_to_file("res://scenes/chess_game.tscn")
