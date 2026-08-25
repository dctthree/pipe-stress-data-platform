from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


STAGES = [(0, 0.0), (20, 42.0), (40, 86.0), (60, 130.0), (80, 174.0)]
ACTIVE_SENSORS = [1, 3, 4, 5, 6]


def gaussian(x: np.ndarray, centre: float, width: float) -> np.ndarray:
    return np.exp(-0.5 * ((x - centre) / width) ** 2)


def generate(output_root: Path) -> list[Path]:
    run_dir = output_root / "MEM_FULL" / "run_01"
    run_dir.mkdir(parents=True, exist_ok=True)
    n = 1200
    sample = np.arange(n)
    pipe_start, pipe_end = 150, 1050
    x_norm = (sample - pipe_start) / (pipe_end - pipe_start)
    x_m = (x_norm - 0.5) * 10.54
    inside = (sample >= pipe_start) & (sample <= pipe_end)
    entry = gaussian(sample, pipe_start, 8)
    exit_ = gaussian(sample, pipe_end, 8)
    head = gaussian(x_m, -1.95, 0.13) + gaussian(x_m, 1.95, 0.13)
    support = gaussian(x_m, -4.11, 0.14) + gaussian(x_m, 4.11, 0.14)
    weld = gaussian(x_m, 0.0, 0.11)
    central = gaussian(x_m, 0.0, 1.30)
    paths: list[Path] = []

    for stage_mm, stress_mpa in STAGES:
        rng = np.random.default_rng(20260825 + stage_mm)
        matrix = np.full((n, 45), -1.0, dtype=float)
        matrix[:, 3:6] = 0.0  # sensor slot 2 is a registered zero channel
        for sensor_id in ACTIVE_SENSORS:
            phase = sensor_id * 0.37
            noise = rng.normal(0.0, 3.0, size=(n, 3))
            z = 1700 + 35 * np.sin(2 * np.pi * x_norm + phase)
            y = -420 + 22 * np.cos(2.4 * np.pi * x_norm + phase)
            x = -7200 + 28 * np.sin(1.5 * np.pi * x_norm + phase)
            z += 650 * entry - 720 * exit_ + 55 * head + 38 * support
            y += -240 * entry + 280 * exit_ + 30 * weld
            x += 820 * entry - 900 * exit_ + 95 * head + 48 * support + 125 * weld
            stress_gain = stress_mpa * (0.72 + 0.025 * sensor_id)
            x += stress_gain * central * inside + 0.28 * stress_mpa * inside
            z += 0.09 * stress_mpa * head * inside
            triplet = np.column_stack([z, y, x]) + noise
            matrix[:, 3 * (sensor_id - 1):3 * sensor_id] = triplet

        # Diagnostic sensor 7 is intentionally noisy but not used for the primary aggregate.
        matrix[:, 18:21] = rng.normal(0, 150, size=(n, 3))
        path = run_dir / f"{stage_mm}-6.csv"
        pd.DataFrame(matrix, columns=[f"I{i}" for i in range(45)]).to_csv(path, index=False, float_format="%.6f")
        paths.append(path)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "input")
    args = parser.parse_args()
    paths = generate(args.output.resolve())
    print(f"Generated {len(paths)} demo scans in {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

