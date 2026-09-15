# Dialogue presentation characterization

Run the static dialogue-view checks with:

```sh
"/Users/max/Desktop/crpg/Godot 4.app/Contents/MacOS/Godot" --headless --path . tests/dialogue/dialogue_view_characterization.tscn
```

Open `res://tools/dev_dialogue/dialogue_lab.tscn` in Godot to review the layout.
Use the lab controls to switch portrait, identity, content, and placement states.
Resize the window to check integer scale transitions, narrow layouts, and wide
layouts. This milestone intentionally uses plain grayscale placeholder styling;
it does not implement reveal timing, authored tags, or dialogue audio.
