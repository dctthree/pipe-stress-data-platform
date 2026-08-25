# 406 管道 MEM—剩磁—ETP 牵拉实验公开数据卡 / Dataset Card

Release: `406-v0.3.0`
Scope: 406 管道四点弯/内检测牵拉研究数据；标定数据与后续三周期盲测数据分区发布。

## 一句话边界 / One-line boundary

本数据可用于复现同一根 406 管道上的**阶段相对排序、空间配准、重复性与质量控制研究**；它不提供盲测阶段的应力真值，也不支持直接宣称绝对应力（MPa）或跨管道泛化能力。

This release supports reproducible research on **relative stage ordering, spatial registration, repeatability and QC on the same 406 pipe**. It does not provide blind-cycle stress ground truth and does not validate absolute-MPa estimation or cross-pipe generalization.

## 数据构成 / Contents

| 分区 | 资产 | 内容 | 阶段 |
|---|---|---|---|
| calibration | `406_calibration_magnetic_v0.3.0.zip` | 7 个加载状态、35 个共享磁 CSV；按物理列奇偶拆分为剩磁与 MEM | S0–S6 |
| calibration | `406_calibration_strain_v0.3.0.zip` | 两个原始应变工作簿，以及派生的阶段表/分析摘要 | S0–S6；原始表还含卸载/残余记录 |
| blind C1 | `406_blind_C1_magnetic_v0.3.0.zip` | 共享磁 CSV | S0–S6，完整 |
| blind C1 | `406_blind_C1_etp_v0.3.0.zip` | ETP 涡流 CSV | S0–S6，完整 |
| blind C2 | `406_blind_C2_magnetic_v0.3.0.zip` | 共享磁 CSV；含原始 `Readme.txt` 质量说明 | S0–S6；S2 为 REJECT |
| blind C2 | `406_blind_C2_etp_v0.3.0.zip` | ETP 涡流 CSV | S0–S6；ETP 自身 QC 可用，配对磁主通道 S2 拒收 |
| blind C3 | `406_blind_C3_magnetic_partial_v0.3.0.zip` | 共享磁 CSV | **仅 S0–S2** |
| blind C3 | `406_blind_C3_etp_partial_v0.3.0.zip` | ETP 涡流 CSV | **仅 S0–S2** |

Archive paths are canonical and relative, for example `raw/blind/C1/magnetic/零压力测试/75000.csv`. No archive contains an absolute local path.

## 阶段映射 / Stage mapping

| ID | 原始文件夹标签 | 含义 |
|---|---|---|
| S0 | 零压力 / 零压力测试 | 零载牵拉 |
| S1 | 第一次加压 | 第 1 个加载阶段 |
| S2 | 第二次加压 | 第 2 个加载阶段 |
| S3 | 第三次加压 | 第 3 个加载阶段 |
| S4 | 第四次加压 | 第 4 个加载阶段 |
| S5 | 第五次加压 | 第 5 个加载阶段 |
| S6 | 第六次加压 | 第 6 个加载阶段 |

The mapping is ordinal. **Do not copy the calibration MPa labels onto C1/C2/C3 merely because the stage IDs match.** Blind folders contain no synchronized strain/load-cell truth in this release.

## 标定应力标签的定义 / Calibration label provenance

`derived/calibration/calibration_stage_labels.csv` contains the seven calibration-stage values used in the earlier 406 analysis:

`nominal surface bending stress = 206 GPa × median bending microstrain`.

这些值由应变片中位弯曲应变派生，不是载荷传感器/压力机的直接真值；它们只属于标定分区。`strain_states.csv` 还保留了卸载/残余状态，不能把该行当成第八个加载阶段。

These values are derived from median bending strain, not from a load cell, and belong only to the calibration partition. The additional unloading/residual row in `strain_states.csv` is not an eighth loading stage.

## 磁 CSV 物理拆分 / Magnetic physical split

每个磁 CSV 有 1307 个命名字段。前 1280 个字段对应 320 个传感位置索引，每个索引依次为 X/Y/Z/T；布局为 32 个物理列 × 10 个周向位置。固化映射为：

- 1-based 奇数物理列（1, 3, …, 31）＝剩磁；
- 1-based 偶数物理列（2, 4, …, 32）＝ MEM；
- X/Y/Z 保留设备字段名，不能在没有独立坐标标定时自动解释为管道轴向/环向/径向；
- `MEMX-*` 等是固件表头前缀，并不表示所有 320 个位置都是 MEM。

The MEM and remanence streams are not independent files: they share one magnetic CSV and are separated by physical-column parity. Treating them as two independent samples would cause leakage.

## ETP CSV / Eddy-current channels

每个 ETP CSV 有 67 个命名字段：20 对 `Amplitude-i, Phase-i`，4 个 Coder 字段，两套 IMU/温度字段和 `Ticker-0`。现有冻结程序用 `Z_i = A_i exp(j·Phase_i)` 构造复信号；继续使用前应核对设备导出的相位单位。ETP 在当前证据中是候选/QC 模态，不是绝对应力量。

## 冻结质量控制 / Frozen QC

- `C2/S2` 磁数据/磁主决策：**REJECT_WELD_NOT_CENTERED**。原始说明为“本次数据有问题，焊缝的数据并不在中间位置”。磁文件为审计可追溯性保留，但必须从磁特征拟合、重复性统计和磁主应力评分中排除。
- `C2/S2` ETP：ETP 自身 QC 为通过，清单标为 `PASS_ETP_PAIRED_MAGNETIC_REJECT`；这表示 ETP 原始阶段仍可做独立研究，但不能据此挽救已拒收的配对磁主决策包。
- `C3`：仅有 S0–S2。S3–S6 是未采集/未提供，不得插值或填补。
- 磁与 ETP 只能按 `cycle + stage` 配对；各自仍需独立检测进管、焊缝、出管地标并完成空间配准。
- 进/出管边缘峰、焊缝强事件、停留段、速度/温度/饱和异常应先用于分段和 QC，不能直接当应力响应。
- 当前程序只实现 fail-closed 的模态资格/QC门控：剩磁主相对量 + MEM 同周期 S0 辅助 + ETP 整轮候选/QC；ETP未过门时保持仅磁相对量。逐阶段跨模态方向冲突评分尚未实现，后续必须显式增加该门后才能用“冲突降级/重测”；当前发布不授权无约束数值融合。

## 明确排除 / Explicit exclusions

本发布没有纳入：

- `blind test/data/未处理数据`（原始/复制树，体积大且与截取数据有重复风险）；
- 所有阶段 PNG 截图；
- 标定阶段的旧连续 ETP 数据；
- P110 数据；
- 盲测阶段 MPa/应变真值（本来就未提供）；
- 对缺失阶段的任何插补。

The two public 406 experiment photographs are documentation assets in the repository case study, not sensor samples and not part of these raw ZIP archives.

## 完整性与追溯 / Integrity and traceability

- `raw_file_manifest.csv`: partition, modality, cycle/stage, canonical path, byte count and SHA-256 for every included raw/derived file;
- `channel_schema.csv`: grouped field contract for magnetic and ETP CSVs;
- `release_index.json`: archive-level coverage, QC boundaries, size and SHA-256;
- `SHA256SUMS.txt`: checksums for every downloadable archive and core metadata file; download the Release attachments into one flat directory before running a standard checksum check.

Verify downloads before analysis. Keep `cycle`, `stage_id`, raw file SHA-256, preprocessing version and QC decision in every derived record.

## 合理用途 / Intended use

适合：读取器验证、分段/地标算法、同管相对阶段排序、特征鲁棒性、负对照、缺失/拒绝数据处理、模态资格门控与显式冲突门设计研究。

不适合：直接现场报绝对 MPa、把 S1–S6 当作盲测真值、随机拆分同一次牵拉片段造成数据泄漏、将 C3 缺失阶段补齐后宣称三次完整重复、未经新管标定即外推。

Suitable for parser validation, segmentation/landmark research, same-pipe relative ordering, robustness/QC and gated multimodal studies. Not suitable for absolute field stress reporting, fragment-level random train/test splits, fabricated completion of C3, or uncalibrated transfer to a new pipe.
