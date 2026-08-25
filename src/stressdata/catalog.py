from __future__ import annotations

import sqlite3
from pathlib import Path

import pandas as pd


def write_sqlite_catalog(path: str | Path, tables: dict[str, pd.DataFrame], metadata: dict[str, str]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    if temporary.exists():
        temporary.unlink()
    connection = sqlite3.connect(temporary)
    try:
        for name, table in tables.items():
            safe = table.copy()
            for column in safe.columns:
                if safe[column].dtype == "object":
                    safe[column] = safe[column].map(_sqlite_value)
            safe.to_sql(name, connection, if_exists="replace", index=False)
        pd.DataFrame([{"key": key, "value": value} for key, value in metadata.items()]).to_sql(
            "dataset_metadata", connection, if_exists="replace", index=False
        )
        _create_indexes(connection, tables)
        connection.commit()
    finally:
        connection.close()
    temporary.replace(target)


def _sqlite_value(value):
    if isinstance(value, (list, tuple, dict, set)):
        return str(value)
    return value


def _create_indexes(connection: sqlite3.Connection, tables: dict[str, pd.DataFrame]) -> None:
    candidates = {
        "raw_files": ["file_id", "sha256", "role"],
        "assets": ["pipe_id"],
        "experiments": ["experiment_id", "pipe_id"],
        "probes": ["probe_id"],
        "channels": ["layout_id", "channel_id", "sensor_id"],
        "strain_files": ["strain_file_id", "source_file_id", "strain_qc_status"],
        "scans": ["scan_id", "run_id", "probe_id", "split_group"],
        "events": ["event_id", "scan_id", "event_type"],
        "qc_checks": ["scan_id", "outcome", "check_name"],
        "channel_features": ["scan_id", "feature_set_id", "axis"],
        "ml_feature_matrix": ["scan_id", "split_group", "label_status"],
    }
    for table_name, columns in candidates.items():
        if table_name not in tables:
            continue
        available = set(tables[table_name].columns)
        for column in columns:
            if column in available:
                connection.execute(
                    f'CREATE INDEX IF NOT EXISTS "idx_{table_name}_{column}" ON "{table_name}" ("{column}")'
                )
