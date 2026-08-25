from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

FEATURES = ["q60_delta", "q70_delta", "q75_delta", "q80_delta"]


def main() -> None:
    parser = argparse.ArgumentParser(description="Plot reviewed real P110 multi-sensor MEM evidence.")
    parser.add_argument("--table", type=Path, default=Path("docs/data/p110_multisensor_mem_real.csv"))
    parser.add_argument("--output", type=Path, default=Path("docs/results/real_p110_magnetic_case.png"))
    args = parser.parse_args()
    data = pd.read_csv(args.table)
    if set(data["run_id"]) != {"mem_r1", "mem_r2"} or data["sensor_n"].min() != 5:
        raise RuntimeError("Expected two reviewed complete-MEM runs with five preselected sensors.")

    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)
    colors = {"mem_r1": "#1764ab", "mem_r2": "#d95f02"}
    labels = {"mem_r1": "complete MEM run 1", "mem_r2": "complete MEM run 2"}
    for run_id, group in data.groupby("run_id"):
        group = group.sort_values("stress_mpa")
        axes[0, 0].plot(group["stress_mpa"], group["q70_delta"], "o-", linewidth=2.2,
                        color=colors[run_id], label=labels[run_id])
        x = group["stress_mpa"] / group["stress_mpa"].max()
        y = group["q70_delta"] / group["q70_delta"].max()
        axes[0, 1].plot(x, y, "o-", linewidth=2.2, color=colors[run_id], label=labels[run_id])

    axes[0, 0].set_title("Real scale: X-axis Q70 shift from same-run zero load")
    axes[0, 0].set_xlabel("Strain-gauge-derived bending stress [MPa]")
    axes[0, 0].set_ylabel("Five-sensor median ΔQ70 [count]")
    axes[0, 1].plot([0, 1], [0, 1], "k--", linewidth=1, label="identity")
    axes[0, 1].set_title("Within-run normalized response")
    axes[0, 1].set_xlabel("Normalized strain-gauge stress")
    axes[0, 1].set_ylabel("Normalized magnetic ΔQ70")

    rho_by_feature, slope_ratio_by_feature = [], []
    for feature in FEATURES:
        rhos, slopes = [], []
        for _, group in data.groupby("run_id"):
            stress_rank = group["stress_mpa"].rank().to_numpy(dtype=float)
            feature_rank = group[feature].rank().to_numpy(dtype=float)
            rhos.append(float(np.corrcoef(stress_rank, feature_rank)[0, 1]))
            slopes.append(np.polyfit(group["stress_mpa"], group[feature], 1)[0])
        rho_by_feature.append(min(rhos))
        slope_ratio_by_feature.append(max(slopes) / min(slopes))

    names = ["Q60", "Q70", "Q75", "Q80"]
    axes[1, 0].bar(names, rho_by_feature, color="#2a9d8f")
    axes[1, 0].axhline(0.9, color="black", linestyle="--", linewidth=1)
    axes[1, 0].set_ylim(0, 1.05)
    axes[1, 0].set_title("Worst-run Spearman ordering reproducibility")
    axes[1, 0].set_ylabel("min Spearman ρ across two complete runs")
    axes[1, 1].bar(names, slope_ratio_by_feature, color="#e9c46a")
    axes[1, 1].axhline(1.0, color="black", linestyle="--", linewidth=1)
    axes[1, 1].set_title("Cross-run scale instability (must not be hidden)")
    axes[1, 1].set_ylabel("larger/smaller calibration slope")
    for ax in axes.flat:
        ax.grid(alpha=0.25, axis="y")
    axes[0, 0].legend()
    axes[0, 1].legend()
    fig.suptitle(
        "REAL P110 EXP2 — reviewed 6 o'clock complete-bilateral-MEM subset\n"
        "ordering repeats; absolute scale does not transfer",
        fontsize=14,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=180)
    plt.close(fig)
    print(args.output)


if __name__ == "__main__":
    main()
