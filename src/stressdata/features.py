from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from .signal import robust_mad


RELATIVE_FEATURES = [
    "delta_mean",
    "delta_median",
    "delta_std",
    "delta_rms",
    "delta_iqr",
    "delta_entropy",
    "q60_delta",
    "q70_delta",
    "q75_delta",
    "q80_delta",
    "q_family_delta",
    "cdf_superiority",
]


def add_relative_features(
    channel_features: pd.DataFrame,
    scans: pd.DataFrame,
    signal_cache: dict[str, dict[tuple[int, str], np.ndarray]],
) -> pd.DataFrame:
    if channel_features.empty:
        return channel_features
    meta_columns = [
        "scan_id", "experiment_id", "pipe_id", "probe_id", "probe_family",
        "magnetization_mode", "pole_geometry", "run_id", "stage_mm",
        "clock_position", "technical_repeat", "recovery_min", "split_group",
        "stress_mpa_magnitude", "local_axial_stress_mpa", "label_status",
        "label_version", "use_for_supervised", "blind_flag", "scan_qc_status",
    ]
    available = [column for column in meta_columns if column in scans.columns]
    table = channel_features.merge(scans[available], on="scan_id", how="left", validate="many_to_one")
    for name in RELATIVE_FEATURES:
        table[name] = np.nan
    table["baseline_scan_id"] = None
    baseline_by_group: dict[tuple[str, int], str] = {}
    candidates = scans[
        np.isclose(pd.to_numeric(scans["stage_mm"], errors="coerce"), 0.0)
        & scans["recovery_min"].isna()
        & (scans["scan_qc_status"] != "FAIL")
    ].copy()
    if not candidates.empty:
        candidates = candidates.sort_values(["run_id", "clock_position", "technical_repeat", "source_modified_utc"])
        for (run_id, clock), group in candidates.groupby(["run_id", "clock_position"], dropna=False):
            baseline_by_group[(str(run_id), int(clock))] = str(group.iloc[0]["scan_id"])
    feature_index = table.set_index(["scan_id", "sensor_id", "axis"], drop=False)
    for row_index, row in table.iterrows():
        key = (str(row["run_id"]), int(row["clock_position"]))
        baseline_scan = baseline_by_group.get(key)
        if baseline_scan is None:
            continue
        baseline_key = (baseline_scan, int(row["sensor_id"]), str(row["axis"]))
        if baseline_key not in feature_index.index:
            continue
        baseline = feature_index.loc[baseline_key]
        if isinstance(baseline, pd.DataFrame):
            baseline = baseline.iloc[0]
        table.at[row_index, "baseline_scan_id"] = baseline_scan
        for current_name, baseline_name, output_name in [
            ("mean", "mean", "delta_mean"),
            ("median", "median", "delta_median"),
            ("std", "std", "delta_std"),
            ("rms", "rms", "delta_rms"),
            ("iqr", "iqr", "delta_iqr"),
            ("histogram_entropy", "histogram_entropy", "delta_entropy"),
            ("q60", "q60", "q60_delta"),
            ("q70", "q70", "q70_delta"),
            ("q75", "q75", "q75_delta"),
            ("q80", "q80", "q80_delta"),
        ]:
            table.at[row_index, output_name] = _difference(row[current_name], baseline[baseline_name])
        q_values = [table.at[row_index, name] for name in ["q60_delta", "q70_delta", "q75_delta", "q80_delta"]]
        table.at[row_index, "q_family_delta"] = float(np.nanmedian(q_values)) if np.isfinite(q_values).any() else np.nan
        current_vector = signal_cache.get(str(row["scan_id"]), {}).get((int(row["sensor_id"]), str(row["axis"])))
        baseline_vector = signal_cache.get(baseline_scan, {}).get((int(row["sensor_id"]), str(row["axis"])))
        table.at[row_index, "cdf_superiority"] = cdf_superiority(current_vector, baseline_vector)
    return table


def build_ml_feature_matrix(channel_features: pd.DataFrame, scans: pd.DataFrame) -> pd.DataFrame:
    matrix = scans.copy()
    if channel_features.empty:
        matrix["feature_analysis_status"] = "REJECTED_NO_FEATURES"
        return matrix
    aggregate_features = [
        "median", "mad", "std", "rms", "iqr", "diff_rms", "spike_q99", "histogram_entropy",
        *RELATIVE_FEATURES,
    ]
    output_rows: list[dict[str, Any]] = []
    for scan_id, scan_row in scans.set_index("scan_id", drop=False).iterrows():
        row = scan_row.to_dict()
        subset = channel_features[channel_features["scan_id"] == scan_id]
        valid_feature_count = 0
        for axis in sorted(subset["axis"].dropna().unique()):
            axis_rows = subset[(subset["axis"] == axis) & subset["channel_qc_valid"].astype(bool)]
            row[f"{axis}_valid_sensor_n"] = int(axis_rows["sensor_id"].nunique())
            for feature in aggregate_features:
                values = pd.to_numeric(axis_rows[feature], errors="coerce").to_numpy(dtype=float)
                values = values[np.isfinite(values)]
                prefix = f"{axis}_{feature}"
                if values.size:
                    median = float(np.median(values))
                    row[f"{prefix}_sensor_median"] = median
                    row[f"{prefix}_sensor_mad"] = robust_mad(values)
                    nonzero = values[np.abs(values) > 1e-12]
                    row[f"{prefix}_sign_consensus"] = (
                        float(np.mean(np.sign(nonzero) == np.sign(np.median(nonzero)))) if nonzero.size else np.nan
                    )
                    valid_feature_count += 1
                else:
                    row[f"{prefix}_sensor_median"] = np.nan
                    row[f"{prefix}_sensor_mad"] = np.nan
                    row[f"{prefix}_sign_consensus"] = np.nan
        row["valid_aggregated_feature_count"] = valid_feature_count
        if row.get("scan_qc_status") == "FAIL":
            row["feature_analysis_status"] = "REJECTED_QC"
        elif valid_feature_count == 0:
            row["feature_analysis_status"] = "REJECTED_NO_VALID_CHANNEL"
        else:
            row["feature_analysis_status"] = "ELIGIBLE_RELATIVE_ONLY"
        row["primary_stress_feature_status"] = (
            "ELIGIBLE" if row.get("primary_stress_feature_qc_status") == "PASS"
            else "REJECTED_PRIMARY_AXIS_QC"
        )
        row["direct_mpa_output_allowed"] = False
        row["direct_mpa_output_reason"] = "尚无跨新管道锁定标定模型；本表仅提供可追溯特征和已知实验标签"
        output_rows.append(row)
    return pd.DataFrame(output_rows)


def feature_definitions(feature_set_id: str) -> pd.DataFrame:
    rows = [
        ("mean", "mean(x)", "raw_count", "管内有效区均值"),
        ("median", "median(x)", "raw_count", "稳健中心位置"),
        ("mad", "1.4826*median(|x-median(x)|)", "raw_count", "稳健离散度"),
        ("std", "sample_std(x)", "raw_count", "整体波动"),
        ("rms", "sqrt(mean(x^2))", "raw_count", "能量幅值"),
        ("iqr", "Q75(x)-Q25(x)", "raw_count", "稳健分布宽度"),
        ("diff_rms", "sqrt(mean(diff(x)^2))", "raw_count/sample", "采样域粗糙度；无速度时不得称空间频率"),
        ("spike_q99", "Q99(|diff(x)|)", "raw_count/sample", "尖峰/摩擦敏感指标"),
        ("histogram_entropy", "-sum(p_i*log2(p_i))", "bit", "幅值分布信息熵"),
        ("q_family_delta", "median_q in {60,70,75,80}[Qq(x)-Qq(x_S0)]", "raw_count", "相对同轮同钟点零载的稳健分位差"),
        ("cdf_superiority", "P(x_stage>x_S0)-0.5", "1", "相对零载的分布优势度"),
    ]
    return pd.DataFrame([
        {
            "feature_set_id": feature_set_id,
            "feature_name": name,
            "feature_version": "1.0.0",
            "formula": formula,
            "unit": unit,
            "roi": "automatically_detected_in_pipe_interval",
            "baseline_rule": "same_run_same_clock_stage0_non_recovery" if "delta" in name or name == "cdf_superiority" else "none",
            "physical_or_engineering_meaning": meaning,
            "status": "candidate",
        }
        for name, formula, unit, meaning in rows
    ])


def cdf_superiority(current: np.ndarray | None, baseline: np.ndarray | None) -> float:
    if current is None or baseline is None:
        return np.nan
    current = np.asarray(current, dtype=float)
    baseline = np.asarray(baseline, dtype=float)
    current = current[np.isfinite(current)]
    baseline = np.sort(baseline[np.isfinite(baseline)])
    if current.size < 3 or baseline.size < 3:
        return np.nan
    left = np.searchsorted(baseline, current, side="left")
    right = np.searchsorted(baseline, current, side="right")
    wins = (left + right) / 2.0
    return float(np.mean(wins / baseline.size) - 0.5)


def _difference(current: Any, baseline: Any) -> float:
    try:
        current_value, baseline_value = float(current), float(baseline)
    except (TypeError, ValueError):
        return np.nan
    return current_value - baseline_value if np.isfinite(current_value) and np.isfinite(baseline_value) else np.nan
