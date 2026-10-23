import json
import tempfile
import unittest
from pathlib import Path

import chess

from import_lichess_openings import (
    ImportedLine,
    build_family,
    canonical_family,
    diversity_cap,
    first_move_distribution,
    load_source,
    move_descriptor,
    stable_id,
)


def make_line(family: str, name: str, moves: list[str]) -> ImportedLine:
    board = chess.Board()
    descriptors = []
    for uci in moves:
        move = chess.Move.from_uci(uci)
        descriptors.append(move_descriptor(board, move))
        board.push(move)
    return ImportedLine(
        stable_id(family), family, "A00", name, "", tuple(moves),
        tuple(descriptors), board.epd(), False,
    )


class OpeningImportTests(unittest.TestCase):
    def test_family_alias_is_not_eco_based(self):
        aliases = {"Queen's Gambit Accepted": "Queen's Gambit"}
        self.assertEqual(canonical_family("Queen's Gambit Accepted: Old Variation", aliases), "Queen's Gambit")
        self.assertEqual(canonical_family("Sicilian Defense: Najdorf Variation", aliases), "Sicilian Defense")

    def test_native_coordinate_and_castling_descriptor(self):
        board = chess.Board()
        descriptor = move_descriptor(board, chess.Move.from_uci("e2e4"))
        self.assertEqual(descriptor["from"], [6, 4])
        self.assertEqual(descriptor["to"], [4, 4])
        for uci in ["e2e4", "e7e5", "g1f3", "b8c6", "f1e2", "g8f6"]:
            board.push_uci(uci)
        castle = move_descriptor(board, chess.Move.from_uci("e1g1"))
        self.assertEqual(castle["piece"], "classic_king")
        self.assertEqual(castle["path"], [[7, 6]])

    def test_shared_prefix_becomes_one_branching_trie(self):
        lines = [
            make_line("Test Opening", "A", ["e2e4", "e7e5", "g1f3"]),
            make_line("Test Opening", "B", ["e2e4", "c7c5", "g1f3"]),
        ]
        family = build_family("test_opening", lines)
        self.assertEqual(len(family["nodes"][0]["children"]), 1)
        after_e4 = family["nodes"][family["nodes"][0]["children"][0]["node"]]
        self.assertEqual({child["uci"] for child in after_e4["children"]}, {"e7e5", "c7c5"})

    def test_diversity_cap_preserves_distinct_shallow_branches(self):
        lines = [
            make_line("Test", "A", ["e2e4", "e7e5", "g1f3"]),
            make_line("Test", "B", ["e2e4", "c7c5", "g1f3"]),
            make_line("Test", "C", ["d2d4", "d7d5", "c2c4"]),
            make_line("Test", "D", ["e2e4", "e7e5", "f1c4"]),
        ]
        selected = diversity_cap(lines, 3)
        self.assertEqual({line.uci[:2] for line in selected}, {
            ("e2e4", "e7e5"), ("e2e4", "c7c5"), ("d2d4", "d7d5")
        })

    def test_uniform_family_selection_not_row_weighting(self):
        small = build_family("small", [make_line("Small", "Small", ["e2e4", "e7e5"])])
        large = build_family("large", [
            make_line("Large", "One", ["d2d4", "d7d5"]),
            make_line("Large", "Two", ["d2d4", "g8f6"]),
            make_line("Large", "Three", ["c2c4", "e7e5"]),
        ])
        distribution = first_move_distribution([small, large])["white"]
        self.assertEqual(distribution["e2e4"], 0.5)
        self.assertEqual(distribution["d2d4"], 0.25)
        self.assertEqual(distribution["c2c4"], 0.25)

    def test_family_generation_is_deterministic(self):
        lines = [
            make_line("Test", "B", ["d2d4", "d7d5"]),
            make_line("Test", "A", ["e2e4", "e7e5"]),
        ]
        first = json.dumps(build_family("test", lines), sort_keys=True)
        second = json.dumps(build_family("test", list(reversed(lines))), sort_keys=True)
        self.assertEqual(first, second)

    def test_depth_limit_and_promotion_rejection_are_explicit(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            for volume in "abcde":
                rows = "eco\tname\tpgn\n"
                if volume == "a":
                    rows += "A00\tShort Test\t1. e4 e5 2. Nf3\n"
                    rows += "A00\tPromotion Test\t1. a4 h5 2. a5 h4 3. a6 h3 4. axb7 hxg2 5. bxa8=Q\n"
                (source / f"{volume}.tsv").write_text(rows, encoding="utf-8")
            lines, diagnostics = load_source({"max_plies": 2, "family_aliases": {}}, source)
            short = next(line for line in lines if line.family_name == "Short Test")
            self.assertEqual(short.uci, ("e2e4", "e7e5"))
            self.assertTrue(short.truncated)
            # The promotion lies beyond the configured depth, so it is validly
            # truncated out rather than represented with false native identity.
            self.assertEqual(len(lines), 2)
            lines, diagnostics = load_source({"max_plies": 14, "family_aliases": {}}, source)
            self.assertEqual(len(lines), 1)
            self.assertEqual(diagnostics["rejected"]["promotion_action_unsupported"], 1)


if __name__ == "__main__":
    unittest.main()
