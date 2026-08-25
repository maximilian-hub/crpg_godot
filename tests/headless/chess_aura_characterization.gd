extends Node

const Aura := preload("res://scripts/view/chess_aura_2d.gd")
const AuraProfile := preload("res://scripts/view/chess_aura_profile.gd")
const PIECE_SCENE := preload("res://scenes/piece.tscn")

var failures := 0


func _ready() -> void:
	var source := Sprite2D.new()
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(2, 1, 4, 6), Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	var original_material := CanvasItemMaterial.new()
	source.material = original_material
	add_child(source)
	var standard_white := PIECE_SCENE.instantiate() as PieceView
	standard_white.set_model(Pawn.new("white", Vector2i.ZERO))
	add_child(standard_white)
	var standard_white_material := standard_white.sprite.material
	var authored_white := PIECE_SCENE.instantiate() as PieceView
	authored_white.set_model(MinotaurKing.new("white", Vector2i.ZERO))
	add_child(authored_white)

	var profile := AuraProfile.new() as ChessAuraProfile
	profile.square_density = 500.0
	profile.square_lifetime = 1.0
	profile.random_seed = 42
	var aura := Aura.new() as ChessAura2D
	aura.profile = profile
	add_child(aura)
	aura.bind_targets([source, standard_white.sprite, authored_white.sprite])

	_check(source.material == original_material, "binding does not replace the source material")
	_check(standard_white.sprite.material == standard_white_material and standard_white_material is ShaderMaterial, "binding preserves the standard White palette shader")
	_check(authored_white.sprite.material == null, "binding preserves authored White art without adding a palette material")
	_check(aura.bindings.size() == 3, "one aura accepts multiple independently layered sprite targets")
	var binding: Dictionary = aura.bindings[0]
	var overlay := binding["overlay"] as Sprite2D
	var emitter := binding["emitter"] as ChessSquareEmitter2D
	_check(overlay.get_parent() == source and emitter.get_parent() == source, "overlay and square emitter inherit the source transform and depth band")
	_check(overlay.texture == source.texture and overlay.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "overlay mirrors the source texture with nearest filtering")
	_check(not emitter.opaque_points.is_empty(), "square flame caches opaque silhouette pixels")

	aura.set_mode(Aura.AuraMode.SILHOUETTE)
	_check(overlay.visible and not emitter.enabled, "Silhouette mode enables only the shader overlay")
	aura.set_mode(Aura.AuraMode.SQUARE_FLAME)
	_check(not overlay.visible and emitter.enabled, "Square Flame mode enables only chess-square motes")
	aura.set_mode(Aura.AuraMode.HYBRID)
	_check(overlay.visible and emitter.enabled, "Hybrid mode combines both renderers")

	aura.set_power(1.0)
	await get_tree().create_timer(0.05).timeout
	_check(is_equal_approx(aura.power, 1.0) and aura.active_particle_count() > 0, "full power drives the shader and emits square motes")
	aura.power_down(0.0)
	_check(is_zero_approx(aura.power), "zero-duration power-down reaches its exact terminal value")
	aura.reset_effect()
	_check(aura.active_particle_count() == 0, "reset clears residual motes")
	_check(source.material == original_material and source.texture != null, "power cycling leaves source presentation unchanged")

	if failures == 0:
		print("CHESS AURA CHARACTERIZATION: PASS")
	else:
		printerr("CHESS AURA CHARACTERIZATION: FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	failures += 1
	printerr("FAIL: ", description)
