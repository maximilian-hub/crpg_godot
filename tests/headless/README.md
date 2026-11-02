# Headless model characterization

This suite constructs `ChessBoardModel` directly, without adding it to the scene
tree and without creating a View or Controller.

```sh
godot --headless --path . tests/headless/headless_model_characterization.tscn
godot --headless --path . tests/headless/cpu_player_characterization.tscn
godot --headless --path . tests/headless/lemay_performance_characterization.tscn
godot --headless --path . tests/headless/dupre_characterization.tscn
godot --headless --path . tests/headless/dupre_match_characterization.tscn
godot --headless --path . tests/headless/dupre_opening_book_characterization.tscn
godot --headless --path . tests/headless/dupre_opening_performance.tscn
godot --headless --path . tests/headless/classic_core_characterization.tscn
godot --headless --path . tests/headless/classic_core_performance.tscn
godot --headless --path . tests/headless/classic_core_differential.tscn
godot --headless --path . tests/headless/dupre_classic_core_characterization.tscn
godot --headless --path . tests/headless/dupre_classic_core_performance.tscn
godot --headless --path . tests/headless/classic_core_live_authority_characterization.tscn
godot --headless --path . tests/headless/classic_core_live_presentation_characterization.tscn
godot --headless --path . tests/headless/arakne_core_characterization.tscn
godot --headless --path . tests/headless/necromancer_core_characterization.tscn
godot --headless --path . tests/headless/minotaur_core_characterization.tscn
godot --headless --path . tests/headless/dupre_arakne_core_performance.tscn
godot --headless --path . tests/headless/dupre_necromancer_core_performance.tscn
godot --headless --path . tests/headless/dupre_minotaur_core_performance.tscn
godot --headless --path . tests/sandbox/classic_core_authority_characterization.tscn
```

The Classic differential suite compares `ChessBoardModel` and the pure-data
Classic core after every action. Its default fixed-seed gate runs 24 sequences
of up to 40 actions. The larger validation profile is:

```sh
godot --headless --path . tests/headless/classic_core_differential.tscn -- --diff-profile=soak
```

Failures write replayable and minimized JSON artifacts under
`user://test_artifacts/classic_core_differential`. The suite prints a matching
`--diff-replay=...` command for deterministic reproduction.

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
The opening-book suites cover seeded family selection, branches, deviations,
RPG-action tolerance, emergency overrides, execution-counted limits, lifecycle
resets, both colors, and the zero-simulation opening fast path.

The core suites characterize the isolated pure-data rules slice,
including import boundaries, legal-action parity, immutable synchronous
resolution, semantic event order, HP combat, castling, en passant, four-way
promotion, forced passes, RNG preservation, and comparative microbenchmarks.
Arakne coverage adds exact Skitter route identity, randomized model/core
differential play, Spike Burst damage and lethality, cooldown lifecycle and
disable rules, schema round-tripping, live presentation, and Dupre backend
parity. Unmigrated special Kings continue to fall back to ChessBoardModel.
Necromancer coverage adds Summon Bone Pawn, Bone Pawn movement and expiration,
single and opposing Raise Dead queues, coordinate-choice parity, target
recomputation, randomized differential play, live reaction presentation, and a
fixed-work Dupre performance gate.
Minotaur coverage adds Charge target and landing parity, wall self-stun,
durable impact damage, automatic Rage priority and cascading, composition with
Spike Burst and Raise Dead, randomized differential play, live Charge/Rage
presentation, and its own fixed-work Dupre performance gate.

The Dupre core suites force both simulation backends across quiet,
poisoned-capture, king-danger, promotion, Arakne, Necromancer, and Minotaur positions and require exact root
move/score parity without touching live state. Unsupported Classic imports and
unmigrated special kings must fall back to ChessBoardModel. The performance gate compares
equal fixed work, requires at least 2x throughput before automatic rollout,
then compares work completed under the same time budget and uninterrupted
main-thread intervals. Production Dupre uses the pure backend only when the
position falls entirely inside the validated Classic/Arakne/Necromancer/Minotaur slice.

The live-authority suites cover the sandbox-only experimental Classic/Arakne/Necromancer/Minotaur rollout.
They verify core-owned legal actions and outcomes, exact model-projection
lifecycle signals and revisions, movement, HP damage, captures, castling,
en passant, promotion choice plumbing, King defeat, forced-pass draws, CPU
execution, Skitter, Spike Burst, Summon Bone Pawn, Raise Dead secondary choices,
Charge, automatic Rage cascades, cooldown presentation, unsupported-position
fallback, position replacement, and the real
presentation adapter's completion gates and visual identity maps.
