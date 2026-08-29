# Project share kit / 项目推广素材

This page provides approved, evidence-bounded copy and real visual assets for sharing the repository. It deliberately separates measured evidence from the synthetic structural demo.

本页提供可直接转发、且不超出当前证据边界的中英文文案与真实图片入口。真实实验结果和合成结构 Demo 必须分开说明。

## Canonical link / 统一链接

https://github.com/dctthree/pipe-stress-data-platform

## One-line description / 一句话介绍

**English**

Real P110 and 406-mm pipe pull-test datasets with traceable Python/MATLAB workflows for magnetic pipeline-stress sensing, repeatability analysis and leakage-safe AI research.

**中文**

公开真实 P110 与 406 mm 管道四点弯牵拉数据，以及面向磁应力感知、重复性评估和防数据泄漏 AI 研究的可追溯 Python/MATLAB 处理流程。

## Short technical post / 技术群短文案

我们公开了一套真实管道应力磁感知实验仓库。406 mm 管道案例包含 MEM、剩磁、ETP 涡流与标定轮应变片数据，并公开两个完整盲测重复周期和一个部分周期；P110 套管案例只包含三轴磁传感与应变片，不把探头硬件名称误写成独立剩磁或涡流模态。仓库同时提供原始数据索引、SHA-256 校验、质量控制、特征版本、MATLAB/Python 程序和真实现场照片。当前结论限定为受控实验下的相对变化与重复性，不宣称已经实现新管道现场绝对应力 MPa 盲测。

项目地址：https://github.com/dctthree/pipe-stress-data-platform

## English post for LinkedIn or ResearchGate

We have released a public research repository for traceable pipeline-stress sensing experiments. It contains two distinct real-data case studies: (1) a 406-mm pipe campaign with MEM, remanence, eddy-current and strain-gauge measurements, including repeated blind pull cycles; and (2) a P110 casing campaign with three-axis magnetic measurements and strain-gauge references only. The repository publishes immutable data indexes, checksums, QC records, versioned features, MATLAB/Python workflows, real test photographs and explicit claim limits. The current evidence supports controlled same-pipe relative assessment and repeatability research—not transferable absolute-MPa field certification.

Repository: https://github.com/dctthree/pipe-stress-data-platform

## Compact post for X / short-form channels

Real pipe pull-test data, not synthetic evidence: P110 magnetic+strain and 406-mm MEM/remanence/ETP case studies, with reproducible Python/MATLAB workflows, QC failures retained, and explicit limits on stress claims. https://github.com/dctthree/pipe-stress-data-platform

## Outreach message for independent reproduction / 同行复现邀请

**English**

We are looking for independent users in pipeline in-line inspection, electromagnetic NDT and structural-health monitoring to reproduce one frozen case study. A useful contribution is not a positive result by default: confirmation, failure, sensitivity to preprocessing and cross-platform issues are all welcome. Please start from the release index rather than inferring stages from filenames, then submit a Reproduction Report issue with the release tag, checksum, environment and observed result.

**中文**

我们希望邀请管道内检测、电磁无损检测和结构健康监测方向的同行，独立复现一个冻结案例。复现不要求得到“正结果”；确认、失败、预处理敏感性和跨平台问题同样有价值。请从 Release 数据索引开始，不要根据文件名自行推断阶段，并通过“复现报告”Issue 提交版本、校验值、运行环境和结果。

## Real assets that may be reused as project links / 可用于项目转发的真实素材

| Asset | What it shows | Boundary |
|---|---|---|
| [P110 field-test overview](results/field_photos/p110_field_test_overview.jpg) | Real P110 four-point-bending setup | Context photograph; not a numerical input |
| [P110 sensor pull setup](results/field_photos/p110_sensor_pull_setup.jpg) | Real sensor, loading head and strain wiring | Context photograph; not a numerical input |
| [P110 reviewed result](../case_studies/p110_magnetic_strain/results/reviewed/real_p110_magnetic_case.png) | Real reviewed magnetic/strain subset | Relative-ordering evidence; not transferable MPa calibration |
| [406 in-line inspection tool](results/field_photos/406/406_inline_inspection_tool_setup.jpg) | Real 406-mm in-line inspection tool | Context photograph; privacy note applies |
| [406 bending setup](results/field_photos/406/406_four_point_bending_strain_setup.jpg) | Real four-point-bending and strain arrangement | Context photograph; not a numerical input |
| [406 calibration relationships](../case_studies/406_multimodal/results/calibration/07_physical_contrast_trends.png) | Real calibration-run feature relationships | Development/calibration evidence, not independent validation |
| [406 repeated blind pulls](results/real_406_repeatability.png) | Real repeated blind packets with QC exclusions retained | No contemporaneous blind MPa truth |

Do not use images under `demo/results/` as experimental evidence. They are deterministic synthetic data for software-path testing.

不要把 `demo/results/` 中的图片作为实验结果，它们是用于验证软件流程的确定性合成数据。

## Search terms / 检索关键词

`pipeline stress assessment`, `pipeline inspection`, `in-line inspection`, `magnetic stress sensing`, `remanence`, `eddy current testing`, `strain gauge`, `four-point bending`, `pull-through test`, `multimodal NDT`, `P110 casing`, `real experimental dataset`, `reproducible research`

管道应力检测、管道内检测、磁感知、剩磁、涡流检测、应变片、四点弯曲、牵拉测试、多传感融合、P110 套管、真实实验数据、可复现研究。

## Claims that must not be made / 禁止超范围宣传

- Do not claim that P110 contains an independent remanence or ETP modality.
- Do not describe the synthetic demo as a real experiment.
- Do not claim independent-pipe absolute-MPa validation.
- Do not hide declared QC failures or the partial third 406 cycle.
- Do not describe public visibility as an open-source licence until explicit code and data licences are added.

- 不得声称 P110 含有独立剩磁或 ETP 模态。
- 不得把合成 Demo 描述为真实实验。
- 不得声称已经完成独立新管道绝对 MPa 验证。
- 不得隐去已声明的 QC 失败和 406 第三个不完整周期。
- 在明确加入代码及数据许可证前，不得把“公开可见”等同于“已授予开源权利”。
