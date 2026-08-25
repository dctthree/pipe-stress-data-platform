from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


SIGNAL_STANDARDIZER_VERSION = "1.0.0"


def process_sensor_scan(
    path: Path,
    meta: dict[str, Any],
    config: dict[str, Any],
) -> tuple[dict[str, Any], pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[tuple[int, str], np.ndarray]]:
    schema = config["signal_schema"]
    checks: list[dict[str, Any]] = []
    frame = pd.read_csv(path, low_memory=False)
    numeric = frame.apply(pd.to_numeric, errors="coerce")
    non_numeric_fraction = float((numeric.isna() & frame.notna()).to_numpy().mean()) if numeric.size else 1.0
    numeric = numeric.loc[~numeric.isna().all(axis=1)]
    values = numeric.to_numpy(dtype=float, copy=True)
    n_rows, n_columns = values.shape if values.ndim == 2 else (0, 0)

    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "minimum_rows", n_rows >= int(schema["minimum_rows"]),
              n_rows, f">={schema['minimum_rows']}", "FAIL", "有效数据行数")
    accepted = {int(value) for value in schema["accepted_column_counts"]}
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "column_schema", n_columns in accepted,
              n_columns, sorted(accepted), "FAIL", "列数必须匹配已注册的传感器布局")
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "numeric_parse", non_numeric_fraction <= 0.001,
              non_numeric_fraction, "<=0.001", "FAIL" if non_numeric_fraction > 0.01 else "WARN", "非数值单元比例")
    for field in ["sample_rate_hz", "pull_speed_mps", "nominal_liftoff_mm"]:
        add_check(checks, meta["scan_id"], "metadata", meta["scan_id"], f"metadata_{field}", schema.get(field) is not None,
                  schema.get(field), "not_null", "WARN", f"缺少{field}时禁止相应物理量解释")

    if n_rows < int(schema["minimum_rows"]) or n_columns not in accepted:
        raise SignalSchemaError(f"{path.name}: 行列结构不合格 ({n_rows}x{n_columns})")

    axis_order = list(schema["axis_order"])
    cps = int(schema["columns_per_sensor"])
    sensor_count = n_columns // cps
    cube = values.reshape(n_rows, sensor_count, cps)
    sensor_ids = list(range(1, sensor_count + 1))
    preferred = [int(value) for value in schema.get("preferred_sensor_ids_for_45_columns", [])]
    if sensor_count == 1:
        selected_ids = [1]
    elif preferred:
        selected_ids = [value for value in preferred if value <= sensor_count]
    else:
        selected_ids = sensor_ids

    clip_limit = schema.get("clip_absolute_value")
    clip_limit = float(clip_limit) if clip_limit is not None else math.inf
    sentinels = [float(value) for value in schema.get("sentinel_values", [])]
    max_clip = float(schema.get("maximum_clip_fraction", 0.05))
    active_by_sensor: dict[int, bool] = {}
    valid_axis: dict[tuple[int, str], bool] = {}
    clip_by_axis: dict[tuple[int, str], float] = {}
    sentinel_by_axis: dict[tuple[int, str], float] = {}

    for sensor_id in sensor_ids:
        sensor = cube[:, sensor_id - 1, :]
        sentinel_fraction_all = _sentinel_mask(sensor, sentinels).mean() if sensor.size else 1.0
        finite_std = np.nanstd(sensor, axis=0)
        active_by_sensor[sensor_id] = bool(np.any(finite_std > 1e-9) and sentinel_fraction_all < 0.95)
        for axis_index, axis in enumerate(axis_order):
            vector = sensor[:, axis_index]
            finite = np.isfinite(vector)
            clip = finite & (np.abs(vector) >= clip_limit)
            sentinel = finite & _sentinel_mask(vector, sentinels)
            clip_fraction = float(clip.mean())
            sentinel_fraction = float(sentinel.mean())
            clip_by_axis[(sensor_id, axis)] = clip_fraction
            sentinel_by_axis[(sensor_id, axis)] = sentinel_fraction
            usable = finite & ~clip
            if sentinel_fraction > 0.20:
                usable &= ~sentinel
            valid = bool(usable.sum() >= max(20, round(0.55 * n_rows)) and clip_fraction <= max_clip and np.nanstd(vector[usable]) > 1e-9)
            valid_axis[(sensor_id, axis)] = valid
            add_check(checks, meta["scan_id"], "channel", f"s{sensor_id:02d}_{axis}", "clip_fraction",
                      clip_fraction <= max_clip, clip_fraction, f"<={max_clip}", "WARN", "ADC削顶/饱和比例")
            add_check(checks, meta["scan_id"], "channel", f"s{sensor_id:02d}_{axis}", "sentinel_fraction",
                      sentinel_fraction <= 0.20, sentinel_fraction, "<=0.20", "WARN", "哨兵值比例")

    effective = sum(active_by_sensor.get(sensor_id, False) for sensor_id in selected_ids)
    required = 1 if sensor_count == 1 else int(schema.get("minimum_effective_sensors_multi", 1))
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "effective_sensor_count", effective >= required,
              effective, f">={required}", "FAIL", "有效首选传感器数量")
    primary_axis = axis_order[-1]
    primary_valid = sum(valid_axis.get((sensor_id, primary_axis), False) for sensor_id in selected_ids)
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "primary_axis_valid_sensor_count",
              primary_valid >= required, primary_valid, f">={required}", "WARN",
              f"主应力候选轴{primary_axis}的有效传感器数量")

    selected_cube = cube[:, np.array(selected_ids) - 1, :]
    pipe_start, pipe_end, edge_snr, edge_fallback = locate_pipe_interval(
        selected_cube, clip_limit, sentinels
    )
    pipe_fraction = (pipe_end - pipe_start + 1) / n_rows
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "pipe_interval_fraction",
              pipe_fraction >= 0.45, pipe_fraction, ">=0.45", "FAIL", "自动检测的有效管内区占比")
    add_check(checks, meta["scan_id"], "scan", meta["scan_id"], "pipe_edge_detection",
              not edge_fallback, edge_snr, "automatic_detection", "WARN", "进出管边缘检测是否使用回退区间")

    signal_rows: list[pd.DataFrame] = []
    feature_rows: list[dict[str, Any]] = []
    cache: dict[tuple[int, str], np.ndarray] = {}
    in_pipe = np.zeros(n_rows, dtype=bool)
    in_pipe[pipe_start:pipe_end + 1] = True
    position = np.full(n_rows, np.nan)
    position[in_pipe] = np.linspace(0.0, 1.0, int(in_pipe.sum()))
    sample_rate = schema.get("sample_rate_hz")
    sample_time = np.arange(n_rows, dtype=float) / float(sample_rate) if sample_rate else np.full(n_rows, np.nan)

    for sensor_id in selected_ids:
        for axis_index, axis in enumerate(axis_order):
            vector = cube[:, sensor_id - 1, axis_index].astype(float, copy=False)
            finite = np.isfinite(vector)
            clipped = finite & (np.abs(vector) >= clip_limit)
            sentinel = finite & _sentinel_mask(vector, sentinels)
            channel = pd.DataFrame({
                "scan_id": meta["scan_id"],
                "sample_index": np.arange(n_rows, dtype=np.int64),
                "raw_row_index": np.arange(1, n_rows + 1, dtype=np.int64),
                "sample_time_s": sample_time,
                "pipe_position_norm": position,
                "in_pipe": in_pipe,
                "sensor_id": sensor_id,
                "axis": axis,
                "source_column_index": (sensor_id - 1) * cps + axis_index + 1,
                "value_raw": vector,
                "is_finite": finite,
                "is_sentinel": sentinel,
                "is_clipped": clipped,
                "channel_qc_valid": valid_axis[(sensor_id, axis)],
            })
            signal_rows.append(channel)
            pipe_vector = vector[in_pipe]
            pipe_good = np.isfinite(pipe_vector) & (np.abs(pipe_vector) < clip_limit)
            if sentinel_by_axis[(sensor_id, axis)] > 0.20:
                pipe_good &= ~_sentinel_mask(pipe_vector, sentinels)
            clean = pipe_vector[pipe_good]
            cache[(sensor_id, axis)] = clean
            features = basic_features(clean, int(config["feature_set"].get("histogram_bins", 32)))
            feature_rows.append({
                "scan_id": meta["scan_id"],
                "feature_set_id": config["feature_set"]["feature_set_id"],
                "sensor_id": sensor_id,
                "axis": axis,
                "channel_qc_valid": valid_axis[(sensor_id, axis)],
                "clip_fraction": clip_by_axis[(sensor_id, axis)],
                "sentinel_fraction": sentinel_by_axis[(sensor_id, axis)],
                **features,
            })

    qc = pd.DataFrame(checks)
    overall = qc_status(qc)
    update = {
        "raw_rows": n_rows,
        "signal_standardizer_version": SIGNAL_STANDARDIZER_VERSION,
        "raw_columns": n_columns,
        "sensor_count_in_file": sensor_count,
        "selected_sensor_ids": ",".join(str(value) for value in selected_ids),
        "effective_sensor_count": effective,
        "primary_axis": primary_axis,
        "primary_axis_valid_sensor_count": primary_valid,
        "primary_stress_feature_qc_status": "PASS" if primary_valid >= required else "FAIL",
        "pipe_start_index": pipe_start,
        "pipe_end_index": pipe_end,
        "pipe_fraction": pipe_fraction,
        "edge_snr": edge_snr,
        "edge_detection_fallback": edge_fallback,
        "scan_qc_status": overall,
        "sample_rate_hz": sample_rate,
        "pull_speed_mps": schema.get("pull_speed_mps"),
        "nominal_liftoff_mm": schema.get("nominal_liftoff_mm"),
    }
    return update, qc, pd.concat(signal_rows, ignore_index=True), pd.DataFrame(feature_rows), cache


class SignalSchemaError(ValueError):
    pass


def add_check(
    rows: list[dict[str, Any]], scan_id: str, level: str, scope_id: str,
    name: str, passed: bool, value: Any, threshold: Any, failure_severity: str,
    message: str,
) -> None:
    outcome = "PASS" if passed else failure_severity
    rows.append({
        "scan_id": scan_id,
        "level": level,
        "scope_id": scope_id,
        "check_name": name,
        "outcome": outcome,
        "passed": bool(passed),
        "value": value,
        "threshold": str(threshold),
        "message": message,
    })


def qc_status(checks: pd.DataFrame) -> str:
    outcomes = set(checks["outcome"].astype(str)) if not checks.empty else {"FAIL"}
    if "FAIL" in outcomes:
        return "FAIL"
    if "WARN" in outcomes:
        return "WARN"
    return "PASS"


def locate_pipe_interval(data: np.ndarray, clip_limit: float, sentinels: list[float]) -> tuple[int, int, float, bool]:
    n = data.shape[0]
    flat = data.reshape(n, -1)
    scores: list[np.ndarray] = []
    for index in range(flat.shape[1]):
        vector = flat[:, index].astype(float, copy=True)
        invalid = ~np.isfinite(vector) | (np.abs(vector) >= clip_limit)
        if _sentinel_mask(vector, sentinels).mean() > 0.20:
            invalid |= _sentinel_mask(vector, sentinels)
        vector[invalid] = np.nan
        if np.isfinite(vector).sum() < max(20, round(0.40 * n)):
            continue
        smooth = smooth_1d(vector, max(1.0, n * 0.006))
        scale = max(robust_mad(np.diff(smooth)), 0.01 * robust_mad(smooth), 1.0)
        scores.append(np.abs(np.gradient(smooth)) / scale)
    if not scores:
        return max(0, round(0.08 * n)), min(n - 1, round(0.92 * n)), 0.0, True
    edge = np.nanmedian(np.column_stack(scores), axis=1)
    edge = gaussian_smooth(edge, max(1.0, n * 0.004))
    left_start = max(1, round(0.015 * n))
    left_end = max(left_start + 1, min(n - 2, round(0.36 * n)))
    right_start = min(n - 2, max(1, round(0.64 * n)))
    right_end = min(n - 1, max(right_start + 1, round(0.985 * n)))
    left_indices = np.arange(left_start, left_end + 1)
    right_indices = np.arange(right_start, right_end + 1)
    first = int(left_indices[np.nanargmax(edge[left_indices])])
    last = int(right_indices[np.nanargmax(edge[right_indices])])
    fallback = False
    if last - first + 1 < 0.45 * n:
        first, last, fallback = round(0.08 * n), round(0.92 * n), True
    trim = max(1, round(0.01 * (last - first + 1)))
    first, last = max(0, first + trim), min(n - 1, last - trim)
    median_edge = float(np.nanmedian(edge))
    peak = min(float(np.nanmax(edge[left_indices])), float(np.nanmax(edge[right_indices])))
    edge_snr = peak / max(median_edge, 1e-9)
    return first, last, edge_snr, fallback


def smooth_1d(vector: np.ndarray, sigma: float) -> np.ndarray:
    result = np.asarray(vector, dtype=float).copy()
    finite = np.isfinite(result)
    if finite.sum() < 3:
        return np.full_like(result, np.nan)
    indices = np.arange(result.size)
    result[~finite] = np.interp(indices[~finite], indices[finite], result[finite])
    result = pd.Series(result).rolling(3, center=True, min_periods=1).median().to_numpy()
    return gaussian_smooth(result, sigma)


def gaussian_smooth(vector: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.5:
        return np.asarray(vector, dtype=float)
    radius = max(1, int(math.ceil(4 * sigma)))
    x = np.arange(-radius, radius + 1, dtype=float)
    kernel = np.exp(-0.5 * (x / sigma) ** 2)
    kernel /= kernel.sum()
    padded = np.pad(np.asarray(vector, dtype=float), radius, mode="edge")
    return np.convolve(padded, kernel, mode="same")[radius:-radius]


def robust_mad(vector: np.ndarray) -> float:
    values = np.asarray(vector, dtype=float)
    values = values[np.isfinite(values)]
    if values.size == 0:
        return 0.0
    median = np.median(values)
    return float(1.4826 * np.median(np.abs(values - median)))


def basic_features(vector: np.ndarray, histogram_bins: int) -> dict[str, float | int]:
    values = np.asarray(vector, dtype=float)
    values = values[np.isfinite(values)]
    names = ["mean", "std", "median", "mad", "min", "max", "range", "q05", "q25", "q60", "q70", "q75", "q80", "q95",
             "iqr", "rms", "skewness", "kurtosis_excess", "diff_rms", "total_variation_per_sample", "spike_q99", "histogram_entropy"]
    if values.size < 3:
        return {"n_valid": int(values.size), **{name: np.nan for name in names}}
    mean = float(np.mean(values))
    centered = values - mean
    std = float(np.std(values, ddof=1))
    rms = float(np.sqrt(np.mean(values ** 2)))
    diff = np.diff(values)
    quantiles = np.quantile(values, [0.05, 0.25, 0.60, 0.70, 0.75, 0.80, 0.95])
    counts, _ = np.histogram(values, bins=max(4, histogram_bins))
    probability = counts[counts > 0] / counts.sum()
    entropy = float(-np.sum(probability * np.log2(probability)))
    skewness = float(np.mean(centered ** 3) / std ** 3) if std > 0 else 0.0
    kurtosis = float(np.mean(centered ** 4) / std ** 4 - 3.0) if std > 0 else 0.0
    return {
        "n_valid": int(values.size),
        "mean": mean,
        "std": std,
        "median": float(np.median(values)),
        "mad": robust_mad(values),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
        "range": float(np.ptp(values)),
        "q05": float(quantiles[0]),
        "q25": float(quantiles[1]),
        "q60": float(quantiles[2]),
        "q70": float(quantiles[3]),
        "q75": float(quantiles[4]),
        "q80": float(quantiles[5]),
        "q95": float(quantiles[6]),
        "iqr": float(quantiles[4] - quantiles[1]),
        "rms": rms,
        "skewness": skewness,
        "kurtosis_excess": kurtosis,
        "diff_rms": float(np.sqrt(np.mean(diff ** 2))) if diff.size else 0.0,
        "total_variation_per_sample": float(np.mean(np.abs(diff))) if diff.size else 0.0,
        "spike_q99": float(np.quantile(np.abs(diff), 0.99)) if diff.size else 0.0,
        "histogram_entropy": entropy,
    }


def _sentinel_mask(values: np.ndarray, sentinels: list[float]) -> np.ndarray:
    array = np.asarray(values)
    if not sentinels:
        return np.zeros(array.shape, dtype=bool)
    mask = np.zeros(array.shape, dtype=bool)
    for sentinel in sentinels:
        mask |= np.isclose(array, sentinel, equal_nan=False)
    return mask
