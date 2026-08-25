from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the reviewed real-P110 case-study figure.")
    parser.add_argument("--lake", type=Path, default=Path("lake"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("docs/results/real_p110_magnetic_case.png"),
    )
    args = parser.parse_args()

    scans = pd.read_parquet(args.lake / "catalog/scans.parquet")
    features = pd.read_parquet(args.lake / "gold/channel_features.parquet")
    selected = scans[
        scans["probe_id"].eq("MEM_SINGLE_SLOT")
        & scans["run_id"].eq("slotted_mem_r1")
        & scans["label_status"].eq("verified")
        & scans["primary_stress_feature_qc_status"].eq("PASS")
    ].copy()
    if selected.empty:
        raise RuntimeError("Reviewed real P110 subset was not found or did not pass QC.")

    colors = plt.cm.viridis(np.linspace(0.05, 0.95, selected["stage_mm"].nunique()))
    color_by_stage = dict(zip(sorted(selected["stage_mm"].unique()), colors))
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)

    for ax, clock in zip(axes[0], (6, 12)):
        subset = selected[selected["clock_position"].eq(clock)].sort_values("stage_mm")
        for row in subset.itertuples(index=False):
            signal = pd.read_parquet(args.lake / row.silver_signal_path)
            x = signal[
                signal["axis"].eq("X") & signal["in_pipe"] & signal["channel_qc_valid"]
            ].sort_values("pipe_position_norm")
            x = x[x["pipe_position_norm"].between(0.01, 0.99)]
            if x.empty:
                continue
            values = x["value_raw"].to_numpy(dtype=float)
            values = values - np.nanmedian(values)
            ax.plot(
                x["pipe_position_norm"],
                values,
                color=color_by_stage[row.stage_mm],
                linewidth=1.1,
                label=f"{row.stage_mm:g} mm / {row.stress_mpa_magnitude:.1f} MPa",
            )
        stress_type = "tension" if clock == 6 else "compression"
        ax.set_title(f"{clock} o'clock ({stress_type}) — real magnetic X signal")
        ax.set_xlabel("Normalized in-pipe position (not metres)")
        ax.set_ylabel("X response − in-pipe median [count]")
        ax.grid(alpha=0.25)
        ax.legend(fontsize=8, ncol=2)

    fx = features[
        features["scan_id"].isin(selected["scan_id"])
        & features["axis"].eq("X")
        & features["channel_qc_valid"]
    ].copy()
    for clock, marker, label in ((6, "o", "6 o'clock tension"), (12, "s", "12 o'clock compression")):
        q = fx[fx["clock_position"].eq(clock)].sort_values("stress_mpa_magnitude")
        axes[1, 0].plot(
            q["stress_mpa_magnitude"], q["q_family_delta"], marker=marker, label=label
        )
        axes[1, 1].plot(
            q["stress_mpa_magnitude"], q["histogram_entropy"], marker=marker, label=label
        )

    axes[1, 0].axhline(0, color="black", linewidth=0.8)
    axes[1, 0].set_title("Robust quantile shift relative to same-clock zero load")
    axes[1, 0].set_xlabel("Strain-gauge-derived axial stress magnitude [MPa]")
    axes[1, 0].set_ylabel("Median Q60/Q70/Q75/Q80 shift [count]")
    axes[1, 1].set_title("Magnetic distribution entropy")
    axes[1, 1].set_xlabel("Strain-gauge-derived axial stress magnitude [MPa]")
    axes[1, 1].set_ylabel("Histogram entropy [dimensionless]")
    for ax in axes[1]:
        ax.grid(alpha=0.25)
        ax.legend(fontsize=9)

    fig.suptitle(
        "REAL P110 EXP2: three-axis magnetic probe + strain gauge\n"
        "Single-side slotted MEM, run 1; 1% pipe-edge trim for display; strict monotonicity is not claimed",
        fontsize=14,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=180)
    plt.close(fig)
    print(args.output)


if __name__ == "__main__":
    main()
