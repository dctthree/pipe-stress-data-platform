# v0.3.0 — 406 mm multimodal public case

This release adds the real 406 mm four-point-bending / in-line pull-test campaign while preserving the modality and truth boundaries of the existing P110 EXP2 release.

## Added

- A fully documented `case_studies/406_multimodal` package with MATLAB source, derived CSV/JSON tables, 13 real blind-repeat figures plus one frozen calibration figure, and an independent fail-fast validator.
- The 406 calibration partition: zero load S0 plus six loaded states S1–S6, shared MEM/remanence magnetic CSVs and strain-gauge records.
- The 406 blind-repeat partition: C1 and C2 complete, C3 partial S0–S2, for 17 paired magnetic/ETP packets.
- Public field photographs with provenance, colour normalization, metadata stripping and an explicit background-person privacy note.
- Real calibration and repeatability figures on the repository front page.
- A versioned data Release index, per-file and per-asset SHA-256 manifests, channel contracts and a bilingual dataset card.

## Sensor contracts

- The 406 magnetic CSV contract has 1307 named numeric fields. The first 1280 fields are `320 × (X,Y,Z,T)`.
- There are 32 physical columns with 10 sensing positions each. One-based odd physical columns are remanence and even physical columns are MEM; each group therefore contains 160 sensing channels.
- MEM and remanence share the same magnetic CSV stream. They must not be counted as two raw files.
- ETP is an independent 67-field stream with 20 `(Amplitude, Phase)` channel pairs plus acquisition fields.

## Frozen evidence boundary

- `MAG-F1-DW-Q90-v1`: primary same-pipe relative-order/change evidence. Strict C1↔C2 repeatability after the pre-declared C2/S2 rejection: Spearman ρ 1.000, Lin CCC 0.996, normalized RMSE 3.35%.
- `MEM-F4-ZSD-v1`: unsigned, same-cycle-S0 auxiliary evidence. Strict C1↔C2 CCC 0.980, normalized RMSE 7.51%.
- ETP candidates: research/QC only because target specificity and negative-control gates do not pass.
- Fusion: fail-closed modality/QC eligibility gating only; no numeric fusion value. Explicit stagewise cross-modality conflict scoring is not implemented in v0.3.0.
- Blind absolute MPa: disabled. The blind-repeat partition has no contemporaneous strain/MPa truth.

The calibration MPa column is derived as `206 GPa × median bending strain`; it is not a load-cell measurement and must not be copied into the blind-repeat labels.

## Deliberately excluded

- `blind test/data/未处理数据`, which duplicates or precedes the curated clipped magnetic source tree.
- Acquisition screenshots, old single-cycle conclusions, deprecated reports, large MAT/FIG runtime products and local absolute paths.
- The old continuous ETP recording as a stage-by-stage calibration source; it represents one strain state and cannot be aligned to S0–S6.

## Compatibility

The generic Python data platform remains backward-compatible with the P110 v0.2.0 package. The 406 raw-data reader is supplied as a dedicated MATLAB case because its 1307-field fragmented magnetic contract and independent complex ETP contract differ materially from the P110 three-axis CSV layout.
