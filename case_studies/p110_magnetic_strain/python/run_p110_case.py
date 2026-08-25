#!/usr/bin/env python3
"""Validate, summarize and redraw the frozen reviewed P110 evidence.

This program starts from the tracked 10-row derived table. It does not claim
to reconstruct those rows independently from the full raw-data Release.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


CASE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TABLE = CASE_ROOT / "results" / "reviewed" / "p110_multisensor_mem_real.csv"
DEFAULT_OUTPUT = CASE_ROOT / "runtime"
FEATURES = ["q60_delta", "q70_delta", "q75_delta", "q80_delta"]
EXPECTED_STAGES = [0, 20, 40, 50, 60]


def validate_table(data: pd.DataFrame) -> None:
    expected_columns = [
        "run_id", "stage_mm", "stress_mpa", *FEATURES, "sensor_n"
    ]
    if list(data.columns) != expected_columns:
        raise RuntimeError(f"Unexpected columns: {list(data.columns)!r}")
    if len(data) != 10 or set(data["run_id"]) != {"mem_r1", "mem_r2"}:
        raise RuntimeError("Expected exactly two reviewed runs and ten rows.")
    if data.duplicated(["run_id", "stage_mm"]).any():
        raise RuntimeError("Duplicate run/stage row detected.")
    if set(data["sensor_n"]) != {5}:
        raise RuntimeError("Expected five preselected sensors in every row.")
    numeric = data[["stage_mm", "stress_mpa", *FEATURES, "sensor_n"]].to_numpy(float)
    if not np.isfinite(numeric).all():
        raise RuntimeError("Non-finite reviewed value detected.")
    for run_id, group in data.groupby("run_id", sort=True):
        group = group.sort_values("stage_mm")
        if group["stage_mm"].tolist() != EXPECTED_STAGES:
            raise RuntimeError(f"{run_id}: expected stages {EXPECTED_STAGES}.")
        baseline = group.iloc[0]
        if baseline["stress_mpa"] != 0 or any(baseline[f] != 0 for f in FEATURES):
            raise RuntimeError(f"{run_id}: same-run zero-load baseline changed.")
        for column in ["stress_mpa", *FEATURES]:
            if not np.all(np.diff(group[column].to_numpy(float)) > 0):
                raise RuntimeError(f"{run_id}: {column} is not strictly increasing.")


def compute_metrics(data: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, float | str]] = []
    for feature in FEATURES:
        run_stats: dict[str, dict[str, float]] = {}
        for run_id, group in data.groupby("run_id", sort=True):
            group = group.sort_values("stage_mm")
            x = group["stress_mpa"].to_numpy(float)
            y = group[feature].to_numpy(float)
            slope, intercept = np.polyfit(x, y, 1)
            predicted = slope * x + intercept
            r_squared = 1.0 - np.sum((y - predicted) ** 2) / np.sum((y - y.mean()) ** 2)
            spearman = float(np.corrcoef(pd.Series(x).rank(), pd.Series(y).rank())[0, 1])
            run_stats[run_id] = {
                "slope": float(slope),
                "r_squared": float(r_squared),
                "spearman": spearman,
            }
        slopes = [run_stats[r]["slope"] for r in ("mem_r1", "mem_r2")]
        rows.append({
            "feature_id": feature,
            "min_within_run_spearman": min(
                run_stats["mem_r1"]["spearman"], run_stats["mem_r2"]["spearman"]
            ),
            "mem_r1_slope_count_per_mpa": run_stats["mem_r1"]["slope"],
            "mem_r2_slope_count_per_mpa": run_stats["mem_r2"]["slope"],
            "slope_ratio": max(slopes) / min(slopes),
            "mem_r1_r_squared": run_stats["mem_r1"]["r_squared"],
            "mem_r2_r_squared": run_stats["mem_r2"]["r_squared"],
            "allowed_use": "relative_order_candidate_only",
        })
    return pd.DataFrame(rows)


def plot_case(data: pd.DataFrame, metrics: pd.DataFrame, output: Path) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)
    colors = {"mem_r1": "#1764ab", "mem_r2": "#d95f02"}
    labels = {"mem_r1": "complete MEM run 1", "mem_r2": "complete MEM run 2"}
    for run_id, group in data.groupby("run_id", sort=True):
        group = group.sort_values("stress_mpa")
        axes[0, 0].plot(
            group["stress_mpa"], group["q70_delta"], "o-", linewidth=2.2,
            color=colors[run_id], label=labels[run_id]
        )
        axes[0, 1].plot(
            group["stress_mpa"] / group["stress_mpa"].max(),
            group["q70_delta"] / group["q70_delta"].max(),
            "o-", linewidth=2.2, color=colors[run_id], label=labels[run_id]
        )
    axes[0, 0].set_title("Real scale: X-axis Q70 shift from same-run zero load")
    axes[0, 0].set_xlabel("Strain-gauge-derived bending stress [MPa]")
    axes[0, 0].set_ylabel("Five-sensor median ΔQ70 [count]")
    axes[0, 1].plot([0, 1], [0, 1], "k--", linewidth=1, label="identity")
    axes[0, 1].set_title("Within-run normalized response")
    axes[0, 1].set_xlabel("Normalized strain-gauge stress")
    axes[0, 1].set_ylabel("Normalized magnetic ΔQ70")
    names = ["Q60", "Q70", "Q75", "Q80"]
    axes[1, 0].bar(names, metrics["min_within_run_spearman"], color="#2a9d8f")
    axes[1, 0].axhline(0.9, color="black", linestyle="--", linewidth=1)
    axes[1, 0].set_ylim(0, 1.05)
    axes[1, 0].set_title("Worst-run Spearman ordering reproducibility")
    axes[1, 0].set_ylabel("minimum Spearman ρ across two runs")
    axes[1, 1].bar(names, metrics["slope_ratio"], color="#e9c46a")
    axes[1, 1].axhline(1.0, color="black", linestyle="--", linewidth=1)
    axes[1, 1].set_title("Cross-run scale instability (not hidden)")
    axes[1, 1].set_ylabel("larger/smaller calibration slope")
    for axis in axes.flat:
        axis.grid(alpha=0.25, axis="y")
    axes[0, 0].legend()
    axes[0, 1].legend()
    fig.suptitle(
        "REAL P110 EXP2 — reviewed 6 o'clock complete-bilateral-MEM subset\n"
        "ordering repeats; absolute scale does not transfer",
        fontsize=14,
    )
    fig.savefig(output, dpi=180)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", type=Path, default=DEFAULT_TABLE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    data = pd.read_csv(args.table)
    validate_table(data)
    metrics = compute_metrics(data)
    if not args.check_only:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        metrics.to_csv(args.output_dir / "feature_metrics.csv", index=False, float_format="%.12f")
        plot_case(data, metrics, args.output_dir / "real_p110_magnetic_case.png")
        summary = {
            "source": "reviewed_frozen_derived_real_P110_evidence",
            "rows": len(data),
            "runs": ["mem_r1", "mem_r2"],
            "stage_mm_each_run": EXPECTED_STAGES,
            "direct_mpa_prediction_enabled": False,
            "allowed_use": "same_pipe_same_configuration_relative_order_candidate_only",
            "metrics": metrics.to_dict(orient="records"),
        }
        (args.output_dir / "analysis_summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print(json.dumps({
        "ok": True,
        "table": str(args.table),
        "output_dir": None if args.check_only else str(args.output_dir),
        "direct_mpa_prediction_enabled": False,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
