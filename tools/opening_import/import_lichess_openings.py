#!/usr/bin/env python3
"""Deterministically compile Lichess opening names for Dupre.

The importer deliberately keeps source theory, runtime repertoire selection,
and future popularity data separate. It emits a complete compatible canonical
book and a compact configured runtime projection.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Iterable

import chess
import chess.pgn


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path(__file__).parent / "vendor" / "lichess_chess_openings"
DEFAULT_CONFIG = Path(__file__).parent / "config.json"
DEFAULT_OUTPUT = ROOT / "assets" / "data" / "openings"
PIECE_NAMES = {
    chess.PAWN: "pawn",
    chess.KNIGHT: "knight",
    chess.BISHOP: "bishop",
    chess.ROOK: "rook",
    chess.QUEEN: "queen",
    chess.KING: "classic_king",
}


@dataclass(frozen=True)
class ImportedLine:
    family_id: str
    family_name: str
    eco: str
    name: str
    pgn: str
    uci: tuple[str, ...]
    moves: tuple[dict[str, Any], ...]
    final_epd: str
    truncated: bool
    source_names: tuple[str, ...] = ()
    source_ecos: tuple[str, ...] = ()

    @property
    def line_id(self) -> str:
        value = f"{self.family_id}|{' '.join(self.uci)}"
        return hashlib.sha256(value.encode("utf-8")).hexdigest()[:20]


def stable_id(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    slug = re.sub(r"[^a-z0-9]+", "_", normalized.lower()).strip("_")
    return slug or hashlib.sha256(value.encode()).hexdigest()[:12]


def square_coordinate(square: chess.Square) -> list[int]:
    return [7 - chess.square_rank(square), chess.square_file(square)]


def move_descriptor(board: chess.Board, move: chess.Move) -> dict[str, Any]:
    piece = board.piece_at(move.from_square)
    if piece is None:
        raise ValueError(f"no piece at {chess.square_name(move.from_square)}")
    target = square_coordinate(move.to_square)
    return {
        "kind": 0,
        "color": "white" if piece.color == chess.WHITE else "black",
        "piece": PIECE_NAMES[piece.piece_type],
        "from": square_coordinate(move.from_square),
        "to": target,
        "path": [target],
        "uci": move.uci(),
    }


def source_family(name: str) -> str:
    return name.split(":", 1)[0].strip()


def canonical_family(name: str, aliases: dict[str, str]) -> str:
    return aliases.get(source_family(name), source_family(name))


def load_source(config: dict[str, Any], source_dir: Path) -> tuple[list[ImportedLine], dict[str, Any]]:
    diagnostics: dict[str, Any] = {
        "source_entries": 0,
        "orthodox_accepted": 0,
        "rejected": Counter(),
        "truncated": 0,
        "duplicate_sequences": 0,
    }
    aliases = config.get("family_aliases", {})
    max_plies = int(config.get("max_plies", 0))
    include_eco = set(config.get("included_eco", []))
    exclude_eco = set(config.get("excluded_eco", []))
    parsed: list[ImportedLine] = []
    for filename in ("a.tsv", "b.tsv", "c.tsv", "d.tsv", "e.tsv"):
        with (source_dir / filename).open(encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                diagnostics["source_entries"] += 1
                eco, name, pgn = row["eco"], row["name"], row["pgn"]
                if include_eco and not any(eco.startswith(prefix) for prefix in include_eco):
                    diagnostics["rejected"]["eco_not_included"] += 1
                    continue
                if any(eco.startswith(prefix) for prefix in exclude_eco):
                    diagnostics["rejected"]["eco_excluded"] += 1
                    continue
                try:
                    game = chess.pgn.read_game(io.StringIO(pgn))
                    if game is None or game.errors:
                        raise ValueError(str(game.errors if game else "empty PGN"))
                    all_moves = list(game.mainline_moves())
                    board = chess.Board()
                    descriptors: list[dict[str, Any]] = []
                    uci: list[str] = []
                    limit = len(all_moves) if max_plies <= 0 else min(max_plies, len(all_moves))
                    unsupported = False
                    for move in all_moves[:limit]:
                        if move not in board.legal_moves:
                            raise ValueError(f"illegal move {move.uci()}")
                        if move.promotion is not None:
                            diagnostics["rejected"]["promotion_action_unsupported"] += 1
                            unsupported = True
                            break
                        descriptors.append(move_descriptor(board, move))
                        uci.append(move.uci())
                        board.push(move)
                    if unsupported:
                        continue
                    # Validate the entire source sequence even if runtime output is truncated.
                    validation_board = chess.Board()
                    for move in all_moves:
                        if move not in validation_board.legal_moves:
                            raise ValueError(f"illegal source move {move.uci()}")
                        validation_board.push(move)
                    family_name = canonical_family(name, aliases)
                    parsed.append(ImportedLine(
                        stable_id(family_name), family_name, eco, name, pgn,
                        tuple(uci), tuple(descriptors), board.epd(), len(all_moves) > limit,
                        (name,), (eco,),
                    ))
                    diagnostics["orthodox_accepted"] += 1
                    if len(all_moves) > limit:
                        diagnostics["truncated"] += 1
                except (ValueError, KeyError, IndexError) as error:
                    diagnostics["rejected"][f"orthodox_error:{type(error).__name__}"] += 1
    # Deduplicate equal sequences within a family while retaining their names/ECO metadata.
    grouped: dict[tuple[str, tuple[str, ...]], list[ImportedLine]] = defaultdict(list)
    for line in parsed:
        grouped[(line.family_id, line.uci)].append(line)
    result: list[ImportedLine] = []
    for key in sorted(grouped):
        group = sorted(grouped[key], key=lambda item: (item.eco, item.name, item.pgn))
        result.append(replace(
            group[0],
            source_names=tuple(sorted({name for line in group for name in (line.source_names or (line.name,))})),
            source_ecos=tuple(sorted({eco for line in group for eco in (line.source_ecos or (line.eco,))})),
        ))
        diagnostics["duplicate_sequences"] += len(group) - 1
    diagnostics["rejected"] = dict(sorted(diagnostics["rejected"].items()))
    return result, diagnostics


def diversity_cap(lines: list[ImportedLine], cap: int) -> list[ImportedLine]:
    """Select deterministic shallow-branch coverage when an experiment enables a cap."""
    if cap <= 0 or len(lines) <= cap:
        return lines
    remaining = sorted(lines, key=lambda line: (line.eco, line.name, line.uci))
    chosen: list[ImportedLine] = []
    covered_edges: set[tuple[str, ...]] = set()
    shallow_groups: dict[tuple[str, ...], list[ImportedLine]] = defaultdict(list)
    for line in remaining:
        shallow_groups[line.uci[:2]].append(line)
    for prefix in sorted(shallow_groups):
        if len(chosen) >= cap:
            break
        candidate = min(shallow_groups[prefix], key=lambda line: (len(line.uci), line.eco, line.name, line.uci))
        chosen.append(candidate)
        for depth in range(1, len(candidate.uci) + 1):
            covered_edges.add(candidate.uci[:depth])
    remaining = [line for line in remaining if line not in chosen]
    while remaining and len(chosen) < cap:
        def score(line: ImportedLine) -> tuple[float, int, str, str, tuple[str, ...]]:
            novelty = sum(1.0 / depth for depth in range(1, len(line.uci) + 1) if line.uci[:depth] not in covered_edges)
            return (-novelty, len(line.uci), line.eco, line.name, line.uci)
        candidate = min(remaining, key=score)
        chosen.append(candidate)
        remaining.remove(candidate)
        for depth in range(1, len(candidate.uci) + 1):
            covered_edges.add(candidate.uci[:depth])
    return sorted(chosen, key=lambda line: (line.uci, line.eco, line.name))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def verify_source(source_dir: Path, provenance: dict[str, Any]) -> None:
    for filename, expected in provenance.get("files", {}).items():
        path = source_dir / filename
        if not path.exists():
            raise RuntimeError(f"vendored source file is missing: {path}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError(f"vendored source hash mismatch for {filename}: {actual} != {expected}")


def validation_payload(lines: list[ImportedLine]) -> dict[str, Any]:
    return {
        "lines": [
            {"line_id": line.line_id, "family_id": line.family_id, "name": line.name, "moves": list(line.moves)}
            for line in lines
        ]
    }


def validation_digest(candidate: dict[str, Any]) -> str:
    encoded = json.dumps(candidate, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def authoritative_validate(candidate: dict[str, Any], godot_bin: Path) -> tuple[set[str], list[dict[str, Any]], str]:
    with tempfile.TemporaryDirectory(prefix="crpg_opening_import_") as temp:
        candidate_path = Path(temp) / "candidates.json"
        result_path = Path(temp) / "validation.json"
        write_json(candidate_path, candidate)
        command = [
            str(godot_bin), "--headless", "--log-file", str(Path(temp) / "godot.log"), "--path", str(ROOT),
            "--script", "res://tools/opening_import/validate_openings.gd", "--",
            str(candidate_path), str(result_path),
        ]
        completed = subprocess.run(command, capture_output=True, text=True, check=False)
        if completed.returncode != 0 or not result_path.exists():
            raise RuntimeError(
                "authoritative validation failed\n"
                f"command: {' '.join(command)}\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
        result = json.loads(result_path.read_text(encoding="utf-8"))
        return set(result["accepted_line_ids"]), result["rejections"], completed.stdout


def build_family(family_id: str, family_lines: list[ImportedLine]) -> dict[str, Any]:
    family_lines = sorted(family_lines, key=lambda line: (line.uci, line.eco, line.name))
    nodes: list[dict[str, Any]] = [{"children": [], "terminal_line_ids": [], "position_key": chess.Board().epd()}]
    child_maps: list[dict[str, int]] = [{}]
    recovery: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    line_records: list[dict[str, Any]] = []
    for line in family_lines:
        node_id = 0
        own_counts = {"white": 0, "black": 0}
        board = chess.Board()
        for descriptor in line.moves:
            color = descriptor["color"]
            recovery[f"{color}:{own_counts[color]}"][descriptor["uci"]] = descriptor
            own_counts[color] += 1
            uci = descriptor["uci"]
            if uci not in child_maps[node_id]:
                child_id = len(nodes)
                child_maps[node_id][uci] = child_id
                move = chess.Move.from_uci(uci)
                board.push(move)
                nodes.append({"children": [], "terminal_line_ids": [], "position_key": board.epd()})
                child_maps.append({})
                child = dict(descriptor)
                child["node"] = child_id
                nodes[node_id]["children"].append(child)
                node_id = child_id
            else:
                node_id = child_maps[node_id][uci]
                board.push(chess.Move.from_uci(uci))
        nodes[node_id]["terminal_line_ids"].append(line.line_id)
        line_records.append({
            "id": line.line_id,
            "eco": line.eco,
            "eco_codes": list(line.source_ecos or (line.eco,)),
            "name": line.name,
            "names": list(line.source_names or (line.name,)),
            "pgn": line.pgn,
            "uci": list(line.uci),
            "final_epd": line.final_epd,
            "truncated": line.truncated,
        })
    for node in nodes:
        node["children"].sort(key=lambda child: child["uci"])
        node["terminal_line_ids"].sort()
    return {
        "id": family_id,
        "name": family_lines[0].family_name,
        "eco_codes": sorted({eco for line in family_lines for eco in (line.source_ecos or (line.eco,))}),
        "nodes": nodes,
        "recovery": {
            key: [values[uci] for uci in sorted(values)]
            for key, values in sorted(recovery.items())
        },
        "lines": line_records,
    }


def compact_family(family: dict[str, Any]) -> dict[str, Any]:
    move_catalog = {
        child["uci"]: [child["piece"], child["color"][0]]
        for node in family["nodes"]
        for child in node["children"]
    }
    return {
        "id": family["id"],
        "name": family["name"],
        "nodes": [
            {
                "children": [
                    [child["uci"], child["piece"], child["color"][0], child["node"]]
                    for child in node["children"]
                ]
            }
            for node in family["nodes"]
        ],
        "recovery": {
            key: [descriptor["uci"] for descriptor in descriptors]
            for key, descriptors in family["recovery"].items()
        },
        "moves": move_catalog,
    }


def leaf_depths(family: dict[str, Any], color: str) -> list[int]:
    result: list[int] = []
    stack: list[tuple[int, int]] = [(0, 0)]
    while stack:
        node_id, own_depth = stack.pop()
        children = family["nodes"][node_id]["children"]
        if not children:
            result.append(own_depth)
            continue
        for child in children:
            stack.append((child["node"], own_depth + int(child["color"] == color)))
    return result


def first_move_distribution(families: list[dict[str, Any]]) -> dict[str, Any]:
    white: Counter[str] = Counter()
    if families:
        family_weight = 1.0 / len(families)
        for family in families:
            moves = family["nodes"][0]["children"]
            if moves:
                for move in moves:
                    white[move["uci"]] += family_weight / len(moves)
    white_keys = sorted({child["uci"] for family in families for child in family["nodes"][0]["children"]})
    black: dict[str, dict[str, float]] = {}
    for white_uci in white_keys:
        eligible: list[tuple[dict[str, Any], dict[str, Any]]] = []
        for family in families:
            for child in family["nodes"][0]["children"]:
                if child["uci"] == white_uci:
                    eligible.append((family, child))
        responses: Counter[str] = Counter()
        if eligible:
            family_weight = 1.0 / len(eligible)
            for family, white_child in eligible:
                moves = family["nodes"][white_child["node"]]["children"]
                if moves:
                    for move in moves:
                        responses[move["uci"]] += family_weight / len(moves)
        black[white_uci] = {move: round(probability, 8) for move, probability in sorted(responses.items())}
    return {
        "white": {move: round(probability, 8) for move, probability in sorted(white.items())},
        "black_conditioned_on_white_first_move": black,
    }


def depth_report(families: list[dict[str, Any]]) -> dict[str, Any]:
    report: dict[str, Any] = {}
    for color in ("white", "black"):
        full, partial, short = [], [], []
        histogram: Counter[int] = Counter()
        for family in families:
            depths = leaf_depths(family, color)
            for depth in depths:
                histogram[depth] += 1
            if depths and min(depths) >= 7:
                full.append(family["id"])
            elif depths and max(depths) >= 7:
                partial.append(family["id"])
            else:
                short.append(family["id"])
        report[color] = {
            "all_leaf_routes_reach_seven": full,
            "some_leaf_routes_reach_seven": partial,
            "no_leaf_route_reaches_seven": short,
            "counts": {"all": len(full), "some": len(partial), "none": len(short)},
            "leaf_depth_histogram": {str(depth): count for depth, count in sorted(histogram.items())},
        }
    return report


def markdown_report(data: dict[str, Any]) -> str:
    summary = data["summary"]
    depth = data["active_depth_coverage"]
    lines = [
        "# Lichess opening import diagnostics", "",
        f"- Revision: `{data['source']['revision']}`",
        f"- Source entries: {summary['source_entries']}",
        f"- Orthodox accepted before deduplication: {summary['orthodox_accepted']}",
        f"- Source rejected or filtered: {summary['source_rejected_or_filtered']}",
        f"- Unsupported entries: {summary['unsupported_entries']}",
        f"- Authoritatively accepted distinct lines: {summary['authoritative_accepted']}",
        f"- Authoritatively rejected: {summary['authoritative_rejected']}",
        f"- Duplicate family sequences merged: {summary['duplicate_sequences']}",
        f"- Truncated to configured depth: {summary['truncated']}",
        f"- Canonical families: {summary['canonical_families']}",
        f"- Active families: {summary['active_families']}",
        f"- Canonical generated bytes: {summary['canonical_bytes']}",
        f"- Runtime generated bytes: {summary['runtime_bytes']}", "",
        "## Seven-own-move active coverage", "",
        f"- White: all routes={depth['white']['counts']['all']}, some routes={depth['white']['counts']['some']}, no route={depth['white']['counts']['none']}",
        f"- Black: all routes={depth['black']['counts']['all']}, some routes={depth['black']['counts']['some']}, no route={depth['black']['counts']['none']}", "",
        "## Expected White first moves under uniform family selection", "",
    ]
    for move, probability in data["expected_first_move_distribution"]["white"].items():
        lines.append(f"- `{move}`: {probability:.4%}")
    lines.extend(["", "Black response distributions are conditional on White's first move and are recorded in the JSON report.", ""])
    if data["rejection_reasons"]:
        lines.extend(["## Rejections", ""])
        for reason, count in data["rejection_reasons"].items():
            lines.append(f"- {reason}: {count}")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--godot-bin", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--refresh-authoritative", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    provenance = json.loads((args.source / "PROVENANCE.json").read_text(encoding="utf-8"))
    verify_source(args.source, provenance)
    lines, import_stats = load_source(config, args.source)
    candidate = validation_payload(lines)
    candidate_digest = validation_digest(candidate)
    validation_path = args.output / "lichess_openings_authoritative_validation.json"
    validation_cache = None
    if validation_path.exists() and not args.refresh_authoritative:
        cached = json.loads(validation_path.read_text(encoding="utf-8"))
        if cached.get("candidate_digest") == candidate_digest:
            validation_cache = cached
    if validation_cache == None:
        accepted_ids, authoritative_rejections, validator_stdout = authoritative_validate(candidate, args.godot_bin)
        validation_cache = {
            "schema_version": 1,
            "candidate_digest": candidate_digest,
            "source_revision": provenance["revision"],
            "accepted_line_ids": sorted(accepted_ids),
            "rejections": authoritative_rejections,
        }
    else:
        accepted_ids = set(validation_cache["accepted_line_ids"])
        authoritative_rejections = validation_cache["rejections"]
        validator_stdout = "AUTHORITATIVE OPENING VALIDATION: cache digest matched"
    lines = [line for line in lines if line.line_id in accepted_ids]

    by_family: dict[str, list[ImportedLine]] = defaultdict(list)
    for line in lines:
        by_family[line.family_id].append(line)
    max_rows = int(config.get("max_rows_per_family", 0))
    capped = {family_id: diversity_cap(family_lines, max_rows) for family_id, family_lines in by_family.items()}
    families = [build_family(family_id, capped[family_id]) for family_id in sorted(capped)]

    include_names = set(config.get("included_families", []))
    exclude_names = set(config.get("excluded_families", []))
    if config.get("include_eccentric", False):
        active = [family for family in families if family["name"] not in exclude_names]
    else:
        active = [family for family in families if family["name"] in include_names and family["name"] not in exclude_names]
    missing = sorted(include_names - {family["name"] for family in families})
    if missing:
        raise RuntimeError(f"configured active families were not imported: {missing}")

    canonical = {
        "schema_version": 1,
        "source": provenance,
        "configuration": config,
        "popularity": None,
        "popularity_note": "Intentionally absent; future game-frequency data must use a separate provenance-bearing sidecar.",
        "families": families,
    }
    runtime = {
        "schema_version": 1,
        "source_revision": provenance["revision"],
        "selection": "uniform_family_then_uniform_distinct_continuation",
        "families": [compact_family(family) for family in active],
    }
    canonical_text = json.dumps(canonical, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    runtime_text = json.dumps(runtime, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    rejection_reasons = Counter(import_stats["rejected"])
    for rejection in authoritative_rejections:
        rejection_reasons[f"authoritative:{rejection['reason']}"] += 1
    distribution = first_move_distribution(active)
    unique_black_responses = {
        response
        for responses in distribution["black_conditioned_on_white_first_move"].values()
        for response in responses
    }
    diagnostics = {
        "source": provenance,
        "configuration": config,
        "summary": {
            **{key: value for key, value in import_stats.items() if key != "rejected"},
            "source_rejected_or_filtered": sum(import_stats["rejected"].values()),
            "unsupported_entries": sum(count for reason, count in import_stats["rejected"].items() if "unsupported" in reason),
            "authoritative_accepted": len(lines),
            "authoritative_rejected": len(authoritative_rejections),
            "canonical_families": len(families),
            "canonical_variations": sum(len(family["lines"]) for family in families),
            "canonical_named_positions": sum(len(line["names"]) for family in families for line in family["lines"]),
            "canonical_branching_nodes": sum(sum(1 for node in family["nodes"] if len(node["children"]) > 1) for family in families),
            "active_families": len(active),
            "active_variations": sum(len(family["lines"]) for family in active),
            "active_named_positions": sum(len(line["names"]) for family in active for line in family["lines"]),
            "active_branching_nodes": sum(sum(1 for node in family["nodes"] if len(node["children"]) > 1) for family in active),
            "canonical_bytes": len(canonical_text.encode("utf-8")),
            "runtime_bytes": len(runtime_text.encode("utf-8")),
            "optional_cap_enabled": max_rows > 0,
            "unique_white_first_moves": len(distribution["white"]),
            "unique_black_first_responses": len(unique_black_responses),
        },
        "rejection_reasons": dict(sorted(rejection_reasons.items())),
        "authoritative_rejections": authoritative_rejections,
        "active_family_distribution": {family["id"]: 1.0 / len(active) for family in active},
        "expected_first_move_distribution": distribution,
        "active_depth_coverage": depth_report(active),
        "canonical_depth_coverage": depth_report(families),
        "active_family_variation_counts": {family["id"]: len(family["lines"]) for family in active},
        "validator_output": validator_stdout.strip().splitlines(),
    }
    diagnostics_text = json.dumps(diagnostics, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    report_text = markdown_report(diagnostics)
    outputs = {
        validation_path: json.dumps(validation_cache, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        args.output / "lichess_openings_canonical.json": canonical_text,
        args.output / "dupre_openings_runtime.json": runtime_text,
        args.output / "lichess_openings_diagnostics.json": diagnostics_text,
        args.output / "lichess_openings_diagnostics.md": report_text,
    }
    if args.check:
        changed = [str(path.relative_to(ROOT)) for path, text in outputs.items() if not path.exists() or path.read_text(encoding="utf-8") != text]
        if changed:
            print("Generated opening artifacts are stale:", *changed, sep="\n- ", file=sys.stderr)
            return 1
    else:
        for path, text in outputs.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
    print(json.dumps(diagnostics["summary"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
