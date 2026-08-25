from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


class ConfigError(ValueError):
    pass


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def load_config(path: str | Path) -> dict[str, Any]:
    config_path = Path(path).resolve()
    with config_path.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    validate_config(config)
    config["_config_path"] = str(config_path)
    config["_config_dir"] = str(config_path.parent)
    config["_config_sha256"] = hashlib.sha256(canonical_json_bytes(config_without_runtime(config))).hexdigest()
    source_root = Path(config["experiment"]["source_root"])
    if not source_root.is_absolute():
        source_root = (config_path.parent / source_root).resolve()
    config["_source_root_path"] = str(source_root)
    labels = config.get("labels_csv")
    if labels:
        labels_path = Path(labels)
        if not labels_path.is_absolute():
            labels_path = (config_path.parent / labels_path).resolve()
        config["_labels_path"] = str(labels_path)
    return config


def config_without_runtime(config: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in config.items() if not key.startswith("_")}


def validate_config(config: dict[str, Any]) -> None:
    required = [
        "schema_version",
        "experiment",
        "discovery",
        "filename_parser",
        "probe_aliases",
        "run_rules",
        "signal_schema",
        "feature_set",
    ]
    missing = [key for key in required if key not in config]
    if missing:
        raise ConfigError(f"配置缺少字段: {', '.join(missing)}")
    experiment = config["experiment"]
    for key in ["experiment_id", "campaign_id", "pipe_id", "source_root"]:
        if not experiment.get(key):
            raise ConfigError(f"experiment.{key} 不能为空")
    schema = config["signal_schema"]
    axes = schema.get("axis_order", [])
    if not axes or len(set(axes)) != len(axes):
        raise ConfigError("signal_schema.axis_order 必须是非空且不重复的轴序")
    if int(schema.get("columns_per_sensor", 0)) != len(axes):
        raise ConfigError("columns_per_sensor 必须等于 axis_order 的长度")
    accepted = schema.get("accepted_column_counts", [])
    if not accepted or any(int(value) % len(axes) for value in accepted):
        raise ConfigError("accepted_column_counts 必须能被轴数整除")


def missing_critical_metadata(config: dict[str, Any]) -> list[str]:
    schema = config["signal_schema"]
    missing: list[str] = []
    for key in ["sample_rate_hz", "pull_speed_mps", "nominal_liftoff_mm"]:
        if schema.get(key) is None:
            missing.append(key)
    return missing
