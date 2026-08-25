#!/usr/bin/env python3
"""Fail-closed validator for the frozen public P110 case evidence.

Only the Python standard library is used. This validates the tracked compact
evidence and its public boundaries; it does not recompute features from raw
Release files or validate an absolute-stress model.
"""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
REVIEWED = ROOT / "results" / "reviewed"
FEATURES = ["q60_delta", "q70_delta", "q75_delta", "q80_delta"]
EXPECTED_HEADER = [
    "run_id", "stage_mm", "stress_mpa", *FEATURES, "sensor_n"
]
EXPECTED_STAGES = [0, 20, 40, 50, 60]
EXPECTED_STRESS = {
    "mem_r1": [0.0, 39.432582, 83.695620, 108.809149, 132.885335],
    "mem_r2": [0.0, 44.262348, 88.826177, 113.215457, 137.099653],
}
EXPECTED_SLOPE_RATIOS = {
    "q60_delta": 2.189957049541,
    "q70_delta": 1.876941862283,
    "q75_delta": 1.806730924313,
    "q80_delta": 2.027040476378,
}


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def ranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=values.__getitem__)
    result = [0.0] * len(values)
    index = 0
    while index < len(order):
        end = index + 1
        while end < len(order) and values[order[end]] == values[order[index]]:
            end += 1
        rank = (index + 1 + end) / 2.0
        for position in range(index, end):
            result[order[position]] = rank
        index = end
    return result


def pearson(x: list[float], y: list[float]) -> float:
    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    numerator = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
    denominator = math.sqrt(
        sum((a - mean_x) ** 2 for a in x) * sum((b - mean_y) ** 2 for b in y)
    )
    return numerator / denominator


def slope(x: list[float], y: list[float]) -> float:
    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    return sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y)) / sum(
        (a - mean_x) ** 2 for a in x
    )


def main() -> int:
    errors: list[str] = []
    checks: dict[str, Any] = {}

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    key_files = {
        ROOT / "README.md",
        ROOT / "config" / "p110_exp2_release.example.json",
        ROOT / "python" / "run_p110_case.py",
        ROOT / "matlab" / "run_p110_case.m",
        REVIEWED / "p110_multisensor_mem_real.csv",
        REVIEWED / "feature_metrics.csv",
        REVIEWED / "release_summary.json",
        REVIEWED / "real_p110_magnetic_case.png",
        ROOT / "release" / "DATASET_CARD.md",
        ROOT / "release" / "release_index.json",
        ROOT / "release" / "SHA256SUMS.txt",
    }
    missing = sorted(str(path.relative_to(ROOT)) for path in key_files if not path.is_file())
    require(not missing, f"Missing P110 case files: {missing}")
    require(all(path.stat().st_size > 0 for path in key_files if path.exists()),
            "At least one required P110 case file is empty")
    checks["key_files_present"] = not missing

    image_path = REVIEWED / "real_p110_magnetic_case.png"
    if image_path.is_file():
        require(image_path.stat().st_size > 10_000, "Tracked real P110 PNG is unexpectedly small")
        require(image_path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n",
                "Tracked real P110 figure is not a PNG")
        checks["real_png_bytes"] = image_path.stat().st_size

    table_path = REVIEWED / "p110_multisensor_mem_real.csv"
    if table_path.is_file():
        header, rows = read_csv(table_path)
        require(header == EXPECTED_HEADER, f"Unexpected compact table header: {header}")
        require(len(rows) == 10, f"Compact table has {len(rows)} rows, expected 10")
        require(len({(r["run_id"], r["stage_mm"]) for r in rows}) == len(rows),
                "Compact table contains duplicate run/stage rows")
        groups: dict[str, list[dict[str, str]]] = defaultdict(list)
        numeric_ok = True
        for row in rows:
            groups[row["run_id"]].append(row)
            try:
                values = [float(row[c]) for c in EXPECTED_HEADER[1:]]
                numeric_ok = numeric_ok and all(math.isfinite(value) for value in values)
            except (TypeError, ValueError):
                numeric_ok = False
        require(numeric_ok, "Compact table contains non-finite or non-numeric values")
        require(set(groups) == {"mem_r1", "mem_r2"}, f"Unexpected runs: {sorted(groups)}")
        require(all(int(float(row["sensor_n"])) == 5 for row in rows),
                "Every compact row must represent five preselected sensors")

        computed_ratios: dict[str, float] = {}
        if numeric_ok and set(groups) == {"mem_r1", "mem_r2"}:
            feature_slopes: dict[str, list[float]] = {feature: [] for feature in FEATURES}
            for run_id in ("mem_r1", "mem_r2"):
                group = sorted(groups[run_id], key=lambda row: float(row["stage_mm"]))
                stages = [int(float(row["stage_mm"])) for row in group]
                stresses = [float(row["stress_mpa"]) for row in group]
                require(stages == EXPECTED_STAGES,
                        f"{run_id} stages are {stages}, expected {EXPECTED_STAGES}")
                require(all(abs(a - b) <= 1e-6 for a, b in zip(stresses, EXPECTED_STRESS[run_id])),
                        f"{run_id} strain-derived stress values changed")
                require(all(b > a for a, b in zip(stresses, stresses[1:])),
                        f"{run_id} strain-derived stress is not strictly increasing")
                require(abs(stresses[0]) <= 1e-12, f"{run_id} zero-load stress is not zero")
                for feature in FEATURES:
                    values = [float(row[feature]) for row in group]
                    require(abs(values[0]) <= 1e-12,
                            f"{run_id}/{feature} same-run zero-load baseline changed")
                    require(all(b > a for a, b in zip(values, values[1:])),
                            f"{run_id}/{feature} no longer preserves strict ordering")
                    rho = pearson(ranks(stresses), ranks(values))
                    require(abs(rho - 1.0) <= 1e-12,
                            f"{run_id}/{feature} Spearman rho changed to {rho}")
                    feature_slopes[feature].append(slope(stresses, values))
            for feature, values in feature_slopes.items():
                ratio = max(values) / min(values)
                computed_ratios[feature] = ratio
                require(1.75 <= ratio <= 2.25,
                        f"{feature} slope ratio {ratio:.6f} no longer freezes scale instability")
                require(abs(ratio - EXPECTED_SLOPE_RATIOS[feature]) <= 1e-9,
                        f"{feature} slope ratio changed: {ratio:.12f}")
        checks["compact_rows"] = len(rows)
        checks["slope_ratios"] = computed_ratios

        legacy = REPO / "docs" / "data" / "p110_multisensor_mem_real.csv"
        require(legacy.is_file() and legacy.read_bytes() == table_path.read_bytes(),
                "Case compact table differs from the backward-compatible docs copy")

    metrics_path = REVIEWED / "feature_metrics.csv"
    if metrics_path.is_file():
        metric_header, metric_rows = read_csv(metrics_path)
        require(len(metric_rows) == 4, "Frozen feature_metrics.csv must contain four rows")
        require({row["feature_id"] for row in metric_rows} == set(FEATURES),
                "Frozen feature metric IDs changed")
        require(all(row["allowed_use"] == "relative_order_candidate_only" for row in metric_rows),
                "A P110 metric was promoted beyond relative-order use")
        require(all(abs(float(row["min_within_run_spearman"]) - 1.0) <= 1e-12
                    for row in metric_rows), "Frozen minimum Spearman values changed")
        checks["metric_rows"] = len(metric_rows)

    config_path = ROOT / "config" / "p110_exp2_release.example.json"
    if config_path.is_file():
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        experiment = config["experiment"]
        require(experiment["material"] == "P110", "Config material is not P110")
        require([experiment[k] for k in ("pipe_length_m", "outer_diameter_mm", "wall_thickness_mm")]
                == [10.54, 139.70, 9.17], "P110 geometry changed")
        require([experiment[k] for k in ("yield_strength_mpa", "tensile_strength_mpa")]
                == [853.0, 930.0], "P110 strength properties changed")
        aliases = config["probe_aliases"]
        require(aliases["MEM"]["pole_geometry"] == "bilateral_intact",
                "MEM_FULL must retain complete bilateral poles")
        require(len({entry["probe_id"] for entry in aliases.values()}) == 5,
                "Sanitized full config must preserve five probe hardware families")
        recommended = {row["run_id"]: row for row in config["run_rules"] if row["recommended"]}
        require(recommended.get("mem_r1", {}).get("folder_contains") == "第二次",
                "mem_r1 must map to the second experimental folder")
        require(recommended.get("mem_r2", {}).get("folder_contains") == "第三次",
                "mem_r2 must map to the third experimental folder")
        require(config["stage_sequences"].get("mem_r1") == EXPECTED_STAGES,
                "mem_r1 must include 0/20/40/50/60 mm")
        require(config["stage_sequences"].get("mem_r2") == EXPECTED_STAGES,
                "mem_r2 must include 0/20/40/50/60 mm")
        schema = config["signal_schema"]
        require(schema["axis_order"] == ["Z", "Y", "X"], "P110 axis order changed")
        require(schema["accepted_column_counts"] == [3, 45], "P110 column layout changed")
        require(schema["preferred_sensor_ids_for_45_columns"] == [1, 3, 4, 5, 6],
                "P110 preselected sensor IDs changed")
        require(schema["known_excluded_sensor_ids"] == [2, 7],
                "P110 excluded sensor IDs changed")
        require(all(schema[key] is None for key in
                    ("sample_rate_hz", "pull_speed_mps", "nominal_liftoff_mm")),
                "Unknown rate/speed/liftoff fields must remain null")
        root_config = REPO / "configs" / "p110_exp2.example.json"
        require(root_config.is_file() and json.loads(root_config.read_text(encoding="utf-8-sig")) == config,
                "Case and backward-compatible root P110 configurations differ")
        checks["recommended_run_mapping"] = {
            key: recommended[key]["folder_contains"] for key in sorted(recommended)
        } if set(recommended) == {"mem_r1", "mem_r2"} else recommended

    summary_path = REVIEWED / "release_summary.json"
    if summary_path.is_file():
        summary = json.loads(summary_path.read_text(encoding="utf-8-sig"))
        require(summary["measurements"] == [
            "three_axis_magnetic_sensor_output", "strain_gauge"
        ], "P110 measurement boundary changed")
        require(summary["independent_remanence_measurement_present"] is False,
                "P110 must not claim an independent remanence measurement")
        require(summary["etp_present"] is False, "P110 must not claim ETP data")
        counts = summary["counts"]
        require(counts == {
            "source_files": 211,
            "sensor_scans_discovered": 53,
            "sensor_scans_completed": 53,
            "sensor_scans_failed": 0,
            "strain_files_standardized": 18,
            "strain_values_standardized": 9380688,
            "channel_feature_rows": 639,
            "primary_stress_feature_qc_failed": 33,
            "ingest_errors": 0,
        }, f"Unexpected P110 release counts: {counts}")
        require(summary["integrity_validation"]["scope"].endswith("not stress-model performance"),
                "Integrity PASS must not be represented as model performance")
        require(summary["label_policy"]["direct_mpa_prediction_enabled"] is False,
                "P110 direct MPa prediction must remain disabled")
        require(summary["coordinate_policy"]["physical_distance_available"] is False,
                "P110 normalized position must not be called a physical distance")
        compact = summary["reviewed_compact_evidence"]
        require(compact["clock_position"] == 6 and compact["mechanical_side"] == "tensile",
                "Reviewed compact evidence must remain the 6 o'clock tensile-side subset")
        require(compact["raw_to_compact_row_provenance_complete"] is False,
                "Compact provenance must not be overclaimed")
        checks["release_counts"] = counts

    release_index_path = ROOT / "release" / "release_index.json"
    if release_index_path.is_file():
        index = json.loads(release_index_path.read_text(encoding="utf-8-sig"))
        require(index["release_tag"] == "v0.2.0", "P110 Release tag changed")
        require(index["dataset_fingerprint_sha256"] ==
                "97b0dca627686ad7002a6cbb83348017963a6d7dbca24d0030978cc50c2010c5",
                "P110 dataset fingerprint changed")
        require(len(index["assets"]) == 1, "P110 Release index must contain one asset")
        asset = index["assets"][0]
        require(asset["asset_name"] ==
                "P110_EXP2_full_release_1.0.0+97b0dca62768.zip", "P110 asset name changed")
        require(asset["bytes"] == 169639531, "P110 asset byte count changed")
        require(asset["sha256"] ==
                "38cc098c9a590f05efea429073e7c17c0b2c5f8b0232a7625e50957e05fa6a7c",
                "P110 asset SHA-256 changed")
        checksum = (ROOT / "release" / "SHA256SUMS.txt").read_text(
            encoding="utf-8-sig"
        ).strip()
        require(checksum == f"{asset['sha256']}  {asset['asset_name']}",
                "P110 SHA256SUMS does not match release_index.json")
        checks["release_asset"] = asset["asset_name"]

    root_readme = (REPO / "README.md").read_text(encoding="utf-8-sig")
    root_readme_cn = (REPO / "README_CN.md").read_text(encoding="utf-8-sig")
    for name, text in (("README.md", root_readme), ("README_CN.md", root_readme_cn)):
        require("case_studies/p110_magnetic_strain/README.md" in text,
                f"{name} lacks the first-class P110 case link")
        require("case_studies/406_multimodal/README.md" in text,
                f"{name} lacks the first-class 406 case link")
        require("releases/tag/v0.2.0" in text and "releases/tag/v0.3.0" in text,
                f"{name} does not link both public data releases")

    case_readme = (ROOT / "README.md").read_text(encoding="utf-8-sig")
    for required in (
        "No ETP data", "no independently acquired remanence", "6 o'clock tensile-side",
        "same run", "strain-gauge-derived", "relative-order candidate",
        "Universal direct MPa prediction remains disabled", "v0.2.0",
    ):
        require(required.lower() in case_readme.lower(),
                f"P110 README lacks required scientific boundary: {required}")

    drive_path = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/]")
    unix_home = re.compile(r"/(?:Users|home)/[^/\s]+/")
    path_leaks: list[str] = []
    replacement_chars: list[str] = []
    for path in ROOT.rglob("*"):
        if "runtime" in path.relative_to(ROOT).parts or not path.is_file():
            continue
        if path.suffix.lower() not in {".m", ".md", ".json", ".csv", ".py", ".txt"}:
            continue
        text = path.read_text(encoding="utf-8-sig", errors="strict")
        if drive_path.search(text) or unix_home.search(text):
            path_leaks.append(str(path.relative_to(ROOT)))
        if "\ufffd" in text:
            replacement_chars.append(str(path.relative_to(ROOT)))
    require(not path_leaks, f"Workstation-specific paths found in: {path_leaks}")
    require(not replacement_chars, f"Unicode replacement characters found in: {replacement_chars}")
    checks["absolute_path_leaks"] = path_leaks

    report = {
        "case": "p110_magnetic_strain",
        "ok": not errors,
        "validation_scope": "tracked reviewed evidence and release identity; not absolute-stress model performance",
        "checks": checks,
        "errors": errors,
    }
    # Windows CI may expose a cp1252 stdout even though the files are UTF-8.
    # ASCII-escaped JSON keeps the validator portable without weakening checks.
    print(json.dumps(report, ensure_ascii=True, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
