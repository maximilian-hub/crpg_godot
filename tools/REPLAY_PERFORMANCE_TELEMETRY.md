# Replay performance telemetry

Schema-v2 `.crpggame` files retain compact per-AI-turn performance counters and
a derived match summary. Full search profiles and candidate diagnostics are kept
only around an explicitly flagged issue frame; clean exports omit them.

Analyze the saved-match corpus:

```sh
godot --headless --path . --script res://tools/analyze_saved_matches.gd
```

Write a machine-readable report:

```sh
godot --headless --path . --script res://tools/analyze_saved_matches.gd -- --json=/tmp/corpus.json
```

Write compact schema-v2 copies of an older corpus (never point this at the
source directory):

```sh
godot --headless --path . --script res://tools/analyze_saved_matches.gd -- --compact-dir=/tmp/compact_matches
```

Extract the position before frame 50 as a fixed-work fixture, then benchmark it:

```sh
godot --headless --path . --script res://tools/analyze_saved_matches.gd -- --extract=res://saved_matches/example.crpggame:49 --output=/tmp/fixture.json --candidates=10 --replies=100
godot --headless --path . --script res://tools/benchmark_dupre_fixture.gd -- --fixture=/tmp/fixture.json
```

Fixed-time telemetry answers how much Dupre completed inside its normal budget.
The extracted fixed-work benchmark answers whether the same bounded workload
became cheaper after an optimization.
