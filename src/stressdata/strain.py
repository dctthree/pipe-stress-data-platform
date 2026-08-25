from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .utils import relative_posix, sha256_text
from .xlsxraw import read_sheet_rows


STRAIN_STANDARDIZER_VERSION = "1.0.0"


def standardize_strain_file(
    path: Path,
    source_file_id: str,
    experiment_id: str,
    output_root: Path,
) -> tuple[dict[str, Any], pd.DataFrame]:
    strain_file_id = "strain_" + source_file_id.removeprefix("file_sha256_")[:20]
    if path.suffix.casefold() == ".xlsx":
        kind, long_table, sheet_name = _read_xlsx(path, strain_file_id, source_file_id, experiment_id)
    elif path.suffix.casefold() == ".txt":
        kind, long_table, sheet_name = _read_txt(path, strain_file_id, source_file_id, experiment_id)
    else:
        raise ValueError(f"不支持的应变文件: {path.suffix}")
    target = output_root / "silver" / "strain" / STRAIN_STANDARDIZER_VERSION / f"{strain_file_id}.parquet"
    target.parent.mkdir(parents=True, exist_ok=True)
    long_table.to_parquet(target, index=False, compression="zstd")
    numeric = pd.to_numeric(long_table["strain_microstrain"], errors="coerce")
    summary = {
        "strain_file_id": strain_file_id,
        "source_file_id": source_file_id,
        "experiment_id": experiment_id,
        "source_path": str(path),
        "workbook_or_text_kind": kind,
        "strain_standardizer_version": STRAIN_STANDARDIZER_VERSION,
        "sheet_name": sheet_name,
        "record_count": int(long_table["record_index"].nunique()),
        "channel_count": int(long_table["channel_id"].nunique()),
        "value_count": int(len(long_table)),
        "missing_value_fraction": float(numeric.isna().mean()),
        "timestamp_start": _timestamp_bound(long_table["timestamp"], "min"),
        "timestamp_end": _timestamp_bound(long_table["timestamp"], "max"),
        "silver_strain_path": relative_posix(target, output_root),
        "strain_qc_status": "PASS" if len(long_table) and numeric.notna().mean() >= 0.90 else "WARN",
        "unit": "microstrain",
        "coordinate_note": "location_description保留采集软件原值；尚未转换到统一管道坐标",
    }
    return summary, long_table.head(0)


def _read_xlsx(path: Path, strain_file_id: str, source_file_id: str, experiment_id: str):
    sheet_name, rows = read_sheet_rows(path)
    if len(rows) < 3:
        raise ValueError("XLSX有效行不足3")
    first = str(rows[0][0] or "")
    if first.casefold().startswith("time["):
        kind = "continuous_1hz"
        metadata_columns = 1
        channels = [_channel_name(value, index + 1) for index, value in enumerate(rows[0][1:])]
        descriptions = [str(value or "") for value in rows[1][1:1 + len(channels)]]
        records = rows[2:]
        times = [_excel_or_text_time(row[0] if row else None) for row in records]
        condition = [None] * len(records)
        value_rows = [row[metadata_columns:metadata_columns + len(channels)] for row in records]
    else:
        kind = "stage_point_summary"
        metadata_columns = 3
        channels = [_channel_name(value, index + 1) for index, value in enumerate(rows[0][metadata_columns:])]
        descriptions = [str(value or "") for value in rows[1][metadata_columns:metadata_columns + len(channels)]]
        records = rows[2:]
        times = [_excel_or_text_time(row[1] if len(row) > 1 else None) for row in records]
        condition = [row[2] if len(row) > 2 else None for row in records]
        value_rows = [row[metadata_columns:metadata_columns + len(channels)] for row in records]
    return kind, _make_long(
        strain_file_id, source_file_id, experiment_id, channels, descriptions,
        value_rows, times, condition
    ), sheet_name


def _read_txt(path: Path, strain_file_id: str, source_file_id: str, experiment_id: str):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    lines = [line for line in lines if line.strip()]
    if len(lines) < 3:
        raise ValueError("TXT有效行不足3")
    header = re.split(r"\s+", lines[0].strip())
    channels = [_channel_name(value, index + 1) for index, value in enumerate(header[3:])]
    records: list[list[str]] = []
    times: list[pd.Timestamp | None] = []
    for line in lines[2:]:
        tokens = re.split(r"\s+", line.strip())
        if len(tokens) < 3:
            continue
        times.append(_excel_or_text_time(tokens[1] + " " + tokens[2]))
        values = tokens[3:3 + len(channels)]
        values += [None] * (len(channels) - len(values))
        records.append(values)
    descriptions = [""] * len(channels)
    conditions = [None] * len(records)
    return "stage_point_text", _make_long(
        strain_file_id, source_file_id, experiment_id, channels, descriptions,
        records, times, conditions
    ), "text"


def _make_long(
    strain_file_id: str,
    source_file_id: str,
    experiment_id: str,
    channels: list[str],
    descriptions: list[str],
    value_rows: list[list[Any]],
    times: list[Any],
    conditions: list[Any],
) -> pd.DataFrame:
    unique_channels = _deduplicate(channels)
    wide_raw = pd.DataFrame(value_rows, columns=unique_channels)
    wide = wide_raw.apply(pd.to_numeric, errors="coerce")
    non_numeric = wide_raw.where(wide.isna() & wide_raw.notna(), None)
    wide.insert(0, "condition_raw", conditions)
    wide.insert(0, "timestamp", pd.to_datetime(times, errors="coerce"))
    wide.insert(0, "record_index", np.arange(1, len(wide) + 1, dtype=np.int64))
    long = wide.melt(
        id_vars=["record_index", "timestamp", "condition_raw"],
        var_name="channel_id", value_name="strain_microstrain"
    )
    non_numeric.insert(0, "condition_raw", conditions)
    non_numeric.insert(0, "timestamp", pd.to_datetime(times, errors="coerce"))
    non_numeric.insert(0, "record_index", np.arange(1, len(non_numeric) + 1, dtype=np.int64))
    non_numeric_long = non_numeric.melt(
        id_vars=["record_index", "timestamp", "condition_raw"],
        var_name="channel_id", value_name="raw_non_numeric_token"
    )
    long["raw_non_numeric_token"] = non_numeric_long["raw_non_numeric_token"].to_numpy()
    description_map = dict(zip(unique_channels, descriptions))
    long.insert(0, "experiment_id", experiment_id)
    long.insert(0, "source_file_id", source_file_id)
    long.insert(0, "strain_file_id", strain_file_id)
    long["location_description"] = long["channel_id"].map(description_map).fillna("")
    uid_map = {
        channel: "strain_channel_" + sha256_text(f"{channel}|{description_map.get(channel, '')}")[:16]
        for channel in unique_channels
    }
    long["strain_channel_uid"] = long["channel_id"].map(uid_map)
    parsed = long["channel_id"].str.extract(r"^(?P<gauge_id>\d+)-(?P<direction_code>\d+)")
    long["gauge_id"] = pd.to_numeric(parsed["gauge_id"], errors="coerce").astype("Int64")
    long["direction_code"] = pd.to_numeric(parsed["direction_code"], errors="coerce").astype("Int64")
    long["direction"] = long["direction_code"].map({1: "circumferential", 3: "axial"}).fillna("unknown")
    long["unit"] = "microstrain"
    long["value_status"] = np.select(
        [long["strain_microstrain"].notna(), long["raw_non_numeric_token"].notna()],
        ["valid", "unbalanced_or_non_numeric"], default="missing"
    )
    return long


def _channel_name(value: Any, index: int) -> str:
    text = str(value or "").strip()
    match = re.match(r"([^\[]+)", text)
    candidate = match.group(1).strip() if match else text
    return candidate or f"channel_{index:03d}"


def _deduplicate(values: list[str]) -> list[str]:
    counts: dict[str, int] = {}
    result: list[str] = []
    for value in values:
        counts[value] = counts.get(value, 0) + 1
        result.append(value if counts[value] == 1 else f"{value}__dup{counts[value]}")
    return result


def _excel_or_text_time(value: Any):
    if value is None:
        return pd.NaT
    if isinstance(value, (int, float)) and np.isfinite(value):
        return pd.Timestamp("1899-12-30") + pd.to_timedelta(float(value), unit="D")
    return pd.to_datetime(value, errors="coerce")


def _timestamp_bound(values: pd.Series, operation: str) -> str | None:
    timestamps = pd.to_datetime(values, errors="coerce").dropna()
    if timestamps.empty:
        return None
    value = timestamps.min() if operation == "min" else timestamps.max()
    return value.isoformat()
