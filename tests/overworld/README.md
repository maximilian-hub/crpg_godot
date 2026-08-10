# Overworld characterization

Run with Godot 4.4 or newer:

```sh
godot --headless --path . tests/overworld/overworld_characterization.tscn
```

The suite verifies physics-backed collision tiles, grid stepping and exact
alignment, latest-direction buffering, NPC dialogue gating, and that the
persistent main flow begins in the overworld.
