# Dupre Lichess opening importer

The vendored input is pinned to the revision recorded in
`vendor/lichess_chess_openings/PROVENANCE.json`. The upstream collection is
released under CC0; its license is retained beside the TSV files.

Create a virtual environment, install `requirements.txt`, then regenerate the
book with:

```sh
python3 tools/opening_import/import_lichess_openings.py \
  --godot-bin "/path/to/Godot" \
  --config tools/opening_import/config.json
```

The command performs standard-chess validation with `python-chess`, invokes the
headless Chess RPG authoritative validator, and writes:

- `assets/data/openings/lichess_openings_canonical.json`: every compatible
  imported family and variation, including metadata for future offline tools.
- `assets/data/openings/dupre_openings_runtime.json`: the compact active
  repertoire used by the game.
- `assets/data/openings/lichess_openings_diagnostics.json` and `.md`: import,
  depth, distribution, and rejection details.

Use `--check` in CI to verify that regeneration is deterministic. Runtime
selection is uniform by family and then by distinct continuation. Named-row
counts are deliberately not treated as popularity. Future game-frequency data
belongs in a separately sourced sidecar keyed by the stable family, line, and
position identifiers in the canonical artifact.

Successful authoritative results are cached by a digest of every candidate
descriptor. The cache is invalidated automatically when theory or conversion
changes. Pass `--refresh-authoritative` to force a complete fresh replay.
