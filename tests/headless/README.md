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
godot --headless --path . tests/headless/quarterly_initiative_core_characterization.tscn
godot --headless --path . tests/headless/dupre_quarterly_core_performance.tscn
godot --headless --path . tests/headless/arakne_core_characterization.tscn
godot --headless --path . tests/headless/necromancer_core_characterization.tscn
godot --headless --path . tests/headless/minotaur_core_characterization.tscn
godot --headless --path . tests/headless/cannon_core_characterization.tscn
godot --headless --path . tests/headless/cannon_reaction_soak.tscn
godot --headless --path . tests/headless/dupre_cannon_core_characterization.tscn
godot --headless --path . tests/headless/dupre_cannon_core_performance.tscn
godot --headless --path . tests/headless/rhetorician_core_characterization.tscn
godot --headless --path . tests/headless/dupre_rhetorician_core_characterization.tscn
godot --headless --path . tests/headless/dupre_rhetorician_core_performance.tscn
godot --headless --path . tests/headless/wraith_core_characterization.tscn
godot --headless --path . tests/headless/dupre_wraith_core_characterization.tscn
godot --headless --path . tests/headless/dupre_wraith_core_performance.tscn
godot --headless --path . tests/headless/dupre_arakne_core_performance.tscn
godot --headless --path . tests/headless/dupre_necromancer_core_performance.tscn
godot --headless --path . tests/headless/dupre_minotaur_core_performance.tscn
godot --headless --path . tests/sandbox/classic_core_authority_characterization.tscn
```

The historical Classic differential suite compares its preserved facade
fixtures with the pure-data core after every action. Live `ChessBoardModel` is
now a projection facade over that same core, rather than an independent rules
implementation. Its default fixed-seed gate runs 24 sequences of up to 40
actions. The larger validation profile is:

```sh
godot --headless --path . tests/headless/classic_core_differential.tscn -- --diff-profile=soak
```

Failures write replayable and minimized JSON artifacts under
`user://test_artifacts/classic_core_differential`. The suite prints a matching
`--diff-replay=...` command for deterministic reproduction.

The Cannon reaction gate compares the model and pure core through delayed
Mortar, Rage, Raise Dead, overlapping-impact, forced-pass, and terminal-battle
cascades. Its default profile runs 32 sequences of up to 80 actions. The full
pre-migration soak and deterministic replay controls are:

```sh
godot --headless --path . tests/headless/cannon_reaction_soak.tscn -- --mixed-profile=soak
godot --headless --path . tests/headless/cannon_reaction_soak.tscn -- --mixed-seed=57923841 --mixed-sequences=32 --mixed-plies=160
godot --headless --path . tests/headless/cannon_reaction_soak.tscn -- --mixed-replay=user://test_artifacts/cannon_reaction_soak/failure-SEED-TIME.json
```

Failures write replayable JSON artifacts under
`user://test_artifacts/cannon_reaction_soak`. Coverage counters prevent a run
from passing without exercising delayed impacts, reaction choices, overlapping
mortars, source-independent shells, forced passes, and battle completion.

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
Arakne coverage adds exact Skitter route identity, randomized facade/core
differential play, Spike Burst damage and lethality, cooldown lifecycle and
disable rules, schema round-tripping, live presentation, and Dupre backend
parity. Unsupported position data is rejected at the authoritative import
boundary; there is no legacy ChessBoardModel rules fallback.
Necromancer coverage adds Summon Bone Pawn, Bone Pawn movement and expiration,
single and opposing Raise Dead queues, coordinate-choice parity, target
recomputation, randomized differential play, live reaction presentation, and a
fixed-work Dupre performance gate.
Minotaur coverage adds Charge target and landing parity, wall self-stun,
durable impact damage, automatic Rage priority and cascading, composition with
Spike Burst and Raise Dead, randomized differential play, live Charge/Rage
presentation, and its own fixed-work Dupre performance gate.

The Quarterly suite covers Efficiency, free and paid Performance Cycles,
explicit movement-type choices, lethal self-cost, permanent granted movement
and attack geometry, randomized differential play, live choice/presentation,
and a dedicated fixed-work Dupre performance gate.

The Cannon suite covers Arc Mortar targeting, conditional cooldowns, delayed
owner-turn impacts, source-independent persistence, position round-tripping,
explicit fallback for unsupported autonomous entities, and model/core soak
parity across mixed Minotaur and Necromancer reaction cascades.

The Rhetorician suite covers adjacent physical-attack prevention, underlying
threat recognition, compelled movement and capture, Lunacy thresholds,
serialized random Socratic moves, no-move skips, Raise Dead composition,
randomized differential play, live projection, and Dupre backend parity.

The Dupre core suites force both simulation containers (direct pure data and
the Node-based live facade) across quiet,
poisoned-capture, king-danger, promotion, Arakne, Necromancer, Minotaur, Quarterly, and Cannon positions and require exact root
move/score parity without touching live state. The Node container delegates its
rules to the same pure core; unsupported imports are rejected rather than sent
to a legacy engine. The performance gate compares
equal fixed work, requires at least 2x throughput before automatic rollout,
then compares work completed under the same time budget and uninterrupted
main-thread intervals. Production Dupre uses the direct pure backend for the
validated roster, including Archer variants.

The live-authority suites cover the mandatory Classic/Arakne/Necromancer/Minotaur/Quarterly/Cannon/Rhetorician/Wraith/Archer authority path.
They verify core-owned legal actions and outcomes, exact model-projection
lifecycle signals and revisions, movement, HP damage, captures, castling,
en passant, promotion choice plumbing, King defeat, forced-pass draws, CPU
execution, Skitter, Spike Burst, Summon Bone Pawn, Raise Dead secondary choices,
Charge, automatic Rage cascades, cooldown presentation, unsupported-position
movement grants, Performance Cycle self-damage, secondary movement choices,
fallback, position replacement, and the real
presentation adapter's completion gates and visual identity maps.

The Wraith suites cover Cursed Marks, Lingering Malice, targeted autonomous
pursuit, immediate source/target cleanup, mixed reaction ordering, live
projection, Dupre routing, and fixed-work performance.

`cross_king_core_soak.tscn` is the bounded all-King conformance gate. It runs
every ordered pairing of Classic, Arakne, Necromancer, Minotaur, Quarterly
Initiative, Cannon, Rhetorician, and Wraith with two deterministic seeds and up
to 48 settled actions. It compares legal action/path identity, choices,
serialized state, RNG, and lifecycle settlement while reporting per-phase
timings and mechanic coverage. Failures write replayable artifacts beneath
`/tmp/crpg_cross_king_core_soak`.

Run the larger opt-in soak with:

```sh
godot --headless --path . tests/headless/cross_king_core_soak.tscn -- --cross-profile=soak
```

Replay with `--cross-replay=<artifact>`. Use `--cross-white=<type>` and
`--cross-black=<type>` for focused diagnosis; seed count and ply limits can be
overridden independently.
