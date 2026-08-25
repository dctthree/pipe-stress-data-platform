from __future__ import annotations

import argparse
import json
from pathlib import Path

from .pipeline import run_pipeline
from .validate import validate_dataset


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="管道应力多传感数据平台")
    subparsers = parser.add_subparsers(dest="command", required=True)
    run = subparsers.add_parser("run", help="扫描、归档、校验、标准化并生成特征库")
    run.add_argument("--config", required=True, help="实验JSON配置")
    run.add_argument("--output", default="lake", help="数据湖输出目录")
    run.add_argument("--snapshot-mode", choices=["blob", "reference"], default="blob",
                     help="blob=保存不可变副本；reference=只登记源路径")
    status = subparsers.add_parser("status", help="显示最近一次数据集索引")
    status.add_argument("--output", default="lake", help="数据湖输出目录")
    validate = subparsers.add_parser("validate", help="独立复核表、外键、分区、标签隔离和原始哈希")
    validate.add_argument("--output", default="lake", help="数据湖输出目录")
    validate.add_argument("--full-hash", action="store_true", help="重新计算所有不可变副本SHA-256")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "run":
        result = run_pipeline(args.config, args.output, args.snapshot_mode)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    if args.command == "validate":
        result = validate_dataset(args.output, args.full_hash)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result["overall_status"] != "FAIL" else 2
    index_path = Path(args.output).resolve() / "dataset_index.json"
    if not index_path.exists():
        raise SystemExit(f"尚无数据集索引: {index_path}")
    print(index_path.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
