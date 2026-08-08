# Headless model characterization

This suite constructs `ChessBoardModel` directly, without adding it to the scene
tree and without creating a View or Controller.

```sh
godot --headless --path . tests/headless/headless_model_characterization.tscn
godot --headless --path . tests/headless/cpu_player_characterization.tscn
```

It covers explicit/idempotent initialization, validated move and ability
commands, immediate completion of unobserved presentation gates, headless
Minotaur Rage, Model-owned Raise Dead decisions, invalid decision rejection,
nonlethal attacks with no presentation subscriber, and battle completion using
only Model state and commands. Raise Dead coverage includes empty death squares
created by effects, occupied death squares created by captures, and immediate
expiration after a Bone Pawn is summoned on its terminal rank. Charge coverage
distinguishes adjacent landings against surviving kings from lethal captures.

The CPU suite covers the shared authoritative primary-action list, heuristic
selection and randomized top-score ties, active abilities, and CPU-owned versus
human-owned reaction choices without constructing a View or Controller. It also
composes one shared-script CPU instance per color to verify alternating turns,
reaction ownership, and battle-completion shutdown.
