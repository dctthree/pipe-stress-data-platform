from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from generate_demo_data import generate  # noqa: E402
from stressdata.pipeline import run_pipeline  # noqa: E402
from stressdata.validate import validate_dataset  # noqa: E402


def run(regenerate: bool, ci: bool) -> dict:
    demo_root = Path(__file__).resolve().parent
    input_root = demo_root / "input"
    output_root = demo_root / "output"
    results_root = demo_root / "results"
    if regenerate:
        if input_root.exists():
            shutil.rmtree(input_root)
        if output_root.exists():
            shutil.rmtree(output_root)
    if not list(input_root.glob("MEM_FULL/run_01/*.csv")):
        generate(input_root)
    index = run_pipeline(demo_root / "config" / "demo_experiment.json", output_root, "blob")
    validation = validate_dataset(output_root, full_hash=True)
    if validation["overall_status"] != "PASS":
        raise RuntimeError(f"Demo validation failed: {validation}")
    results_root.mkdir(parents=True, exist_ok=True)
    plot_stage_signals(output_root, results_root)
    plot_stress_feature(output_root, results_root)
    summary = {
        "dataset_id": index["dataset_id"],
        "dataset_version": index["dataset_version"],
        "counts": index["counts"],
        "validation": validation,
        "direct_mpa_output_enabled": index["label_policy"]["direct_mpa_prediction_enabled"],
        "demo_data_notice": "Deterministic de-identified structural demo; not experimental evidence.",
    }
    (results_root / "demo_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not ci:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def plot_stage_signals(output_root: Path, results_root: Path) -> None:
    scans = pd.read_parquet(output_root / "catalog" / "scans.parquet").sort_values("stage_mm")
    fig, ax = plt.subplots(figsize=(10.5, 5.6), constrained_layout=True)
    for _, scan in scans.iterrows():
        signal = pd.read_parquet(output_root / Path(scan["silver_signal_path"]))
        x = signal[(signal["axis"] == "X") & signal["in_pipe"] & signal["channel_qc_valid"]]
        profile = x.pivot_table(index="pipe_position_norm", columns="sensor_id", values="value_raw", aggfunc="mean").median(axis=1)
        profile = profile - profile.median()
        ax.plot(profile.index, profile.values, lw=1.35, label=f"{scan['stage_mm']:.0f} mm / {scan['stress_mpa_magnitude']:.0f} MPa")
    ax.set(title="Demo: standardized in-pipe X response", xlabel="Normalized pipe position", ylabel="Median sensor response - median [count]")
    ax.grid(alpha=0.25)
    ax.legend(ncol=2, fontsize=8)
    fig.savefig(results_root / "demo_stage_signals.png", dpi=180)
    plt.close(fig)


def plot_stress_feature(output_root: Path, results_root: Path) -> None:
    matrix = pd.read_parquet(output_root / "gold" / "ml_feature_matrix.parquet").sort_values("stress_mpa_magnitude")
    feature = "X_q_family_delta_sensor_median"
    fig, ax = plt.subplots(figsize=(7.2, 5.2), constrained_layout=True)
    ax.plot(matrix["stress_mpa_magnitude"], matrix[feature], "o-", lw=1.8, ms=6)
    for _, row in matrix.iterrows():
        ax.annotate(f"{row['stage_mm']:.0f} mm", (row["stress_mpa_magnitude"], row[feature]), xytext=(4, 5), textcoords="offset points", fontsize=8)
    ax.set(title="Demo: zero-load Q60-Q80 family vs label", xlabel="Demo stress label [MPa]", ylabel="Median sensor Q-family delta [count]")
    ax.grid(alpha=0.25)
    ax.text(0.01, 0.01, "Structural demo only — direct MPa inference remains disabled", transform=ax.transAxes, fontsize=8, color="firebrick")
    fig.savefig(results_root / "demo_stress_feature.png", dpi=180)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the deterministic reader demo")
    parser.add_argument("--regenerate", action="store_true")
    parser.add_argument("--ci", action="store_true")
    args = parser.parse_args()
    run(args.regenerate, args.ci)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

