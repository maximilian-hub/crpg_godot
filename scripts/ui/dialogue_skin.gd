extends Resource
class_name DialogueSkin

@export_category("Replaceable presentation assets")
@export var text_panel_style: StyleBox
@export var portrait_panel_style: StyleBox
@export var name_plate_style: StyleBox
@export var text_interior_texture: Texture2D
@export var empty_portrait_texture: Texture2D
@export var continue_indicator_texture: Texture2D
@export var body_font: Font
@export var name_font: Font

@export_category("Logical layout")
@export var portrait_aspect_ratio := 0.75
@export var panel_height := 64
@export var panel_join_overlap := 2
@export var panel_inner_padding := 5
@export var portrait_inner_padding := 2
@export var name_plate_horizontal_offset := 4
@export var name_plate_size := Vector2i(92, 14)
@export var body_font_size := 8
@export var name_font_size := 8
@export var choice_font_size := 7

@export_category("Fallback colors")
@export var body_color := Color("f0eee8")
@export var name_color := Color("191b1e")
@export var choice_color := Color("d8c590")
@export var empty_portrait_color := Color("6f757b")
