extends Node

const MAIN := preload("res://scenes/main.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var main := MAIN.instantiate() as GameFlow
	main.transition_duration = 0.0
	add_child(main)
	await get_tree().process_frame

	var presentation_layer := main.get_node("DialoguePresentationLayer") as CanvasLayer
	var transition_layer := main.get_node("TransitionLayer") as CanvasLayer
	_check(main.dialogue_presenter.get_parent() == presentation_layer and presentation_layer.layer < transition_layer.layer, "Main owns the shared presenter above gameplay and below fades")
	var profile := main.active_overworld.npc.encounter_profile
	_check(profile.pre_battle_dialogue_path == "res://content/dialogue/hood_greeting.dialog", "forest encounter references the authored Hood conversation")
	_check(profile.player_win_dialogue_path == "res://content/dialogue/hood_player_win.dialog" and profile.rematch_dialogue_path == "res://content/dialogue/hood_rematch.dialog", "forest encounter owns its authored result and rematch conversations")
	var left_statue := main.active_overworld.get_inspectable_at(Vector2i(6, 2))
	main.active_overworld.player.configure(main.active_overworld.collision_grid, main.active_overworld.npc, left_statue.get_grid_cell() + Vector2i.DOWN, Vector2i.UP)
	main.dialogue_presenter.session_runner.set_instant_text(true)
	main.active_overworld._begin_inspection(left_statue)
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "forest_king_statue", "inspection opens the marker's authored dialogue through the shared presenter")
	_check(main.active_overworld.player.movement_state == OverworldPlayer.MovementState.INPUT_LOCKED, "inspection locks overworld movement")
	_check(not main.dialogue_presenter.dialogue_view.speaker_label.visible and not main.dialogue_presenter.dialogue_view.empty_portrait.visible, "inspection leaves the nameplate and portrait panels empty")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	await get_tree().process_frame
	_check(main.active_overworld.player.is_grid_idle() and not main.dialogue_pending, "finishing inspection restores overworld movement")

	main.active_overworld.player.configure(main.active_overworld.collision_grid, main.active_overworld.npc, Vector2i(5, 5), Vector2i.RIGHT)
	main.active_overworld._begin_challenge_dialogue()
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_greeting", "initial interaction opens Hood's authored conversation")
	_check(main.active_battle == null and main.active_overworld.player.movement_state == OverworldPlayer.MovementState.INPUT_LOCKED, "dialogue locks exploration and gates battle creation")

	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	var timeout := 60
	while main.active_battle == null and timeout > 0:
		await get_tree().process_frame
		timeout -= 1
	_check(timeout > 0 and main.active_overworld == null, "final dialogue confirmation releases the overworld-to-battle transition")
	_check(is_instance_valid(main.dialogue_presenter) and main.dialogue_presenter.get_parent() == presentation_layer, "presenter persists for future dialogue over chess scenes")

	if main.active_battle != null and main.active_battle.opening_in_progress:
		main.active_battle.opening_director.finish_immediately()
		await get_tree().process_frame
	await main._transition_to_overworld("win")
	await get_tree().process_frame
	_check(main.active_overworld != null and main.active_battle == null, "battle flow returns to the overworld")
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_player_win", "player victory opens Hood's authored result conversation")
	_check(main.active_overworld.player.movement_state == OverworldPlayer.MovementState.INPUT_LOCKED, "result dialogue locks exploration")
	_check(main.active_overworld.get_player_cell() == Vector2i(5, 5) and main.active_overworld.get_player_facing() == Vector2i.RIGHT, "dialogue-gated battle preserves overworld position and facing")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	await get_tree().process_frame
	_check(main.active_overworld.player.movement_state != OverworldPlayer.MovementState.INPUT_LOCKED, "finishing result dialogue restores exploration")

	main.active_overworld._begin_challenge_dialogue()
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_rematch", "later interaction opens the authored rematch choice")
	while not main.dialogue_presenter.session_runner.choices_are_active():
		main.dialogue_presenter.confirm()
	main.dialogue_presenter.move_choice(1)
	main.dialogue_presenter.confirm()
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_rematch_decline", "No branches to Hood's decline response")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	await get_tree().process_frame
	_check(main.active_battle == null and main.active_overworld.player.movement_state != OverworldPlayer.MovementState.INPUT_LOCKED, "decline response returns to exploration without starting battle")

	main.active_overworld._begin_challenge_dialogue()
	await get_tree().process_frame
	while not main.dialogue_presenter.session_runner.choices_are_active():
		main.dialogue_presenter.confirm()
	main.dialogue_presenter.confirm()
	await get_tree().process_frame
	_check(main.dialogue_presenter.active and main.dialogue_presenter.conversation.id == "hood_rematch_accept", "Yes branches to Hood's acceptance response")
	while main.dialogue_presenter.active:
		main.dialogue_presenter.confirm()
	timeout = 60
	while main.active_battle == null and timeout > 0:
		await get_tree().process_frame
		timeout -= 1
	_check(timeout > 0 and main.active_overworld == null, "battle starts only after the accepted response finishes")

	main.dialogue_presenter.stop()
	main.queue_free()
	for _cleanup_frame in range(4):
		await get_tree().process_frame
	if failures.is_empty():
		print("DIALOGUE GAME FLOW CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE GAME FLOW FAILURE: ", failure)
		get_tree().quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
