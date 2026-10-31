extends Node

const QuiescencePolicy := preload("res://scripts/ai/dupre_quiescence_policy.gd")
const TacticalMap := preload("res://scripts/ai/dupre_tactical_map.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_ordinary_moves()
	_test_arakne_damage()
	_test_minotaur_charge_and_self_stun()
	_test_rhetorician_forced_movement()
	_test_necromancer_summons()
	_test_positional_and_scheduled_abilities()
	if failures.is_empty():
		print("DUPRE QUIESCENCE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_ordinary_moves() -> void:
	var model := _empty_model()
	var rook := Rook.new("white", Vector2i(4, 4))
	var pawn := Pawn.new("black", Vector2i(4, 3))
	_add(model, [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), rook, pawn])
	var tactical := TacticalMap.from_model(model)
	var capture := QuiescencePolicy.classify(model, ChessPrimaryAction.new(ChessPrimaryAction.Kind.MOVE, rook, pawn.coordinate), tactical)
	var quiet := QuiescencePolicy.classify(model, ChessPrimaryAction.new(ChessPrimaryAction.Kind.MOVE, rook, Vector2i(5, 4)), tactical)
	_expect(int(capture.category) == QuiescencePolicy.Category.TACTICAL and capture.reason == &"ordinary_capture", "lethal ordinary captures extend quiescence")
	_expect(int(quiet.category) == QuiescencePolicy.Category.QUIET, "quiet ordinary moves do not extend quiescence")
	model.free()


func _test_arakne_damage() -> void:
	var model := _empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var enemy := ClassicKing.new("black", Vector2i(5, 5))
	_add(model, [arakne, enemy])
	arakne.set_cooldown(0)
	var result := _classify_ability(model, arakne, enemy.coordinate)
	_expect(int(result.category) == QuiescencePolicy.Category.CRITICAL and result.reason == &"king_damage", "Arakne King damage is a critical extension")
	model.free()


func _test_minotaur_charge_and_self_stun() -> void:
	var model := _empty_model()
	var minotaur := MinotaurKing.new("white", Vector2i(4, 4))
	var queen := Queen.new("black", Vector2i(4, 0))
	_add(model, [minotaur, ClassicKing.new("black", Vector2i(0, 7)), queen])
	var charge := _classify_ability(model, minotaur, queen.coordinate)
	var wall_stun := _classify_ability(model, minotaur, Vector2i(4, 1))
	_expect(int(charge.category) == QuiescencePolicy.Category.TACTICAL and charge.reason == &"lethal_material_damage", "lethal Minotaur material damage extends quiescence")
	_expect(int(wall_stun.category) == QuiescencePolicy.Category.QUIET, "Minotaur self-stun does not extend quiescence")
	model.free()


func _test_rhetorician_forced_movement() -> void:
	var model := _empty_model()
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4))
	var compelled := Pawn.new("black", Vector2i(4, 2))
	_add(model, [rhetorician, ClassicKing.new("black", Vector2i(0, 7)), compelled])
	var quiet := _classify_ability(model, rhetorician, compelled.coordinate)
	var victim := Rook.new("black", Vector2i(4, 3))
	model.add_piece(victim, victim.coordinate)
	var capture := _classify_ability(model, rhetorician, compelled.coordinate)
	_expect(int(quiet.category) == QuiescencePolicy.Category.QUIET, "harmless Rhetorician displacement does not extend quiescence")
	_expect(int(capture.category) == QuiescencePolicy.Category.TACTICAL and capture.reason == &"forced_material_capture", "Rhetorician forced material capture extends quiescence")
	model.free()


func _test_necromancer_summons() -> void:
	var quiet_model := _empty_model()
	var quiet_necro := NecromancerKing.new("white", Vector2i(7, 4))
	_add(quiet_model, [quiet_necro, ClassicKing.new("black", Vector2i(0, 7))])
	var quiet := _classify_ability(quiet_model, quiet_necro, Vector2i(6, 4))
	_expect(int(quiet.category) == QuiescencePolicy.Category.QUIET, "ordinary Bone Pawn summon does not extend quiescence")
	quiet_model.free()

	var danger_model := _empty_model()
	var danger_necro := NecromancerKing.new("white", Vector2i(7, 4))
	_add(danger_model, [danger_necro, ClassicKing.new("black", Vector2i(0, 7)), Rook.new("black", Vector2i(0, 4))])
	var block := _classify_ability(danger_model, danger_necro, Vector2i(6, 4))
	_expect(int(block.category) == QuiescencePolicy.Category.CRITICAL and block.reason == &"emergency_king_block", "Bone Pawn that removes a current King attacker is a critical extension")
	danger_model.free()


func _test_positional_and_scheduled_abilities() -> void:
	var quarterly_model := _empty_model()
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 4))
	var rook := Rook.new("white", Vector2i(6, 4))
	_add(quarterly_model, [quarterly, ClassicKing.new("black", Vector2i(0, 7)), rook])
	var grant := _classify_ability(quarterly_model, quarterly, rook.coordinate)
	_expect(int(grant.category) == QuiescencePolicy.Category.QUIET and grant.reason == &"positional_ability", "Quarterly movement grant stays outside quiescence")
	quarterly_model.free()

	var cannon_model := _empty_model()
	var cannon := CannonKing.new("white", Vector2i(7, 4))
	_add(cannon_model, [cannon, ClassicKing.new("black", Vector2i(0, 4))])
	var mortar := _classify_ability(cannon_model, cannon, Vector2i(0, 4))
	_expect(int(mortar.category) == QuiescencePolicy.Category.QUIET and mortar.reason == &"positional_ability", "scheduled Cannon mortar stays outside quiescence")
	cannon_model.free()


func _classify_ability(model: ChessBoardModel, king: KingPiece, target: Vector2i) -> Dictionary:
	var action := ChessPrimaryAction.new(ChessPrimaryAction.Kind.ACTIVE_ABILITY, king, target)
	return QuiescencePolicy.classify(model, action, TacticalMap.from_model(model))


func _empty_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	model.current_turn = "white"
	return model


func _add(model: ChessBoardModel, pieces: Array) -> void:
	for piece in pieces: model.add_piece(piece, piece.coordinate)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
