from __future__ import annotations

import json
import platform
import shutil
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from . import __version__
from .catalog import write_sqlite_catalog
from .config import canonical_json_bytes, config_without_runtime, load_config
from .events import build_event_table
from .features import add_relative_features, build_ml_feature_matrix, feature_definitions
from .metadata import attach_label, classify_file, load_labels, parse_scan_metadata, should_exclude
from .signal import SIGNAL_STANDARDIZER_VERSION, SignalSchemaError, process_sensor_scan
from .strain import STRAIN_STANDARDIZER_VERSION, standardize_strain_file
from .utils import atomic_write_json, relative_posix, sha256_file, stable_fingerprint, utc_now, write_dataframe


def run_pipeline(config_path: str | Path, output_root: str | Path, snapshot_mode: str = "blob") -> dict[str, Any]:
    if snapshot_mode not in {"blob", "reference"}:
        raise ValueError("snapshot_mode 只能是 blob 或 reference")
    config = load_config(config_path)
    source_root = Path(config["_source_root_path"]).resolve()
    output = Path(output_root).resolve()
    if not source_root.is_dir():
        raise FileNotFoundError(f"源目录不存在: {source_root}")
    output.mkdir(parents=True, exist_ok=True)
    for directory in ["raw/blobs/sha256", "catalog", "silver/signals", "gold", "runs", "releases"]:
        (output / directory).mkdir(parents=True, exist_ok=True)

    started_at = utc_now()
    code_sha256 = _pipeline_code_fingerprint()
    signal_standardization_id = stable_fingerprint([
        SIGNAL_STANDARDIZER_VERSION,
        canonical_json_bytes(config["signal_schema"]).decode("utf-8"),
    ])[:12]
    run_token = started_at.replace(":", "").replace("-", "").replace("+00:00", "Z")
    pipeline_run_id = f"run_{run_token}_{config['_config_sha256'][:8]}"
    previous = _load_previous_file_cache(output / "catalog" / "raw_files.csv")
    previous_strain = _load_previous_strain_cache(output / "catalog" / "strain_files.csv", output)
    labels = load_labels(config)
    raw_rows: list[dict[str, Any]] = []
    scan_meta_rows: list[dict[str, Any]] = []
    ingest_errors: list[dict[str, Any]] = []

    files = sorted(
        [path for path in source_root.rglob("*") if path.is_file() and not should_exclude(path, source_root, config)],
        key=lambda value: str(value).casefold(),
    )
    for source_path in files:
        relative = relative_posix(source_path, source_root)
        stat = source_path.stat()
        cache_key = (str(source_path), int(stat.st_size), int(stat.st_mtime_ns))
        file_sha = previous.get(cache_key) or sha256_file(source_path)
        role = classify_file(source_path, relative, config)
        blob_path: Path | None = None
        if snapshot_mode == "blob":
            blob_path = _snapshot_blob(source_path, file_sha, output)
        file_id = "file_sha256_" + file_sha
        raw_row = {
            "file_id": file_id,
            "sha256": file_sha,
            "experiment_id": config["experiment"]["experiment_id"],
            "relative_path": relative,
            "source_path": str(source_path),
            "snapshot_path": relative_posix(blob_path, output) if blob_path else None,
            "snapshot_mode": snapshot_mode,
            "role": role,
            "extension": source_path.suffix.casefold(),
            "size_bytes": int(stat.st_size),
            "source_modified_utc": pd.Timestamp(stat.st_mtime, unit="s", tz="UTC").isoformat(),
            "pipeline_run_id": pipeline_run_id,
            "metadata_parse_status": "not_applicable",
        }
        if role == "sensor_raw":
            parsed = parse_scan_metadata(relative, file_sha, config)
            if parsed is None:
                raw_row["metadata_parse_status"] = "FAIL"
                ingest_errors.append({
                    "source_path": str(source_path), "relative_path": relative,
                    "error_type": "metadata_parse", "message": "CSV未匹配已注册的探头/轮次/文件名规则",
                })
            else:
                raw_row["metadata_parse_status"] = "PASS"
                parsed.update(
                    source_file_id=file_id,
                    source_sha256=file_sha,
                    source_path=str(source_path),
                    source_modified_utc=raw_row["source_modified_utc"],
                )
                scan_meta_rows.append(attach_label(parsed, labels))
        raw_rows.append(raw_row)

    raw_files = pd.DataFrame(raw_rows)
    strain_summaries: list[dict[str, Any]] = []
    for raw_row in raw_rows:
        if raw_row["role"] != "strain_measurement" or raw_row["extension"] not in {".xlsx", ".txt"}:
            continue
        try:
            summary = previous_strain.get(raw_row["file_id"])
            if summary is None:
                summary, _ = standardize_strain_file(
                    Path(raw_row["source_path"]), raw_row["file_id"],
                    config["experiment"]["experiment_id"], output,
                )
            mapped_run, alignment_status = _match_strain_run(raw_row["relative_path"], config)
            summary["mapped_run_id"] = mapped_run
            summary["alignment_status"] = alignment_status
            strain_summaries.append(summary)
        except Exception as error:
            ingest_errors.append({
                "source_path": raw_row["source_path"],
                "relative_path": raw_row["relative_path"],
                "scan_id": None,
                "error_type": f"strain_{type(error).__name__}",
                "message": str(error),
            })
    strain_files = pd.DataFrame(strain_summaries)
    if strain_files.empty:
        strain_files = pd.DataFrame(columns=[
            "strain_file_id", "source_file_id", "experiment_id", "source_path",
            "workbook_or_text_kind", "sheet_name", "record_count", "channel_count",
            "strain_standardizer_version",
            "value_count", "missing_value_fraction", "timestamp_start", "timestamp_end",
            "silver_strain_path", "strain_qc_status", "unit", "coordinate_note",
            "mapped_run_id", "alignment_status",
        ])
    scan_qc_frames: list[pd.DataFrame] = []
    signal_feature_frames: list[pd.DataFrame] = []
    completed_scans: list[dict[str, Any]] = []
    signal_cache: dict[str, dict[tuple[int, str], np.ndarray]] = {}
    silver_paths: dict[str, str] = {}

    for meta in scan_meta_rows:
        source_path = Path(meta["source_path"])
        try:
            update, qc, signals, features, cache = process_sensor_scan(source_path, meta, config)
            full_meta = {**meta, **update}
            completed_scans.append(full_meta)
            scan_qc_frames.append(qc)
            signal_feature_frames.append(features)
            signal_cache[meta["scan_id"]] = cache
            silver_path = output / "silver" / "signals" / signal_standardization_id / f"{meta['scan_id']}.parquet"
            silver_path.parent.mkdir(parents=True, exist_ok=True)
            signals.to_parquet(silver_path, index=False, compression="zstd")
            silver_paths[meta["scan_id"]] = relative_posix(silver_path, output)
        except Exception as error:
            ingest_errors.append({
                "source_path": str(source_path),
                "relative_path": meta["source_relative_path"],
                "scan_id": meta["scan_id"],
                "error_type": type(error).__name__,
                "message": str(error),
            })
            failed = dict(meta)
            failed.update(
                raw_rows=None, raw_columns=None, sensor_count_in_file=None,
                selected_sensor_ids=None, effective_sensor_count=0,
                pipe_start_index=None, pipe_end_index=None, pipe_fraction=None,
                edge_snr=None, edge_detection_fallback=None, scan_qc_status="FAIL",
                primary_axis=config["signal_schema"]["axis_order"][-1],
                primary_axis_valid_sensor_count=0, primary_stress_feature_qc_status="FAIL",
                sample_rate_hz=config["signal_schema"].get("sample_rate_hz"),
                pull_speed_mps=config["signal_schema"].get("pull_speed_mps"),
                nominal_liftoff_mm=config["signal_schema"].get("nominal_liftoff_mm"),
            )
            completed_scans.append(failed)
            scan_qc_frames.append(pd.DataFrame([{
                "scan_id": meta["scan_id"], "level": "scan", "scope_id": meta["scan_id"],
                "check_name": "scan_processing", "outcome": "FAIL", "passed": False,
                "value": type(error).__name__, "threshold": "successful", "message": str(error),
            }]))

    scans = pd.DataFrame(completed_scans)
    if not scans.empty:
        scans["silver_signal_path"] = scans["scan_id"].map(silver_paths)
        scans = scans.sort_values(
            ["probe_id", "run_order", "clock_position", "source_modified_utc", "technical_repeat"],
            ignore_index=True,
        )
    qc_checks = pd.concat(scan_qc_frames, ignore_index=True) if scan_qc_frames else pd.DataFrame()
    channel_features = pd.concat(signal_feature_frames, ignore_index=True) if signal_feature_frames else pd.DataFrame()
    if not channel_features.empty:
        channel_features = add_relative_features(channel_features, scans, signal_cache)
        channel_features["feature_implementation_sha256"] = code_sha256
    ml_matrix = build_ml_feature_matrix(channel_features, scans) if not scans.empty else pd.DataFrame()
    definitions = feature_definitions(config["feature_set"]["feature_set_id"])
    definitions["implementation_sha256"] = code_sha256
    events = build_event_table(scans, config)
    assets, experiments, probes, channels = _build_registries(config)
    errors = pd.DataFrame(ingest_errors)
    if errors.empty:
        errors = pd.DataFrame(columns=["source_path", "relative_path", "scan_id", "error_type", "message"])

    paths: dict[str, Any] = {}
    paths["raw_files"] = _relative_outputs(write_dataframe(raw_files, output / "catalog" / "raw_files"), output)
    paths["assets"] = _relative_outputs(write_dataframe(assets, output / "catalog" / "assets"), output)
    paths["experiments"] = _relative_outputs(write_dataframe(experiments, output / "catalog" / "experiments"), output)
    paths["probes"] = _relative_outputs(write_dataframe(probes, output / "catalog" / "probes"), output)
    paths["channels"] = _relative_outputs(write_dataframe(channels, output / "catalog" / "channels"), output)
    paths["strain_files"] = _relative_outputs(write_dataframe(strain_files, output / "catalog" / "strain_files"), output)
    paths["scans"] = _relative_outputs(write_dataframe(scans, output / "catalog" / "scans"), output)
    paths["events"] = _relative_outputs(write_dataframe(events, output / "catalog" / "events"), output)
    paths["qc_checks"] = _relative_outputs(write_dataframe(qc_checks, output / "catalog" / "qc_checks"), output)
    paths["ingest_errors"] = _relative_outputs(write_dataframe(errors, output / "catalog" / "ingest_errors"), output)
    paths["channel_features"] = _relative_outputs(write_dataframe(channel_features, output / "gold" / "channel_features"), output)
    paths["ml_feature_matrix"] = _relative_outputs(write_dataframe(ml_matrix, output / "gold" / "ml_feature_matrix"), output)
    paths["feature_definitions"] = _relative_outputs(write_dataframe(definitions, output / "gold" / "feature_definitions"), output)

    labels_sha = sha256_file(config["_labels_path"]) if config.get("_labels_path") and Path(config["_labels_path"]).exists() else "none"
    dataset_fingerprint = stable_fingerprint(
        [f"{row['relative_path']}|{row['sha256']}" for row in raw_rows]
        + [config["_config_sha256"], labels_sha, __version__, code_sha256]
    )
    dataset_version = f"1.0.0+{dataset_fingerprint[:12]}"
    status_counts = scans["scan_qc_status"].value_counts().to_dict() if not scans.empty else {}
    index = {
        "schema_version": "1.0",
        "dataset_id": config["experiment"]["experiment_id"],
        "dataset_version": dataset_version,
        "dataset_fingerprint_sha256": dataset_fingerprint,
        "pipeline_version": __version__,
        "pipeline_code_sha256": code_sha256,
        "signal_standardization_id": signal_standardization_id,
        "signal_standardizer_version": SIGNAL_STANDARDIZER_VERSION,
        "strain_standardizer_version": STRAIN_STANDARDIZER_VERSION,
        "pipeline_run_id": pipeline_run_id,
        "created_at_utc": utc_now(),
        "source_root_registered": str(source_root),
        "snapshot_mode": snapshot_mode,
        "config_sha256": config["_config_sha256"],
        "labels_sha256": labels_sha,
        "counts": {
            "source_files": int(len(raw_files)),
            "sensor_scans_discovered": int(len(scan_meta_rows)),
            "sensor_scans_completed": int((scans["scan_qc_status"] != "FAIL").sum()) if not scans.empty else 0,
            "sensor_scans_failed": int((scans["scan_qc_status"] == "FAIL").sum()) if not scans.empty else 0,
            "primary_stress_feature_qc_failed": int((scans["primary_stress_feature_qc_status"] == "FAIL").sum()) if not scans.empty else 0,
            "strain_files_standardized": int(len(strain_files)),
            "strain_values_standardized": int(strain_files["value_count"].sum()) if not strain_files.empty else 0,
            "channel_feature_rows": int(len(channel_features)),
            "ingest_errors": int(len(errors)),
        },
        "qc_status_counts": {str(key): int(value) for key, value in status_counts.items()},
        "coordinate_policy": {
            "raw_coordinate": "sample_index",
            "normalized_coordinate": "pipe_position_norm_between_detected_entry_exit",
            "physical_distance_available": bool(config["signal_schema"].get("pull_speed_mps") and config["signal_schema"].get("sample_rate_hz")),
            "warning": "无编码器/速度标定时，归一化位置不得解释为精确米制坐标",
        },
        "label_policy": {
            "labels_separate_from_signal": True,
            "direct_mpa_prediction_enabled": False,
            "split_unit": "pipe_id + experiment_id + run_id",
        },
        "tables": paths,
        "signal_partition_template": f"silver/signals/{signal_standardization_id}/{{scan_id}}.parquet",
        "strain_partition_template": f"silver/strain/{STRAIN_STANDARDIZER_VERSION}/{{strain_file_id}}.parquet",
        "sqlite_catalog": "catalog/catalog.sqlite",
        "release_manifest": f"releases/{dataset_version}/release_manifest.json",
    }
    atomic_write_json(output / "dataset_index.json", index)

    sqlite_tables = {
        "raw_files": raw_files,
        "assets": assets,
        "experiments": experiments,
        "probes": probes,
        "channels": channels,
        "strain_files": strain_files,
        "scans": scans,
        "events": events,
        "qc_checks": qc_checks,
        "channel_features": channel_features,
        "ml_feature_matrix": ml_matrix,
        "feature_definitions": definitions,
        "ingest_errors": errors,
    }
    write_sqlite_catalog(
        output / "catalog" / "catalog.sqlite", sqlite_tables,
        {"dataset_id": index["dataset_id"], "dataset_version": dataset_version,
         "dataset_fingerprint_sha256": dataset_fingerprint, "pipeline_run_id": pipeline_run_id},
    )
    run_summary = {
        **index,
        "started_at_utc": started_at,
        "finished_at_utc": utc_now(),
        "python": sys.version,
        "platform": platform.platform(),
        "config": config_without_runtime(config),
    }
    atomic_write_json(output / "runs" / pipeline_run_id / "run_summary.json", run_summary)
    _freeze_release(output, dataset_version, index)
    return index


def _snapshot_blob(source_path: Path, file_sha: str, output: Path) -> Path:
    suffix = source_path.suffix.casefold()
    target = output / "raw" / "blobs" / "sha256" / file_sha[:2] / f"{file_sha}{suffix}"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.stat().st_size != source_path.stat().st_size:
            raise IOError(f"内容寻址目标大小冲突: {target}")
        return target
    temporary = target.with_suffix(target.suffix + ".tmp")
    shutil.copy2(source_path, temporary)
    if sha256_file(temporary) != file_sha:
        temporary.unlink(missing_ok=True)
        raise IOError(f"原始文件副本哈希校验失败: {source_path}")
    temporary.replace(target)
    return target


def _load_previous_file_cache(path: Path) -> dict[tuple[str, int, int], str]:
    if not path.exists():
        return {}
    try:
        table = pd.read_csv(path, encoding="utf-8-sig")
    except Exception:
        return {}
    cache: dict[tuple[str, int, int], str] = {}
    for _, row in table.iterrows():
        try:
            mtime_ns = int(pd.Timestamp(row["source_modified_utc"]).timestamp() * 1_000_000_000)
            cache[(str(row["source_path"]), int(row["size_bytes"]), mtime_ns)] = str(row["sha256"])
        except Exception:
            continue
    return cache


def _load_previous_strain_cache(path: Path, output: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    try:
        table = pd.read_csv(path, encoding="utf-8-sig")
    except Exception:
        return {}
    result: dict[str, dict[str, Any]] = {}
    for _, row in table.iterrows():
        if str(row.get("strain_standardizer_version")) != STRAIN_STANDARDIZER_VERSION:
            continue
        partition = row.get("silver_strain_path")
        if not isinstance(partition, str) or not (output / Path(partition)).exists():
            continue
        result[str(row["source_file_id"])] = {
            key: (None if pd.isna(value) else value) for key, value in row.to_dict().items()
        }
    return result


def _pipeline_code_fingerprint() -> str:
    package_root = Path(__file__).resolve().parent
    parts = []
    for path in sorted(package_root.glob("*.py"), key=lambda value: value.name):
        parts.append(f"{path.name}|{sha256_file(path)}")
    return stable_fingerprint(parts)


def _relative_outputs(paths: dict[str, str], output: Path) -> dict[str, str]:
    return {kind: relative_posix(Path(path), output) for kind, path in paths.items()}


def _match_strain_run(relative_path: str, config: dict[str, Any]) -> tuple[str | None, str]:
    normalized = relative_path.replace("\\", "/")
    for rule in config.get("strain_run_rules", []):
        if str(rule["path_contains"]).replace("\\", "/") in normalized:
            return rule.get("run_id"), rule.get("alignment_status", "registered")
    return None, "unmapped"


def _build_registries(config: dict[str, Any]) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    experiment = config["experiment"]
    asset_fields = [
        "pipe_id", "material", "pipe_length_m", "outer_diameter_mm", "wall_thickness_mm",
        "yield_strength_mpa", "tensile_strength_mpa",
    ]
    asset = {field: experiment.get(field) for field in asset_fields}
    asset.update(
        coordinate_origin="pipe_center_for_geometry_priors",
        axial_positive_direction="not_yet_registered",
        stress_sign_convention="tension_positive_compression_negative",
    )
    experiment_row = {
        "experiment_id": experiment["experiment_id"],
        "campaign_id": experiment["campaign_id"],
        "pipe_id": experiment["pipe_id"],
        "source_root_registered": experiment["source_root"],
        "inner_head_half_span_m": experiment.get("inner_head_half_span_m"),
        "support_half_span_m": experiment.get("support_half_span_m"),
        "sample_rate_hz": config["signal_schema"].get("sample_rate_hz"),
        "pull_speed_mps": config["signal_schema"].get("pull_speed_mps"),
        "nominal_liftoff_mm": config["signal_schema"].get("nominal_liftoff_mm"),
        "operator": None,
        "ambient_temperature_c": None,
        "protocol_version": None,
        "metadata_completeness_status": "WARN",
    }
    unique_probes: dict[str, dict[str, Any]] = {}
    for folder, spec in config["probe_aliases"].items():
        probe_id = spec["probe_id"]
        unique_probes.setdefault(probe_id, {
            "probe_id": probe_id,
            "probe_family": spec.get("probe_family"),
            "magnetization_mode": spec.get("magnetization_mode"),
            "pole_geometry": spec.get("pole_geometry"),
            "source_folder_aliases": [],
            "device_serial_number": None,
            "sensor_layout_version": "ZYX_config_v1",
            "magnetizing_current_a": None,
            "cover_material": None,
            "cover_thickness_mm": None,
            "calibration_id": None,
        })
        unique_probes[probe_id]["source_folder_aliases"].append(folder)
    for row in unique_probes.values():
        row["source_folder_aliases"] = "|".join(sorted(set(row["source_folder_aliases"])))

    schema = config["signal_schema"]
    channel_rows: list[dict[str, Any]] = []
    for column_count in sorted({int(value) for value in schema["accepted_column_counts"]}):
        sensor_count = column_count // int(schema["columns_per_sensor"])
        layout_id = f"{column_count}col_{''.join(schema['axis_order'])}"
        for sensor_id in range(1, sensor_count + 1):
            for axis_index, axis in enumerate(schema["axis_order"]):
                channel_rows.append({
                    "layout_id": layout_id,
                    "channel_id": f"{layout_id}_s{sensor_id:02d}_{axis}",
                    "sensor_id": sensor_id,
                    "source_column_index": (sensor_id - 1) * int(schema["columns_per_sensor"]) + axis_index + 1,
                    "axis_raw": axis,
                    "axis_pipe": "unmapped",
                    "unit": "adc_count",
                    "sample_rate_hz": schema.get("sample_rate_hz"),
                    "preferred_for_analysis": sensor_count == 1 or sensor_id in schema.get("preferred_sensor_ids_for_45_columns", []),
                    "known_excluded": sensor_id in schema.get("known_excluded_sensor_ids", []),
                    "polarity": "not_registered",
                    "calibration_id": None,
                })
    return (
        pd.DataFrame([asset]), pd.DataFrame([experiment_row]),
        pd.DataFrame(unique_probes.values()), pd.DataFrame(channel_rows),
    )


def _freeze_release(output: Path, version: str, index: dict[str, Any]) -> None:
    release = output / "releases" / version
    release.mkdir(parents=True, exist_ok=True)
    for source in [
        output / "catalog" / "scans.parquet",
        output / "catalog" / "events.parquet",
        output / "catalog" / "strain_files.parquet",
        output / "catalog" / "qc_checks.parquet",
        output / "gold" / "channel_features.parquet",
        output / "gold" / "ml_feature_matrix.parquet",
        output / "gold" / "feature_definitions.parquet",
    ]:
        target = release / source.name
        if not target.exists():
            shutil.copy2(source, target)
    manifest = dict(index)
    manifest["frozen_release"] = True
    manifest["frozen_tables"] = sorted(path.name for path in release.glob("*.parquet"))
    atomic_write_json(release / "release_manifest.json", manifest)
