# AI data contract

AI programs start from `lake/dataset_index.json`; they do not scan Chinese source folders.

Required rules:

1. Resolve every table path relative to the index file.
2. Filter `scan_qc_status != 'FAIL'` before feature use.
3. Use labels only when `use_for_supervised == true` and `blind_flag == false`.
4. Group model splits by `split_group`; never split signal windows independently.
5. Treat `pipe_position_norm` as a normalized coordinate, not metres.
6. Do not emit MPa while `direct_mpa_output_allowed == false`.
7. Preserve `dataset_version`, `feature_set_id`, `baseline_scan_id` and input `source_sha256` with every model artifact or prediction.
8. A new config, label version, raw file or pipeline version produces a new dataset fingerprint.

Recommended model input is `gold/ml_feature_matrix.parquet`. Raw signal models may read `silver/signals/{scan_id}.parquet`, but their training manifest must still list scan IDs and split groups explicitly.

## 406 release contract

The 406 raw-data Release uses `release_index.json` and `raw_file_manifest.csv` because its fragmented 1307-field magnetic stream and independent 67-field complex ETP stream require a dedicated reader.

AI and analysis clients must additionally enforce:

1. Treat MEM and remanence as two parity-defined sensor groups in one magnetic CSV; do not count the same file twice.
2. Pair modalities only by the published `cycle_id + stage_id` manifest after each modality has passed its own entry/weld/exit registration.
3. Preserve the actual design: C1=7 states, C2=7 states and C3=3 states. Never impute C3/S3–S6.
4. Exclude C2/S2 from strict magnetic repeatability because its source operator note says the weld was not centred.
5. Do not copy calibration MPa values into the blind partition. Blind `stage_ordinal` is an order label, not contemporaneous stress truth.
6. Keep `fusion_value` non-finite and `direct_mpa_output_allowed=false` unless a future independently validated release explicitly changes both fields.
7. Use ETP target features together with their weld/outside/temperature negative controls; a failed specificity gate cannot be hidden by model weighting.
8. Treat v0.3.0 as modality/QC eligibility gating only. No stagewise MEM–remanence–ETP direction/conflict score is implemented, so clients must not infer a concordance decision from an ETP eligibility pass.

The tracked [406 case validator](../case_studies/406_multimodal/validate_case.py) checks the frozen derived evidence independently of MATLAB.
