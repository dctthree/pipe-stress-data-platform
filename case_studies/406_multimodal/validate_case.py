#!/usr/bin/env python3
"""Validate the frozen public evidence for the 406 multimodal case.

This script uses only the Python standard library. It does not read the large
raw CSV release and does not recompute scientific features.
"""

from __future__ import annotations

import csv
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "results" / "latest"

EXPECTED_CSV = {
    "cross_cycle_metrics.csv",
    "cycle_metrics.csv",
    "etp_channel_features.csv",
    "etp_fragment_qc.csv",
    "etp_gates.csv",
    "etp_stage_qc.csv",
    "F2_circumferential_features.csv",
    "F2_physical_column_features.csv",
    "F2_repeat_metrics.csv",
    "F3_shape_qc.csv",
    "feature_status.csv",
    "magnetic_fragment_qc.csv",
    "magnetic_stage_qc.csv",
    "multimodal_decision_table.csv",
    "source_stage_manifest.csv",
    "stage_features.csv",
    "stage_repeatability.csv",
    "test_results.csv",
    "window_metrics.csv",
    "window_sensitivity_27.csv",
}

EXPECTED_PNG = {
    "01_repeat_design_matrix.png",
    "02_magnetic_landmark_qc.png",
    "03_etp_landmark_qc.png",
    "04_registered_remanence_q90_profiles.png",
    "05_F1_three_cycle_trajectories.png",
    "06_F1_cross_cycle_agreement.png",
    "07_F1_window_robustness_27.png",
    "08_F2_array_consistency.png",
    "09_F3_spatial_mechanics_qc.png",
    "10_MEM_F4_and_MAG_F5.png",
    "11_ETP_candidate_trajectories.png",
    "12_ETP_negative_controls_temperature.png",
    "13_multimodal_gated_dashboard.png",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> int:
    errors: list[str] = []
    checks: dict[str, Any] = {}

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    key_files = {
        ROOT / "README.md",
        ROOT / "config" / "406_release.example.json",
        ROOT / "matlab" / "run_blind406_demo.m",
        ROOT / "matlab" / "run_blind406_tests.m",
        ROOT / "matlab" / "export_simple_feature_profiles.m",
        ROOT / "matlab" / "plot_calibration_feature_trends.m",
        ROOT / "matlab" / "+blind406" / "readMagneticStage.m",
        ROOT / "matlab" / "+blind406" / "readEtpStage.m",
        RESULTS / "analysis_summary.json",
        RESULTS / "结论说明.md",
        ROOT / "results" / "calibration" / "calibration_stage_labels.csv",
        ROOT / "results" / "calibration" / "calibration_feature_values.csv",
        ROOT / "results" / "calibration" / "calibration_feature_metrics.csv",
        ROOT / "results" / "calibration" / "07_physical_contrast_trends.png",
        ROOT / "release" / "DATASET_CARD.md",
        ROOT / "release" / "channel_schema.csv",
        ROOT / "release" / "raw_file_manifest.csv",
        ROOT / "release" / "release_index.json",
        ROOT / "release" / "SHA256SUMS.txt",
    }
    missing_key = sorted(str(p.relative_to(ROOT)) for p in key_files if not p.is_file())
    require(not missing_key, f"Missing key files: {missing_key}")
    checks["key_files_present"] = not missing_key

    actual_csv = {p.name for p in RESULTS.glob("*.csv")}
    missing_csv = sorted(EXPECTED_CSV - actual_csv)
    require(not missing_csv, f"Missing derived CSV files: {missing_csv}")
    checks["derived_csv_count"] = len(actual_csv)

    actual_png = {p.name for p in (RESULTS / "figures").glob("*.png")}
    require(actual_png == EXPECTED_PNG, (
        f"PNG set mismatch; missing={sorted(EXPECTED_PNG - actual_png)}, "
        f"extra={sorted(actual_png - EXPECTED_PNG)}"
    ))
    require(all((RESULTS / "figures" / name).stat().st_size > 0 for name in EXPECTED_PNG),
            "At least one expected PNG is empty")
    checks["png_count"] = len(actual_png)

    if not errors:
        features = read_csv(RESULTS / "stage_features.csv")
        counts = Counter(row["cycle_id"] for row in features)
        require(len(features) == 17, f"stage_features.csv has {len(features)} rows, expected 17")
        require(counts == Counter({"C1": 7, "C2": 7, "C3": 3}),
                f"Unexpected cycle counts: {dict(counts)}")
        require(len({(row["cycle_id"], row["stage_id"]) for row in features}) == 17,
                "stage_features.csv does not contain 17 unique cycle-stage packets")
        c2s2_features = [r for r in features if r["cycle_id"] == "C2" and r["stage_id"] == "S2"]
        require(len(c2s2_features) == 1 and c2s2_features[0]["mag_qc_status"] == "REJECT",
                "C2/S2 must be retained with magnetic QC status REJECT")
        checks["stage_packets"] = len(features)
        checks["cycle_stage_counts"] = dict(sorted(counts.items()))

        manifest = read_csv(RESULTS / "source_stage_manifest.csv")
        require(len(manifest) == 42, f"Manifest has {len(manifest)} rows, expected 42")
        legacy_layout_tokens = (
            "raw/blind/magnetic/",
            "raw/blind/etp/",
            "第一个周期-截取",
            "第二个周期-截取",
            "第三个周期-截取",
        )
        require(all(
            not any(token in row.get("StageFolder", "") for token in legacy_layout_tokens)
            for row in manifest
        ), "Frozen source manifest still contains a pre-release local path layout")
        require(all(
            row.get("StageFolder", "").startswith(
                f"raw/blind/{row['CycleID']}/"
                f"{'magnetic' if row['Modality'] == 'MAGNETIC' else 'etp'}/"
            )
            for row in manifest
        ), "Frozen source manifest paths do not match the canonical Release layout")
        available_by_modality: Counter[str] = Counter()
        packet_modalities: dict[tuple[str, str], set[str]] = defaultdict(set)
        for row in manifest:
            if row["Available"] in {"1", "true", "True"}:
                available_by_modality[row["Modality"]] += 1
                packet_modalities[(row["CycleID"], row["StageID"])].add(row["Modality"])
        require(available_by_modality == Counter({"MAGNETIC": 17, "ETP": 17}),
                f"Unexpected available manifest counts: {dict(available_by_modality)}")
        require(len(packet_modalities) == 17 and all(v == {"MAGNETIC", "ETP"} for v in packet_modalities.values()),
                "The 17 available packets are not paired across MAGNETIC and ETP")
        checks["available_manifest_rows"] = dict(sorted(available_by_modality.items()))

        mag_qc = read_csv(RESULTS / "magnetic_stage_qc.csv")
        mag_fragment_qc = read_csv(RESULTS / "magnetic_fragment_qc.csv")
        require(all(
            row.get("Path", "").startswith(
                f"raw/blind/{row['cycle_id']}/magnetic/"
            )
            and not any(token in row.get("Path", "") for token in legacy_layout_tokens)
            for row in mag_fragment_qc
        ), "Frozen magnetic fragment paths do not match the canonical Release layout")
        c2s2_qc = [r for r in mag_qc if r["cycle_id"] == "C2" and r["stage_id"] == "S2"]
        require(len(mag_qc) == 17, f"magnetic_stage_qc.csv has {len(mag_qc)} rows, expected 17")
        require(len(c2s2_qc) == 1 and c2s2_qc[0]["status"] == "REJECT",
                "magnetic_stage_qc.csv does not mark C2/S2 as REJECT")
        require(c2s2_qc and "焊缝" in c2s2_qc[0].get("source_note", ""),
                "C2/S2 operator weld warning is missing")

        decisions = read_csv(RESULTS / "multimodal_decision_table.csv")
        fusion_values = [r.get("fusion_value", "").strip().lower() for r in decisions]
        require(len(decisions) == 17, f"Decision table has {len(decisions)} rows, expected 17")
        require(all(v == "nan" for v in fusion_values),
                "fusion_value must be NaN for every packet; numeric fusion is prohibited")
        checks["numeric_fusion_values"] = 0

        calibration = read_csv(ROOT / "results" / "calibration" / "calibration_stage_labels.csv")
        require([row["stage_id"] for row in calibration] == [f"S{i}" for i in range(7)],
                "Calibration labels must contain exactly S0-S6 in order")
        require(all("not load-cell truth" in row["label_scope"] for row in calibration),
                "Calibration label scope must state that values are not load-cell truth")
        require(abs(float(calibration[-1]["nominal_stress_mpa"]) - 305.3744) < 1e-9,
                "Calibration S6 nominal stress changed")
        checks["calibration_label_rows"] = len(calibration)

        calibration_values = read_csv(
            ROOT / "results" / "calibration" / "calibration_feature_values.csv"
        )
        calibration_metrics = read_csv(
            ROOT / "results" / "calibration" / "calibration_feature_metrics.csv"
        )
        require(len(calibration_values) == 28,
                f"Calibration feature table has {len(calibration_values)} rows, expected 28")
        require(len({row["feature_id"] for row in calibration_values}) == 4,
                "Calibration feature table must contain four frozen features")
        require(len(calibration_metrics) == 4,
                f"Calibration metric table has {len(calibration_metrics)} rows, expected 4")
        require(all(row["feature_scope"] == "development_calibration_only"
                    for row in calibration_values),
                "Calibration features must remain development-only evidence")
        checks["calibration_feature_rows"] = len(calibration_values)
        checks["calibration_metric_rows"] = len(calibration_metrics)

        release_manifest = read_csv(ROOT / "release" / "raw_file_manifest.csv")
        require(len(release_manifest) == 234,
                f"Release manifest has {len(release_manifest)} rows, expected 234")
        release_counts = Counter(row["modality"] for row in release_manifest)
        require(release_counts == Counter({
            "magnetic_shared_MEM_remanence": 131,
            "ETP_eddy_current": 97,
            "strain_gauge_derived_label": 3,
            "strain_gauge": 2,
            "documentation": 1,
        }), f"Unexpected release modality counts: {dict(release_counts)}")
        c2s2_etp = [
            row for row in release_manifest
            if row["modality"] == "ETP_eddy_current"
            and row["cycle"] == "C2" and row["stage_id"] == "S2"
        ]
        c2s2_mag = [
            row for row in release_manifest
            if row["modality"] == "magnetic_shared_MEM_remanence"
            and row["cycle"] == "C2" and row["stage_id"] == "S2"
        ]
        require(len(c2s2_etp) == 6 and all(
            row["stage_qc_status"] == "PASS_ETP_PAIRED_MAGNETIC_REJECT"
            for row in c2s2_etp
        ), "Release manifest must preserve ETP C2/S2 as own-QC pass / paired-magnetic reject")
        require(len(c2s2_mag) == 10 and all(
            row["stage_qc_status"] == "REJECT_WELD_NOT_CENTERED"
            for row in c2s2_mag
        ), "Release manifest must reject the ten magnetic C2/S2 fragments")
        with (ROOT / "release" / "release_index.json").open(
            "r", encoding="utf-8-sig"
        ) as handle:
            release_index = json.load(handle)
        require(len(release_index.get("assets", [])) == 8,
                "Release index must describe eight ZIP assets")
        require(release_index.get("truth_policy", {}).get(
            "blind_cycles_have_stress_truth"
        ) is False, "Release index must keep blind stress truth false")
        checksum_lines = [
            line for line in (ROOT / "release" / "SHA256SUMS.txt").read_text(
                encoding="utf-8-sig"
            ).splitlines() if line.strip()
        ]
        require(len(checksum_lines) == 12,
                f"SHA256SUMS has {len(checksum_lines)} lines, expected 12")
        checks["release_manifest_rows"] = len(release_manifest)
        checks["release_assets"] = len(release_index.get("assets", []))

        statuses = {r["feature_id"]: r["status"] for r in read_csv(RESULTS / "feature_status.csv")}
        required_statuses = {
            "MAG-F1-DW-Q90-v1": "B_RELATIVE_ORDER_ONLY_SCALE_DRIFT_OR_QC_EXCLUSION",
            "MEM-F4-ZSD-v1": "CONDITIONAL_S0_AUXILIARY_SCALE_NOT_QUALIFIED",
            "ETP-E1-CDIFF-v1": "QC_ONLY_NOT_STRESS_QUANTITY",
            "MULTIMODAL-GATED-v1": "DECISION_GATING_NO_NUMERIC_FUSION",
        }
        for feature_id, expected_status in required_statuses.items():
            require(statuses.get(feature_id) == expected_status,
                    f"Unexpected status for {feature_id}: {statuses.get(feature_id)!r}")
        checks["frozen_feature_statuses"] = required_statuses

        with (RESULTS / "analysis_summary.json").open("r", encoding="utf-8-sig") as handle:
            summary = json.load(handle)
        require(summary.get("current_strain_or_stress_truth_used") is False,
                "Summary must state that blind strain/stress truth was not used")
        require(summary.get("available_stage_packets") == 17,
                "Summary available_stage_packets must equal 17")
        require(summary.get("cycle_stage_counts") == {"C1": 7, "C2": 7, "C3": 3},
                "Summary cycle_stage_counts must equal C1=7, C2=7, C3=3")
        require(summary.get("numeric_fusion_performed") is False,
                "Summary must state that numeric fusion was not performed")
        require(summary.get("public_raw_identity") ==
                "release/raw_file_manifest.csv per-file SHA-256",
                "Summary must identify the public per-file SHA-256 manifest")
        require(summary.get("frozen_path_layout") ==
                "canonical_release_paths_mechanical_provenance_migration_only",
                "Summary must disclose the frozen path-layout provenance migration")
        require(summary.get("cache", {}).get("sourceFingerprint_scope") ==
                "pre-release local cache key; not a public raw-data integrity identifier",
                "Summary must scope the legacy cache fingerprint correctly")
        multimodal_status = next(
            (row for row in summary.get("feature_status", [])
             if row.get("feature_id") == "MULTIMODAL-GATED-v1"),
            {},
        )
        require("逐阶段冲突评分未实现" in multimodal_status.get("allowed_use", ""),
                "Summary must state that stagewise conflict scoring is not implemented")
        require("not implemented" in summary.get("fusion_policy", ""),
                "Summary fusion policy must not overclaim stagewise conflict gating")
        require(summary.get("absolute_stress_status") == "NOT_VALIDATED_NO_CURRENT_TRUTH",
                "Summary absolute-stress boundary changed")
        warning = summary.get("known_warning", {})
        require(warning.get("cycle") == "C2" and warning.get("stage") == "S2"
                and warning.get("final_qc_status") == "REJECT",
                "Summary must preserve the C2/S2 REJECT warning")
        checks["blind_truth_used"] = summary.get("current_strain_or_stress_truth_used")

        with (ROOT / "config" / "406_release.example.json").open("r", encoding="utf-8-sig") as handle:
            config = json.load(handle)
        require(config.get("magneticRoot") == "raw/blind",
                "Example magneticRoot must match the Release root raw/blind")
        require(config.get("etpRoot") == "raw/blind",
                "Example etpRoot must match the Release root raw/blind")
        require([
            row.get("magneticFolder") for row in config.get("cycles", [])
        ] == ["C1/magnetic", "C2/magnetic", "C3/magnetic"],
                "Configured magnetic folders must match canonical Release paths")
        require([
            row.get("etpFolder") for row in config.get("cycles", [])
        ] == ["C1/etp", "C2/etp", "C3/etp"],
                "Configured ETP folders must match canonical Release paths")
        require(str(config.get("outputRoot", "")).startswith("runtime/"),
                "Example outputRoot must write under ignored runtime/")
        require(str(config.get("cacheFile", "")).startswith("runtime/"),
                "Example cacheFile must write under ignored runtime/")

    # Public text must not expose a workstation-specific absolute path.
    drive_path = re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:[\\/]")
    unix_home = re.compile(r"/(?:Users|home)/[^/\s]+/")
    leaked_paths: list[str] = []
    generated_or_private = {"raw", "runtime", "cache", "__pycache__"}
    for path in ROOT.rglob("*"):
        if generated_or_private.intersection(path.relative_to(ROOT).parts):
            continue
        if path.is_file() and path.suffix.lower() in {".m", ".md", ".json", ".csv", ".py", ".txt"}:
            text = path.read_text(encoding="utf-8-sig", errors="strict")
            if drive_path.search(text) or unix_home.search(text):
                leaked_paths.append(str(path.relative_to(ROOT)))
    require(not leaked_paths, f"Workstation-specific absolute paths found in: {sorted(leaked_paths)}")
    checks["absolute_path_leaks"] = sorted(leaked_paths)

    report = {
        "case": "406_multimodal",
        "ok": not errors,
        "checks": checks,
        "errors": errors,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
