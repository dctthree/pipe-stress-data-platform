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

