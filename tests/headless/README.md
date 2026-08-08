# Headless model characterization

This suite constructs `ChessBoardModel` directly, without adding it to the scene
tree and without creating a View or Controller.

```sh
godot --headless --path . tests/headless/headless_model_characterization.tscn
```

It covers explicit/idempotent initialization, validated move and ability
commands, immediate completion of unobserved presentation gates, headless
Minotaur Rage, Model-owned Raise Dead decisions, invalid decision rejection,
and battle completion using only Model state and commands.
