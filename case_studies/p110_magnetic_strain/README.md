# P110 magnetic + strain case study / P110 磁传感与应变案例

[Repository home](../../README.md) · [406 multimodal case](../406_multimodal/README.md) · [P110 v0.2.0 data release](https://github.com/dctthree/pipe-stress-data-platform/releases/tag/v0.2.0) · [Dataset card](release/DATASET_CARD.md)

This is the first-class P110 entry point. It collects the real evidence, corrected public configuration, Python/MATLAB redraw programs, immutable Release identity and fail-closed validation rules that were previously scattered across the repository.

## Field experiment and sensor context / 现场实验与传感器

| P110 four-point-bending loading rig | Central loading head, pipe and strain-gauge wiring |
|---|---|
| ![P110 four-point-bending loading rig](../../docs/results/field_photos/p110_field_test_overview.jpg) | ![P110 central loading head and strain-gauge wiring](../../docs/results/field_photos/p110_sensor_pull_setup.jpg) |

| Item | Description |
|---|---|
| Experiment | Repeated four-point-bending pulls on the same P110 casing; the public index contains 48 six-o'clock scans and five twelve-o'clock scans, with all five twelve-o'clock scans belonging to the single-side-slotted MEM sequence |
| Magnetic acquisition | Three-axis output stored in `Z/Y/X` order; multiple probe hardware configurations were tested |
| Reviewed sensor subset | Complete bilateral MEM probe, 6 o'clock tensile side, preselected sensor IDs 1/3/4/5/6, and same-run zero-load reference |
| Strain reference | Strain gauges provide the matched development labels; the photographs show the loading fixture and strain wiring, not the internal magnetic probe itself |

The photographs provide real physical context only and are not numerical analysis inputs. Published copies and their provenance are documented in the [photo record](../../docs/results/field_photos/README.md).

## Measurement boundary

| Item | Frozen description |
|---|---|
| Test piece | P110 casing, 10.54 m long, 139.70 mm OD, 9.17 mm wall; yield strength 853 MPa, tensile strength 930 MPa |
| Four-point bend geometry | Loading-head centre half-span 1.95 m; inner support-to-centre distance 4.11 m |
| Actual measured modalities | Three-axis magnetic sensor output and strain gauges |
| Not present | No ETP data and no independently acquired remanence measurement |
| Name warning | Folder/probe names containing `剩磁` describe a magnetization/hardware condition; their CSV files are still magnetic-sensor output |
| Public full package | 211 source files, 53/53 magnetic scans completed, 18 strain files, 639 channel-feature rows, 0 ingest errors |

The full package's 40-check `PASS` proves frozen-file integrity and structural consistency. It does **not** mean that an absolute-stress model passed blind validation.

## Reviewed real evidence

![Real P110 reviewed magnetic evidence](results/reviewed/real_p110_magnetic_case.png)

The compact table is a reviewed, frozen derived subset from the same P110 pipe:

- 6 o'clock tensile-side pulls;
- the complete bilateral-pole MEM probe configuration;
- the second and third experimental runs, mapped as `mem_r1` and `mem_r2`;
- stages 0, 20, 40, 50 and 60 mm in each run;
- X-axis quantiles from the five preselected sensors 1, 3, 4, 5 and 6;
- each loaded state referenced to the zero-load pull from the same run.

For run (r), stage (s), selected sensor (k), X-axis signal (X), and quantile (p\in\{0.60,0.70,0.75,0.80\}):

\[
d_{r,s,k,p}=Q_p(X_{r,s,k})-Q_p(X_{r,0,k}),\qquad
F_{r,s,p}=\operatorname{median}_{k\in\{1,3,4,5,6\}}d_{r,s,k,p}.
\]

The tracked columns `q60_delta` through `q80_delta` are the aggregated features shown above. `stress_mpa` is strain-gauge-derived from the matched record; it is not load-cell truth.

| Feature | Minimum within-run Spearman ρ | Linear slope run 1 | Linear slope run 2 | Larger/smaller slope |
|---|---:|---:|---:|---:|
| ΔQ60 | 1.000 | 3.599 | 1.643 | 2.190 |
| ΔQ70 | 1.000 | 3.556 | 1.894 | 1.877 |
| ΔQ75 | 1.000 | 3.468 | 1.919 | 1.807 |
| ΔQ80 | 1.000 | 3.982 | 1.964 | 2.027 |

Stress ordering repeats in these two reviewed subsets, but the response scale differs by 1.81–2.19×. The allowed claim is therefore a same-pipe, same-configuration **relative-order candidate**. Universal direct MPa prediction remains disabled.

There is also a method-dependent QC difference that must remain visible: the conservative whole-trace Python gate flags clipping in these MEM scans, while the later X-axis-specific reviewed workflow preserves the monotonic candidate. The five sensors are therefore described as *preselected for this exploratory subset*, not certified as universally valid channels.

## Reproduce the tracked result

The programs below validate and redraw the 10-row reviewed table. They do not claim to reconstruct that table independently from all 211 raw files, because the current compact table lacks row-level `scan_id`, source SHA-256, baseline scan ID and method-version fields.

From the repository root:

```powershell
python case_studies/p110_magnetic_strain/validate_case.py
python case_studies/p110_magnetic_strain/python/run_p110_case.py
```

MATLAB R2024b or a compatible release:

```matlab
run('case_studies/p110_magnetic_strain/matlab/run_p110_case.m')
```

Generated files go to the ignored `runtime/` directory. The tracked real evidence remains immutable.

For a full local rebuild after downloading and extracting the Release asset, copy [the corrected complete configuration](config/p110_exp2_release.example.json), replace only local paths/identifiers, and use the shared root pipeline:

```powershell
python run_pipeline.py run --config path/to/p110_exp2.json --output lake --snapshot-mode blob
python run_pipeline.py validate --output lake --full-hash
```

## Data and visual context

| Resource | Purpose |
|---|---|
| [Reviewed 10-row evidence](results/reviewed/p110_multisensor_mem_real.csv) | Transparent values used by the case figure |
| [Frozen feature metrics](results/reviewed/feature_metrics.csv) | Ordering and cross-run scale checks |
| [Sanitized release summary](results/reviewed/release_summary.json) | Full-package counts and scientific boundaries without workstation paths |
| [Release index](release/release_index.json) | Public ZIP name, size, SHA-256 and dataset fingerprint |
| [Field-test photographs](../../docs/results/field_photos/README.md) | Real rig and sensor-pull visual context; not analysis inputs |

## 中文说明

本目录是 P110 项目的独立一级入口。P110 EXP2 的真实测量只有三轴磁传感数据和应变片数据，不含 ETP，也没有一套独立采集的“剩磁数据”。文件夹名中的“剩磁/磁化节”表示探头硬件或磁化工况，不能当作新增模态。

当前冻结的 10 行真实证据来自 6 点钟拉应力侧、完整双磁极 MEM 探头、第二次与第三次实验、每轮 0/20/40/50/60 mm 五个阶段，并使用同轮 0 mm 牵拉作为基线。Q60–Q80 在两轮内部都保持应变片推导应力的排序，但跨轮斜率相差 1.81–2.19 倍。因此它只能支持“同管、同配置、同会话相对排序候选”，不能直接输出通用 MPa。

全量 Release 的 40 项 `PASS` 是数据文件完整性与结构校验，不是应力模型性能验收。当前紧凑表也尚未包含逐行扫描 ID、源文件哈希和方法版本，因此这里提供的是可复核的“派生表→统计→图”流程，而不是夸大为“全量原始数据→10 行表”的完全独立重建。
