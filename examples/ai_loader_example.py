from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


class StressDataset:
    """Small read-only interface intended for analysis agents and model code."""

    def __init__(self, index_path: str | Path):
        self.index_path = Path(index_path).resolve()
        self.root = self.index_path.parent
        self.index = json.loads(self.index_path.read_text(encoding="utf-8"))

    def table(self, name: str) -> pd.DataFrame:
        relative = self.index["tables"][name]["parquet"]
        return pd.read_parquet(self.root / Path(relative))

    def signal(self, scan_id: str, valid_only: bool = False) -> pd.DataFrame:
        scans = self.table("scans")
        matched = scans.loc[scans["scan_id"] == scan_id]
        if len(matched) != 1:
            raise KeyError(f"scan_id必须唯一，实际{len(matched)}条: {scan_id}")
        signal = pd.read_parquet(self.root / Path(matched.iloc[0]["silver_signal_path"]))
        if valid_only:
            signal = signal[signal["in_pipe"] & signal["channel_qc_valid"] & ~signal["is_clipped"]]
        return signal

    def supervised_samples(self) -> pd.DataFrame:
        samples = self.table("ml_feature_matrix")
        return samples[
            samples["use_for_supervised"].fillna(False)
            & (samples["scan_qc_status"] != "FAIL")
            & ~samples["blind_flag"].fillna(True)
        ].copy()


if __name__ == "__main__":
    dataset = StressDataset(Path(__file__).parents[1] / "lake" / "dataset_index.json")
    print(dataset.index["dataset_id"], dataset.index["dataset_version"])
    print(dataset.table("scans")[["scan_id", "probe_id", "run_id", "stage_mm", "scan_qc_status"]].head())
    print("可监督样本数:", len(dataset.supervised_samples()))

