from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from stressdata.features import cdf_superiority  # noqa: E402
from stressdata.metadata import parse_scan_metadata  # noqa: E402
from stressdata.pipeline import run_pipeline  # noqa: E402


class MetadataTests(unittest.TestCase):
    def test_unicode_probe_and_repeat_parser(self):
        config = json.loads((ROOT / "configs" / "p110_exp2.json").read_text(encoding="utf-8"))
        meta = parse_scan_metadata("MEM/第三次/60-6-第二次.csv", "a" * 64, config)
        self.assertIsNotNone(meta)
        self.assertEqual(meta["probe_id"], "MEM_FULL")
        self.assertEqual(meta["run_id"], "mem_r2")
        self.assertEqual(meta["stage_mm"], 60.0)
        self.assertEqual(meta["clock_position"], 6)
        self.assertEqual(meta["technical_repeat"], 2)

    def test_cdf_superiority_direction(self):
        baseline = np.arange(100, dtype=float)
        shifted = baseline + 20
        self.assertGreater(cdf_superiority(shifted, baseline), 0.0)
        self.assertLess(cdf_superiority(baseline - 20, baseline), 0.0)


class PipelineSmokeTests(unittest.TestCase):
    def test_incremental_end_to_end(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            run_dir = source / "Probe" / "Run1"
            run_dir.mkdir(parents=True)
            n = 240
            base = np.zeros((n, 3), dtype=float)
            base[:40] -= 20
            base[200:] += 30
            base[:, 0] += np.sin(np.linspace(0, 10, n))
            loaded = base.copy()
            loaded[45:195, 2] += 5
            pd.DataFrame(base, columns=["I0", "I1", "I2"]).to_csv(run_dir / "0-6.csv", index=False)
            pd.DataFrame(loaded, columns=["I0", "I1", "I2"]).to_csv(run_dir / "20-6.csv", index=False)
            labels = root / "labels.csv"
            pd.DataFrame([
                {"run_id": "probe_r1", "stage_mm": 0, "clock_position": 6, "recovery_min": np.nan,
                 "stress_mpa_magnitude": 0, "local_axial_stress_mpa": 0, "label_status": "verified",
                 "label_source": "synthetic", "label_version": "v1", "use_for_supervised": True, "notes": ""},
                {"run_id": "probe_r1", "stage_mm": 20, "clock_position": 6, "recovery_min": np.nan,
                 "stress_mpa_magnitude": 50, "local_axial_stress_mpa": 50, "label_status": "verified",
                 "label_source": "synthetic", "label_version": "v1", "use_for_supervised": True, "notes": ""},
            ]).to_csv(labels, index=False)
            config = {
                "schema_version": "1.0",
                "experiment": {"experiment_id": "SYN", "campaign_id": "TEST", "pipe_id": "P1", "source_root": str(source)},
                "discovery": {"exclude_directory_names": ["lake"], "strain_directory_markers": ["strain"],
                              "sensor_extensions": [".csv"], "strain_extensions": [".xlsx", ".txt"],
                              "protocol_extensions": [".docx"]},
                "filename_parser": {"pattern": r"^(?P<stage_mm>\d+(?:\.\d+)?)-(?P<clock_position>6|12)(?P<suffix>.*)$",
                                    "technical_repeat_markers": {"第二次": 2}, "recovery_pattern": r"(?P<recovery_min>\d+)min"},
                "probe_aliases": {"Probe": {"probe_id": "P", "probe_family": "MEM", "magnetization_mode": "active", "pole_geometry": "intact"}},
                "run_rules": [{"probe_id": "P", "folder_contains": "Run1", "run_id": "probe_r1", "run_order": 1, "recommended": True}],
                "signal_schema": {"axis_order": ["Z", "Y", "X"], "columns_per_sensor": 3,
                                  "accepted_column_counts": [3], "preferred_sensor_ids_for_45_columns": [],
                                  "known_excluded_sensor_ids": [], "clip_absolute_value": None,
                                  "sentinel_values": [-1], "minimum_rows": 100, "maximum_clip_fraction": 0.05,
                                  "minimum_effective_sensors_multi": 1, "sample_rate_hz": None,
                                  "pull_speed_mps": None, "nominal_liftoff_mm": None},
                "labels_csv": str(labels),
                "feature_set": {"feature_set_id": "synthetic_v1", "histogram_bins": 16,
                                "quantiles": [0.05, 0.25, 0.60, 0.70, 0.75, 0.80, 0.95], "store_full_signal": True},
            }
            config_path = root / "config.json"
            config_path.write_text(json.dumps(config, ensure_ascii=False), encoding="utf-8")
            output = root / "lake"
            first = run_pipeline(config_path, output, "reference")
            second = run_pipeline(config_path, output, "reference")
            self.assertEqual(first["dataset_fingerprint_sha256"], second["dataset_fingerprint_sha256"])
            self.assertEqual(first["counts"]["sensor_scans_discovered"], 2)
            matrix = pd.read_parquet(output / first["tables"]["ml_feature_matrix"]["parquet"])
            self.assertEqual(len(matrix), 2)
            self.assertFalse(matrix["direct_mpa_output_allowed"].any())
            loaded_row = matrix.loc[matrix["stage_mm"] == 20].iloc[0]
            self.assertGreater(loaded_row["X_q_family_delta_sensor_median"], 0)


if __name__ == "__main__":
    unittest.main()

