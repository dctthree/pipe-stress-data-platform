# 管道应力多传感工业数据平台

本工程把 406/P110 四点弯牵拉实验整理成可追溯、可增量、可供 MATLAB、Python 和 AI 共用的数据链。它不会修改源目录中的任何文件。

## 私有全量数据版本

获得仓库权限的协作者可从私有 [v0.2.0 Release](https://github.com/dctthree/pipe-stress-data-platform/releases/tag/v0.2.0) 下载冻结的 P110 EXP2 数据包：

| 附件 | 大小 | SHA-256 |
|---|---:|---|
| `P110_EXP2_full_release_1.0.0+97b0dca62768.zip` | 169,639,531 字节 | `38cc098c9a590f05efea429073e7c17c0b2c5f8b0232a7625e50957e05fa6a7c` |

解压后以 `dataset_index.json` 为唯一程序入口，不要重新依靠文件名猜测实验阶段。Release 是冻结研究制品；新增实验应创建新配置、独立标签和新数据集版本，禁止覆盖已发布文件。

## 数据分层

| 层级 | 内容 | 约束 |
|---|---|---|
| L0 原始档案 | 原文件字节、SHA-256、原相对路径和采集时间 | 只增不改；同一哈希只保存一次 |
| L1 标准信号 | 统一的 `scan_id / sample_index / sensor_id / axis / value_raw` | 保留原始量纲；不把滤波结果覆盖原始值 |
| L2 质量与特征 | 文件、扫描、通道三级 QC；基础统计和相对零载特征 | 每个特征记录算法版本、参数和基线扫描 |
| L3 AI 样本 | 一次牵拉一行的特征矩阵、标签状态、分组键 | 盲测标签与训练标签隔离；按管道/实验轮次分组 |

默认输出位于 `lake/`：

```text
lake/
  raw/blobs/sha256/       # 内容寻址的不可变原始文件
  catalog/                # CSV/Parquet 清单、SQLite 目录库
  silver/signals/         # 按标准化算法ID分区，每次牵拉一个 Parquet
  gold/                   # 通道特征和 AI 特征矩阵
  runs/                   # 每次处理的审计记录
  dataset_index.json      # AI/程序的唯一入口
```

## 首次运行

当前机器可直接使用已有 Python 环境：

```powershell
cd pipe-stress-data-platform
python run_pipeline.py run `
  --config configs\p110_exp2.json `
  --output lake `
  --snapshot-mode blob
```

日后加入新文件后执行同一命令即可。哈希未变化的原始文件会复用；新文件会增量登记并生成新的数据集版本指纹。

独立复核所有目录外键、分区、盲态隔离以及不可变原始副本哈希：

```powershell
python run_pipeline.py validate `
  --output lake --full-hash
```

仅检查而不保存原始副本：

```powershell
python run_pipeline.py run `
  --config configs\p110_exp2.json --output lake --snapshot-mode reference
```

## 关键输出

- `catalog/raw_files.csv`：所有源文件及哈希、角色和不可变副本位置。
- `catalog/scans.csv`：一次牵拉一行的工况、传感方案、加载位移、钟点、重复编号和标签。
- `catalog/events.csv`：自动管端与压头/支墩几何先验；自动检测和几何推算来源严格区分。
- `catalog/assets/probes/channels`：管道、探头与原始列—传感器—轴映射注册表。
- `catalog/qc_checks.csv`：可机器判定的质量门禁。
- `silver/signals/<标准化算法ID>/<scan_id>.parquet`：统一长表信号。
- `gold/channel_features.parquet`：逐传感器、逐轴特征。
- `gold/ml_feature_matrix.parquet`：一次牵拉一行，可直接供模型训练或盲评。
- `catalog/catalog.sqlite`：AI、Python 或业务系统可直接查询的目录数据库。
- `dataset_index.json`：数据集版本、文件计数、QC 汇总和各表地址。

CSV 用 UTF-8 with BOM，便于中文 Windows/Excel 打开；Parquet 用于保持类型和高效 AI 读取。

## 新实验接入规则

1. 原始文件放到独立实验目录，禁止在原始目录中保存分析图片和结果表。
2. 复制 `configs/experiment_template.json`，填写管道、探头、磁化方式、轴序和路径映射。
3. 新建独立标签 CSV。未知应力保留空值，`label_status=blind`，不得用位移冒充应力标签。
4. 必须记录采样率、编码器/牵拉速度、提离、磁化电流、探头序列号、操作者和时间；缺失字段会进入 QC。
5. 同一根管道的重复牵拉必须共享 `pipe_id`，不同轮次使用不同 `run_id`，模型划分使用 `split_group`，防止同轮数据同时落入训练集和测试集。

## 不允许的做法

- 不允许手工改写原 CSV 后仍沿用原文件名。
- 不允许把应变真值硬编码在分析程序里；标签必须单独版本化。
- 不允许在不知道采样率/速度时解释 Hz 频谱或把采样点直接当物理距离。
- 不允许 QC 失败后仍输出 MPa；可输出原始特征和“拒判”状态。
- 不允许随机按单条扫描拆分训练/测试；至少按 `pipe_id + run_id` 分组。

## MATLAB 与 AI

MATLAB R2024b 可使用 `matlab/loadStressDataset.m` 读取索引、扫描表、特征矩阵及指定牵拉信号。Python/AI 可使用 `examples/ai_loader_example.py`。接口只依赖 `dataset_index.json`，因此后续数据目录可迁移而无需修改模型代码。
