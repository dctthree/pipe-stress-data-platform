# Pipe Stress Data Platform

[中文说明](README_CN.md) · [Demo](demo/README.md) · [AI data contract](docs/AI_DATA_CONTRACT.md) · [Acquisition SOP](docs/工业采集元数据SOP.md)

A traceable data pipeline for magnetic, remanence, eddy-current and strain-gauge pull-test data used in pipeline stress research. It turns scattered CSV/XLSX/native acquisition files into immutable raw assets, typed Parquet signals, quality-control records, versioned features and leakage-safe AI tables.

> Status: research/engineering foundation. Quantitative MPa output remains fail-closed until a model passes independent-pipe blind validation.

## Why this repository exists

Real pull-test campaigns often mix sensor files, strain exports, loading notes, repeated stages and manually named folders. That makes it easy to overwrite raw data, align the wrong load stage, reuse blind labels during feature selection, or compare sample-domain frequencies across different pull speeds.

This project makes those failure modes explicit:

```mermaid
flowchart LR
    A[Incoming experiment] --> B[SHA-256 immutable archive]
    B --> C[Schema and metadata QC]
    C --> D[Standardized magnetic/strain tables]
    D --> E[Pipe events and alignment priors]
    E --> F[Versioned feature store]
    F --> G[Leakage-safe AI matrix]
    G --> H{Engineering gate}
    H -->|pass| I[Relative assessment]
    H -->|fail| J[Reject / review]
```

## Included capabilities

- Content-addressed immutable raw archive with SHA-256 deduplication.
- Config-driven 3-column and 45-column `Z,Y,X` magnetic layouts.
- Streaming XLSX reader that does not trust incorrect worksheet dimension metadata.
- Explicit sentinel, clipping, channel and primary-feature QC.
- Automatic pipe-entry/exit detection plus head/support geometry priors.
- Robust statistics, entropy, spike metrics, zero-load Q60–Q80 deltas and CDF superiority.
- Separate, versioned stress labels and blind-label access policies.
- CSV + Parquet + SQLite catalogs for MATLAB, Python and AI clients.
- Dataset fingerprinting from raw hashes, configuration, labels and pipeline code.
- Frozen releases and grouped AI split keys to prevent run-level leakage.

## Quick demo

The demo creates a deterministic, de-identified P110-like five-stage experiment with the same 45-column `15 sensors × ZYX` layout. It is structural demonstration data, not field-validation evidence.

```powershell
python -m pip install -e ".[demo]"
python demo/run_demo.py --regenerate
```

Expected outputs:

- five standardized pull scans;
- a QC/event catalog;
- channel and AI feature tables;
- a full SHA-256 validation report;
- signal and stress-feature figures.

![Demo signals](demo/results/demo_stage_signals.png)

![Demo stress feature](demo/results/demo_stress_feature.png)

## Real P110 case-study result

The local full-data run used 211 source files:

| Item | Result |
|---|---:|
| Magnetic pulls standardized | 53 |
| Strain files standardized | 18 |
| Strain values standardized | 9,380,688 |
| Channel feature rows | 639 |
| AI sample rows | 53 |
| Integrity/lineage checks | 40/40 passed |
| Unique raw blobs after deduplication | 201 |

The real raw data are deliberately excluded from Git history. For an authorized private deployment, publish the full data lake as a GitHub Release asset or store it in an immutable object store.

## Run on a local experiment

1. Copy [configs/experiment_template.json](configs/experiment_template.json).
2. Register the pipe, probe layout, run/stage mapping and signal schema.
3. Keep verified labels in a separate CSV; leave stress blank for blind data.
4. Run:

```powershell
python run_pipeline.py run --config path/to/experiment.json --output lake --snapshot-mode blob
python run_pipeline.py validate --output lake --full-hash
```

The single machine entry point is `lake/dataset_index.json`. AI code should not scan source folders or infer stages from Chinese filenames.

## AI and MATLAB

Python example:

```python
from examples.ai_loader_example import StressDataset

dataset = StressDataset("lake/dataset_index.json")
samples = dataset.supervised_samples()
```

MATLAB R2024b interface:

```matlab
addpath('matlab');
d = loadStressDataset('lake/dataset_index.json');
```

## Important limitations

- Without encoder/speed calibration, `pipe_position_norm` is not a precise metre coordinate.
- Without sampling rate, sample-domain roughness must not be reported as Hz-domain information.
- A clipped primary axis may still be retained for audit or other-axis research, but it cannot pass the primary stress gate.
- Same-pipe repeated experiments show repeatability, not generalization to a new pipe.
- Direct MPa output remains disabled until calibration and independent blind validation are frozen.

## Repository/data boundary

Tracked in Git: source code, schemas, templates, tests, deterministic demo and documentation.

Not tracked in Git: raw customer/experimental files, local absolute-path configs, verified private labels, generated lakes and large release ZIP files.

No open-source license is granted by default. See [NOTICE.md](NOTICE.md).

