extends Node

const PRESENTER_SCENE := preload("res://scenes/ui/dialogue_presenter.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var presenter := PRESENTER_SCENE.instantiate() as DialoguePresenter
	add_child(presenter)
	_check(not presenter.active and not presenter.visible, "presenter starts inactive and hidden")
	var started := PackedStringArray()
	var finished := PackedStringArray()
	var failures_seen: Array = []
	presenter.conversation_started.connect(func(id: String): started.append(id))
	presenter.conversation_finished.connect(func(id: String): finished.append(id))
	presenter.conversation_failed.connect(func(path: String, errors: PackedStringArray): failures_seen.append([path, errors]))
	presenter.session_runner.set_instant_text(true)
	presenter.session_runner.set_voice_enabled(false)
	_check(presenter.start_file("res://content/dialogue/hood_greeting.dialog", DialogueView.Placement.BATTLE_FAR), "presenter parses and starts an authored conversation")
	_check(presenter.active and presenter.visible and presenter.dialogue_view.placement == DialogueView.Placement.BATTLE_FAR, "presenter exposes an active battle-safe placement")
	_check(started == PackedStringArray(["hood_greeting"]) and presenter.dialogue_view.speaker_label.text == "???", "presenter forwards lifecycle and applies unknown-speaker presentation")
	_check(presenter.dialogue_view.portrait_texture.texture != null and presenter.dialogue_view.portrait_texture.texture.resource_path.ends_with("hood_annoyed.png"), "presenter resolves the authored portrait through the speaker catalog")
	while presenter.active:
		presenter.confirm()
	_check(finished == PackedStringArray(["hood_greeting"]) and not presenter.visible, "final confirmation finishes and hides the conversation")
	_check(not presenter.start_file("res://content/dialogue/not_present.dialogue"), "missing dialogue fails without opening the presenter")
	_check(failures_seen.size() == 1 and failures_seen[0][0].ends_with("not_present.dialogue") and not failures_seen[0][1].is_empty(), "presenter reports actionable load failures")
	presenter.stop()
	await get_tree().process_frame
	presenter.free()

	if failures.is_empty():
		print("DIALOGUE PRESENTER CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DIALOGUE PRESENTER FAILURE: ", failure)
		get_tree().quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
