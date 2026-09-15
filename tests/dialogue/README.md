# Dialogue presentation characterization

Run the static dialogue-view checks with:

```sh
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_view_characterization.tscn
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_parser_characterization.tscn
```

Open `res://tools/dev_dialogue/dialogue_lab.tscn` in Godot to review the layout.
Use the lab controls to switch portrait, identity, content, and placement states.
Resize the window to check integer scale transitions, narrow layouts, and wide
layouts. This milestone intentionally uses plain grayscale placeholder styling;
it does not implement reveal timing, authored tags, or dialogue audio.

The provisional skin is `res://assets/ui/dialogue/dialogue_skin_provisional.tres`.
Its panel and plaque slots accept any `StyleBox`, including future nine-sliced
`StyleBoxTexture` assets. It also exposes optional textures for the text interior,
empty portrait, and continue indicator, plus fonts and logical spacing values.

The lab parses `res://content/dialogue/hood_authoring_demo.dialogue`. Page and
portrait-state selectors demonstrate ordered pages and expression events without
simulating progressive reveal. See `docs/dialogue_authoring_format.md` for the
grammar and visible-character indexing rules.
