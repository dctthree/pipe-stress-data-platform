from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pandas as pd

from .utils import atomic_write_json, sha256_file, utc_now, write_dataframe


def validate_dataset(output_root: str | Path, full_hash: bool = False) -> dict[str, Any]:
    root = Path(output_root).resolve()
    index_path = root / "dataset_index.json"
    if not index_path.exists():
        raise FileNotFoundError(f"数据集索引不存在: {index_path}")
    index = json.loads(index_path.read_text(encoding="utf-8"))
    rows: list[dict[str, Any]] = []

    tables: dict[str, pd.DataFrame] = {}
    for name, paths in index["tables"].items():
        parquet_path = root / Path(paths["parquet"])
        _check(rows, f"table_exists:{name}", parquet_path.exists(), str(parquet_path), "exists", "FAIL")
        if parquet_path.exists():
            try:
                tables[name] = pd.read_parquet(parquet_path)
                _check(rows, f"table_readable:{name}", True, len(tables[name]), ">=0", "FAIL")
            except Exception as error:
                _check(rows, f"table_readable:{name}", False, type(error).__name__, "readable", "FAIL", str(error))

    raw = tables.get("raw_files", pd.DataFrame())
    scans = tables.get("scans", pd.DataFrame())
    strain = tables.get("strain_files", pd.DataFrame())
    features = tables.get("channel_features", pd.DataFrame())
    matrix = tables.get("ml_feature_matrix", pd.DataFrame())
    events = tables.get("events", pd.DataFrame())

    _check(rows, "raw_file_count", len(raw) == index["counts"]["source_files"], len(raw), index["counts"]["source_files"], "FAIL")
    _check(rows, "scan_count", len(scans) == index["counts"]["sensor_scans_discovered"], len(scans), index["counts"]["sensor_scans_discovered"], "FAIL")
    _check(rows, "scan_id_unique", not scans.empty and scans["scan_id"].is_unique, int(scans["scan_id"].nunique()) if not scans.empty else 0, len(scans), "FAIL")
    _check(rows, "strain_partition_count", len(strain) == index["counts"]["strain_files_standardized"], len(strain), index["counts"]["strain_files_standardized"], "FAIL")
    _check(rows, "feature_scan_fk", set(features.get("scan_id", [])) <= set(scans.get("scan_id", [])), "foreign_keys", "all_present", "FAIL")
    _check(rows, "event_scan_fk", set(events.get("scan_id", [])) <= set(scans.get("scan_id", [])), "foreign_keys", "all_present", "FAIL")
    _check(rows, "split_group_complete", not scans.empty and scans["split_group"].notna().all(), int(scans.get("split_group", pd.Series(dtype=object)).isna().sum()), 0, "FAIL")
    if not matrix.empty:
        blind_leak = matrix["blind_flag"].fillna(True) & matrix["use_for_supervised"].fillna(False)
        _check(rows, "blind_label_leakage", not blind_leak.any(), int(blind_leak.sum()), 0, "FAIL")
        _check(rows, "direct_mpa_gate_closed", not matrix["direct_mpa_output_allowed"].fillna(False).any(),
               int(matrix["direct_mpa_output_allowed"].fillna(False).sum()), 0, "FAIL")
    baseline_ids = set(features.get("baseline_scan_id", pd.Series(dtype=object)).dropna().astype(str))
    _check(rows, "baseline_scan_fk", baseline_ids <= set(scans.get("scan_id", []).astype(str)), len(baseline_ids), "all_present", "FAIL")

    missing_signal = []
    for _, row in scans.iterrows():
        path = row.get("silver_signal_path")
        if not path or not (root / Path(path)).exists():
            missing_signal.append(str(row.get("scan_id")))
    _check(rows, "signal_partitions_exist", not missing_signal, len(missing_signal), 0, "FAIL", ",".join(missing_signal[:5]))
    missing_strain = []
    for _, row in strain.iterrows():
        path = row.get("silver_strain_path")
        if not path or not (root / Path(path)).exists():
            missing_strain.append(str(row.get("strain_file_id")))
    _check(rows, "strain_partitions_exist", not missing_strain, len(missing_strain), 0, "FAIL", ",".join(missing_strain[:5]))

    if index.get("snapshot_mode") == "blob":
        missing_blobs, bad_hashes = [], []
        for _, row in raw.iterrows():
            path = Path(str(row["snapshot_path"]))
            if not path.is_absolute():
                path = root / path
            if not path.exists():
                missing_blobs.append(str(row["file_id"]))
            elif full_hash and sha256_file(path) != row["sha256"]:
                bad_hashes.append(str(row["file_id"]))
        _check(rows, "raw_blobs_exist", not missing_blobs, len(missing_blobs), 0, "FAIL", ",".join(missing_blobs[:5]))
        if full_hash:
            _check(rows, "raw_blob_sha256", not bad_hashes, len(bad_hashes), 0, "FAIL", ",".join(bad_hashes[:5]))

    checks = pd.DataFrame(rows)
    overall = "FAIL" if (checks["outcome"] == "FAIL").any() else "WARN" if (checks["outcome"] == "WARN").any() else "PASS"
    report = {
        "schema_version": "1.0",
        "dataset_id": index["dataset_id"],
        "dataset_version": index["dataset_version"],
        "validated_at_utc": utc_now(),
        "full_blob_hash_validation": full_hash,
        "overall_status": overall,
        "check_count": int(len(checks)),
        "failed_check_count": int((checks["outcome"] == "FAIL").sum()),
        "warning_check_count": int((checks["outcome"] == "WARN").sum()),
    }
    write_dataframe(checks, root / "catalog" / "validation_checks")
    atomic_write_json(root / "catalog" / "validation_report.json", report)
    return report


def _check(
    rows: list[dict[str, Any]], name: str, passed: bool, value: Any,
    expected: Any, failure_severity: str, message: str = "",
) -> None:
    rows.append({
        "check_name": name,
        "outcome": "PASS" if passed else failure_severity,
        "passed": bool(passed),
        "value": str(value),
        "expected": str(expected),
        "message": message,
    })
