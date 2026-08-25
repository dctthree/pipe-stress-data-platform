from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .utils import sha256_text


def should_exclude(path: Path, source_root: Path, config: dict[str, Any]) -> bool:
    try:
        relative = path.relative_to(source_root)
    except ValueError:
        return True
    excluded = {str(name).casefold() for name in config["discovery"].get("exclude_directory_names", [])}
    return any(part.casefold() in excluded for part in relative.parts[:-1])


def classify_file(path: Path, relative_path: str, config: dict[str, Any]) -> str:
    suffix = path.suffix.casefold()
    markers = config["discovery"].get("strain_directory_markers", [])
    in_strain = any(marker.casefold() in relative_path.casefold() for marker in markers)
    if suffix == ".csv" and not in_strain:
        return "sensor_raw"
    if in_strain:
        measurement_name = any(marker in path.stem for marker in ["取数", "原始数据", "原始文件"])
        if suffix in {".xlsx", ".xls"} or (suffix == ".txt" and measurement_name):
            return "strain_measurement"
        return "strain_acquisition_native"
    if suffix in {ext.casefold() for ext in config["discovery"].get("protocol_extensions", [])}:
        return "protocol_or_analysis_code"
    return "experiment_auxiliary"


def parse_scan_metadata(
    relative_path: str,
    file_sha256: str,
    config: dict[str, Any],
) -> dict[str, Any] | None:
    parts = Path(relative_path).parts
    if len(parts) < 3:
        return None
    probe_folder, run_folder = parts[0], parts[1]
    probe_spec = config["probe_aliases"].get(probe_folder)
    if probe_spec is None:
        normalized = probe_folder.rstrip("'‘’ ")
        for alias, candidate in config["probe_aliases"].items():
            if alias.rstrip("'‘’ ") == normalized:
                probe_spec = candidate
                break
    if probe_spec is None:
        return None
    stem = Path(relative_path).stem
    match = re.fullmatch(config["filename_parser"]["pattern"], stem, flags=re.IGNORECASE)
    if match is None:
        return None
    stage_mm = float(match.group("stage_mm"))
    clock_position = int(match.group("clock_position"))
    suffix = match.groupdict().get("suffix", "") or ""
    technical_repeat = 1
    for marker, repeat in config["filename_parser"].get("technical_repeat_markers", {}).items():
        if marker in suffix:
            technical_repeat = int(repeat)
    recovery_min: float | None = None
    recovery_pattern = config["filename_parser"].get("recovery_pattern")
    if recovery_pattern:
        recovery_match = re.search(recovery_pattern, suffix, flags=re.IGNORECASE)
        if recovery_match:
            recovery_min = float(recovery_match.group("recovery_min"))
    run_spec = None
    for candidate in config["run_rules"]:
        if candidate["probe_id"] == probe_spec["probe_id"] and candidate["folder_contains"] in run_folder:
            run_spec = candidate
            break
    if run_spec is None:
        return None
    stage_token = f"{stage_mm:g}"
    recovery_token = "" if recovery_min is None else f"_rec{recovery_min:g}m"
    stage_sequence = config.get("stage_sequences", {}).get(run_spec["run_id"], [])
    stage_order = next((index + 1 for index, value in enumerate(stage_sequence) if np.isclose(float(value), stage_mm)), None)
    loading_branch = "recovery" if recovery_min is not None else run_spec.get("default_loading_branch", "unknown")
    if technical_repeat > 1 and loading_branch == "loading":
        loading_branch = "technical_repeat"
    for override in config.get("stage_overrides", []):
        if override.get("run_id") == run_spec["run_id"] and np.isclose(float(override.get("stage_mm")), stage_mm):
            loading_branch = override.get("loading_branch", loading_branch)
            stage_order = override.get("stage_order", stage_order)
    semantic = (
        f"{config['experiment']['experiment_id']}|{probe_spec['probe_id']}|"
        f"{run_spec['run_id']}|{stage_token}|{clock_position}|{technical_repeat}|{recovery_token}"
    )
    scan_id = "pull_" + sha256_text(semantic + "|" + file_sha256)[:20]
    pipe_id = config["experiment"]["pipe_id"]
    experiment_id = config["experiment"]["experiment_id"]
    return {
        "scan_id": scan_id,
        "pull_id": scan_id,
        "experiment_id": experiment_id,
        "campaign_id": config["experiment"]["campaign_id"],
        "pipe_id": pipe_id,
        "probe_folder_raw": probe_folder,
        "probe_id": probe_spec["probe_id"],
        "probe_family": probe_spec.get("probe_family"),
        "magnetization_mode": probe_spec.get("magnetization_mode"),
        "pole_geometry": probe_spec.get("pole_geometry"),
        "run_folder_raw": run_folder,
        "run_id": run_spec["run_id"],
        "run_order": int(run_spec.get("run_order", 0)),
        "recommended_run": bool(run_spec.get("recommended", False)),
        "stage_mm": stage_mm,
        "stage_id": f"disp_{stage_mm:g}mm" + recovery_token,
        "stage_order": stage_order,
        "clock_position": clock_position,
        "local_stress_sign_convention": "tension_positive_at_6_compression_negative_at_12",
        "technical_repeat": technical_repeat,
        "recovery_min": recovery_min,
        "loading_branch": loading_branch,
        "split_group": f"{pipe_id}::{experiment_id}::{run_spec['run_id']}",
        "source_relative_path": relative_path,
    }


def load_labels(config: dict[str, Any]) -> pd.DataFrame:
    path = config.get("_labels_path")
    columns = [
        "run_id", "stage_mm", "clock_position", "recovery_min",
        "stress_mpa_magnitude", "local_axial_stress_mpa", "label_status",
        "label_source", "label_version", "use_for_supervised", "notes",
    ]
    if not path or not Path(path).exists():
        return pd.DataFrame(columns=columns)
    labels = pd.read_csv(path, encoding="utf-8-sig")
    for column in ["stage_mm", "clock_position", "recovery_min", "stress_mpa_magnitude", "local_axial_stress_mpa"]:
        labels[column] = pd.to_numeric(labels[column], errors="coerce")
    labels["use_for_supervised"] = labels["use_for_supervised"].astype(str).str.casefold().isin({"true", "1", "yes"})
    return labels


def attach_label(meta: dict[str, Any], labels: pd.DataFrame) -> dict[str, Any]:
    result = dict(meta)
    if labels.empty:
        return _empty_label(result)
    recovery = meta.get("recovery_min")
    same_recovery = labels["recovery_min"].isna() if recovery is None else np.isclose(labels["recovery_min"], recovery, equal_nan=False)
    mask = (
        (labels["run_id"] == meta["run_id"])
        & np.isclose(labels["stage_mm"], meta["stage_mm"])
        & (labels["clock_position"] == meta["clock_position"])
        & same_recovery
    )
    matched = labels.loc[mask]
    if len(matched) != 1:
        return _empty_label(result, "missing" if matched.empty else "ambiguous")
    row = matched.iloc[0]
    for column in [
        "stress_mpa_magnitude", "local_axial_stress_mpa", "label_status",
        "label_source", "label_version", "use_for_supervised", "notes",
    ]:
        value = row.get(column)
        result[column] = None if pd.isna(value) else value
    result["blind_flag"] = result.get("stress_mpa_magnitude") is None
    result["label_access_policy"] = "training_allowed" if result.get("use_for_supervised") else "analysis_only_or_blind"
    return result


def _empty_label(result: dict[str, Any], status: str = "blind") -> dict[str, Any]:
    result.update(
        stress_mpa_magnitude=None,
        local_axial_stress_mpa=None,
        label_status=status,
        label_source=None,
        label_version=None,
        use_for_supervised=False,
        notes=None,
        blind_flag=True,
        label_access_policy="withheld",
    )
    return result
