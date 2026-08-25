# P110 EXP2 public dataset card / P110 EXP2 公开数据卡

## Identity

| Field | Value |
|---|---|
| Dataset ID | `P110_EXP2_20260819_21` |
| Dataset version | `1.0.0+97b0dca62768` |
| Dataset fingerprint | `97b0dca627686ad7002a6cbb83348017963a6d7dbca24d0030978cc50c2010c5` |
| GitHub Release | [v0.2.0](https://github.com/dctthree/pipe-stress-data-platform/releases/tag/v0.2.0) |
| Full ZIP | `P110_EXP2_full_release_1.0.0+97b0dca62768.zip` |
| ZIP bytes | 169,639,531 |
| ZIP SHA-256 | `38cc098c9a590f05efea429073e7c17c0b2c5f8b0232a7625e50957e05fa6a7c` |

Verify the downloaded ZIP against [SHA256SUMS.txt](SHA256SUMS.txt) before extraction. Then start from the ZIP's `dataset_index.json`; do not rediscover stages from filenames.

## Scientific scope

P110 EXP2 contains three-axis magnetic sensor output and strain-gauge measurements. It contains no ETP data and no independently acquired remanence signal stream. Probe names containing “剩磁” identify magnetization/hardware conditions only.

The full package registers 211 source files, 53 completed magnetic scans, 18 standardized strain files, 9,380,688 standardized strain values and 639 channel-feature rows. Ingestion reported no errors. All 40 frozen integrity/structure checks passed with full blob-hash validation.

That `PASS` is not a model-performance result. Thirty-three primary-feature records fail the conservative frozen stress-feature QC, and `direct_mpa_prediction_enabled` remains false.

## Geometry and coordinates

- P110 casing: 10.54 m length, 139.70 mm outside diameter, 9.17 mm wall thickness.
- Material properties recorded for the experiment: 853 MPa yield and 930 MPa tensile strength.
- Four-point-bend half-spans: 1.95 m between pipe centre and loading-head centre; 4.11 m between pipe centre and inner support.
- Raw magnetic position is sample index. A pipe-entry/exit normalized coordinate may be used for registration, but it is not a metre-scale distance because no physical encoder or verified pull speed is frozen.

## Labels and permitted use

- Strain-derived labels are stored separately from magnetic signals.
- Split unit: `pipe_id + experiment_id + run_id`.
- Same-pipe repeated runs are not independent-pipe validation.
- The reviewed Q60–Q80 evidence supports exploratory relative ordering only.
- Direct MPa prediction, residual-stress inversion and transfer to a new pipe are not validated.

## Compact evidence versus full release

The case directory tracks a 10-row reviewed derived table so readers can inspect exact values and redraw the real figure without downloading 169 MB. This compact table does not yet include row-level scan IDs, source hashes, baseline scan IDs and method versions, so it is not presented as a complete raw-to-feature provenance reconstruction. Use the full Release for source-level research and the compact table only for the frozen exploratory result described in the case README.

## 中文边界说明

P110 数据只有三轴磁传感与应变片，不含 ETP，也没有独立剩磁采集流。Release 中的 40 项通过表示文件完整性和结构一致性，不代表应力模型通过盲测。当前只允许把 Q60–Q80 作为同管、同配置下的相对应力排序候选，禁止直接输出通用 MPa。
