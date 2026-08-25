from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from .utils import sha256_text


def build_event_table(scans: pd.DataFrame, config: dict[str, Any]) -> pd.DataFrame:
    columns = [
        "event_id", "scan_id", "event_type", "sample_index", "pipe_position_norm",
        "x_from_pipe_center_m", "confidence", "event_source", "detection_method",
        "algorithm_version", "manually_verified", "notes",
    ]
    if scans.empty:
        return pd.DataFrame(columns=columns)
    length = config["experiment"].get("pipe_length_m")
    head = config["experiment"].get("inner_head_half_span_m")
    support = config["experiment"].get("support_half_span_m")
    welds = config["experiment"].get("weld_positions_from_center_m", []) or []
    rows: list[dict[str, Any]] = []
    for _, scan in scans.iterrows():
        if scan.get("pipe_start_index") is None or pd.isna(scan.get("pipe_start_index")):
            continue
        first, last = int(scan["pipe_start_index"]), int(scan["pipe_end_index"])
        fallback = bool(scan.get("edge_detection_fallback", False))
        edge_snr = float(scan.get("edge_snr", 0.0) or 0.0)
        edge_confidence = 0.20 if fallback else float(np.clip(edge_snr / 20.0, 0.40, 0.95))
        _append(rows, scan["scan_id"], "pipe_entry", first, 0.0,
                -float(length) / 2 if length else None, edge_confidence,
                "automatic", "multichannel_derivative_edge", "1.0.0", "管端强变化检测")
        _append(rows, scan["scan_id"], "pipe_exit", last, 1.0,
                float(length) / 2 if length else None, edge_confidence,
                "automatic", "multichannel_derivative_edge", "1.0.0", "管端强变化检测")
        if length:
            priors: list[tuple[str, float]] = []
            if support is not None:
                priors.extend([("support_left", -float(support)), ("support_right", float(support))])
            if head is not None:
                priors.extend([("head_left", -float(head)), ("head_right", float(head))])
            priors.extend(("weld", float(position)) for position in welds)
            for event_type, x_position in priors:
                normalized = (x_position + float(length) / 2) / float(length)
                sample = int(round(first + normalized * (last - first)))
                _append(rows, scan["scan_id"], event_type, sample, normalized, x_position, 0.50,
                        "geometry_prior", "linear_map_between_detected_pipe_ends", "1.0.0",
                        "无编码器时仅为几何先验，不能视为信号已检测地标")
    return pd.DataFrame(rows, columns=columns)


def _append(
    rows: list[dict[str, Any]], scan_id: str, event_type: str, sample_index: int,
    position_norm: float, x_m: float | None, confidence: float, source: str,
    method: str, version: str, notes: str,
) -> None:
    identity = f"{scan_id}|{event_type}|{sample_index}|{source}|{version}"
    rows.append({
        "event_id": "event_" + sha256_text(identity)[:20],
        "scan_id": scan_id,
        "event_type": event_type,
        "sample_index": sample_index,
        "pipe_position_norm": position_norm,
        "x_from_pipe_center_m": x_m,
        "confidence": confidence,
        "event_source": source,
        "detection_method": method,
        "algorithm_version": version,
        "manually_verified": False,
        "notes": notes,
    })

