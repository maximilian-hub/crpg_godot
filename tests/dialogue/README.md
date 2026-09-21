# Dialogue presentation characterization

Run the static dialogue-view checks with:

```sh
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_view_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_parser_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_reveal_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_speaker_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_choice_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_session_runner_characterization.tscn
```

Open `res://tools/dev_dialogue/dialogue_lab.tscn` in Godot to review the layout.
Use the lab controls to switch portrait, identity, content, and placement states.
Resize the window to check integer scale transitions, narrow layouts, and wide
layouts. This milestone intentionally uses plain grayscale placeholder styling;
final decorative skin and dialogue voice assets are still intentionally absent.

The provisional skin is `res://assets/ui/dialogue/dialogue_skin_provisional.tres`.
Its panel and plaque slots accept any `StyleBox`, including future nine-sliced
`StyleBoxTexture` assets. It also exposes optional textures for the text interior,
empty portrait, and continue indicator, plus fonts and logical spacing values.

The Lab currently plays `res://content/dialogue/hood_greeting.dialog`; the older
`hood_authoring_demo.dialogue` remains a parser and presentation regression
fixture. Page and portrait-state selectors demonstrate ordered pages and
expression events without coupling them to gameplay. Reveal controls provide play/pause, restart, one
character stepping, immediate completion, two-stage confirm, player-speed
scaling, instant text, and character-voice request diagnostics. See
`docs/dialogue_authoring_format.md` for the grammar, speed spans, and
visible-character indexing rules.

The Ernest page demonstrates nested semantic color, capitalization, and
`small`/`large` font-size spans, plus a semantic `strong` jiggle. The status
panel reports the fully shaped text dimensions and marks content as `fits` or
`OVERFLOW`; it never auto-shrinks or silently paginates authored prose. Animated
text and reduced-motion toggles exercise the static accessibility paths.
For capture or automation, launch the Lab with `-- --dialogue-page=4` to select
that one-based page before its first frame.

`dialogue_speaker_characterization.tscn` verifies speaker/portrait catalog
resolution, silent and asset-pending voice profiles, deterministic pitch, the
whitespace eligibility policy, size-based voice volume, and the single loudest-
remaining blip emitted on immediate page completion.

`dialogue_choice_characterization.tscn` verifies empty, single, and multiple
choice pages; reveal gating; wrapping selection; neutral target and cancel
emission; ordered presentation cues; and optional choice sound slots. The Lab's
choice buttons and `move_left`, `move_right`, `interact`, and `back` actions expose
the same controller without executing story consequences.

`dialogue_session_runner_characterization.tscn` verifies the reusable runtime
boundary used by the Lab: ordered page starts, two-stage confirmation, choice
gating, one-shot neutral target emission, explicit post-choice continuation,
restart behavior, settings propagation, sound gating, and final conversation
completion. The runner does not interpret target IDs or depend on DialogueView.

Font controls compare the engine baseline with Pixel Operator 8, its bold-plaque
pairing, Pixel Operator Mono 8, and the non-8 Pixel Operator family at 8px and
16px logical sizes. The tested pixel-font imports disable antialiasing and
subpixel positioning, fix font oversampling at 1x, and render through the
DialogueView's nearest-filtered logical stage.
