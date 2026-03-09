#! /usr/bin/env python3

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal

# Add the project root to sys.path
project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from lib.configuration import load_and_validate_config


@dataclass
class MetadataEntry:
    label: str
    value: str | int
    unit: str | None = None
    trend: Literal["up", "down", "neutral"] | None = None

    def to_dict(self) -> dict[str, str | int]:
        return {k: v for k, v in asdict(self).items() if v is not None}


type ServiceMetadata = dict[str, MetadataEntry]


def get_status_dir() -> Path:
    json_env_file = project_root / ".env.json"

    config = load_and_validate_config(json_env_file, ["status-dir"])
    if config is None:
        sys.exit(1)

    status_dir = config.get_path("status-dir")

    # Ensure the status directory exists
    status_dir.mkdir(parents=True, exist_ok=True)

    return status_dir


def report_status(
    status_dir: Path,
    service_name: str,
    exit_code: int,
    metadata: ServiceMetadata | None = None,
) -> None:
    utc_now = (
        datetime.now(UTC)
        .replace(tzinfo=None)
        .isoformat(timespec="milliseconds")
        + "Z"
    )

    data: dict[str, Any] = {
        "service": service_name,
        "timestamp": utc_now,
        "status": "success" if exit_code == 0 else "error",
        "exit_code": exit_code,
    }

    if metadata:
        data["metadata"] = {
            key: value.to_dict() for key, value in metadata.items()
        }

    status_file = status_dir / f"{service_name}.json"
    try:
        with open(status_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4)
            # Ensure file ends with a newline for better readability
            f.write("\n")

    except OSError as e:
        print(f"❌ Error writing status file: {e}", file=sys.stderr)


def update_manifest(status_dir: Path, service_name: str) -> None:
    manifest_file = status_dir / "services.json"

    services: set[str] = set()

    if manifest_file.exists():
        try:
            with open(manifest_file, encoding="utf-8") as f:
                services = set(json.load(f))
        except json.JSONDecodeError:
            pass

    if service_name not in services:
        services.add(service_name)
        temp_file = manifest_file.with_suffix(".tmp")
        with open(temp_file, "w", encoding="utf-8") as f:
            json.dump(sorted(list(services)), f, indent=2)

        temp_file.replace(manifest_file)
        manifest_file.chmod(0o644)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Report service status to a JSON file."
    )
    parser.add_argument("service_name", help="Name of the service")
    parser.add_argument("exit_code", type=int, help="Exit code of the service")
    parser.add_argument("--metadata", type=str, help="JSON string of metadata")

    args = parser.parse_args()
    status_dir = get_status_dir()

    # Convert the JSON string into MetadataEntry objects
    try:
        raw_metadata = json.loads(args.metadata)
        metadata_dict = {k: MetadataEntry(**v) for k, v in raw_metadata.items()}
    except (json.JSONDecodeError, TypeError) as e:
        print(f"⚠️ Metadata ignored due to parse error: {e}")
        metadata_dict = None

    report_status(
        status_dir, args.service_name, args.exit_code, metadata=metadata_dict
    )
    update_manifest(status_dir, args.service_name)


if __name__ == "__main__":
    main()
