# Headless model characterization

This suite constructs `ChessBoardModel` directly, without adding it to the scene
tree and without creating a View or Controller.

```sh
godot --headless --path . tests/headless/headless_model_characterization.tscn
godot --headless --path . tests/headless/cpu_player_characterization.tscn
godot --headless --path . tests/headless/lemay_performance_characterization.tscn
godot --headless --path . tests/headless/dupre_characterization.tscn
godot --headless --path . tests/headless/dupre_match_characterization.tscn
```

It covers explicit/idempotent initialization, validated move and ability
commands, immediate completion of unobserved presentation gates, headless
Minotaur Rage, Model-owned Raise Dead decisions, invalid decision rejection,
nonlethal attacks with no presentation subscriber, and battle completion using
only Model state and commands. Raise Dead coverage includes empty death squares
created by effects, occupied death squares created by captures, and immediate
expiration after a Bone Pawn is summoned on its terminal rank. Charge coverage
distinguishes adjacent landings against surviving kings from lethal captures.

The CPU suite covers the shared authoritative primary-action list, the legacy
Ryck heuristic brain, and LeMay's exact budgeted two-ply search for Classic and
Arakne Kings. It verifies alpha-beta equivalence with exhaustive search,
timeouts, invalid simulations, active abilities, path-aware Skitter plans,
live-state isolation during search, and direct Ryck-versus-LeMay automatic play.
It also covers CPU-owned versus human-owned reactions, alternating turns,
reaction ownership, and battle-completion shutdown.

The LeMay performance suite prints permanent search counters for comparable
full-army LeMay and Dupre Classic/Arakne positions, including model loads, legal-action
generation, evaluation throughput, pruning, timeout status, and cooperative
main-thread slice duration.

The Dupre suites cover purposeful development, rook activity, move reversal,
hanging pieces, poisoned captures, explicit unverified fallback, immediate
victories, Spike Burst, path-aware Skitter, and fixed-seed color-reversed
controlled games against Ryck and LeMay.
