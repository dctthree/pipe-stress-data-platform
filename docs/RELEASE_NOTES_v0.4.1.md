# v0.4.1 — Zenodo archival release

Release date: 2026-08-29

## Purpose

This maintenance release triggers the repository's newly enabled Zenodo
integration and makes the archive metadata explicit. It does not change the
experimental data, processing algorithms, frozen features or scientific
conclusions.

## Metadata changes

- set the software version to `0.4.1` in the Python package, citation metadata
  and Zenodo metadata;
- identify the Zenodo upload as open-access software in English;
- retain Bin Gao, University of Electronic Science and Technology of China
  (UESTC), as the creator;
- retain Apache-2.0 for software and the separate CC BY 4.0 data terms described
  in `DATA_LICENSE.md`.

## Frozen data boundary

- P110 magnetic-and-strain data remain frozen in release `v0.2.0`;
- 406-mm MEM, remanence and ETP data remain frozen in release `v0.3.0`;
- no raw measurement, strain reference, feature value or validation result is
  rewritten by this release.

The evidence boundary is unchanged: the repository supports traceable
same-pipe relative stress studies and quality control; it does not claim a
field-universal absolute-stress model in MPa.
