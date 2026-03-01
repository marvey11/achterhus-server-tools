#! /usr/bin/env python3

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

# Add the project root to sys.path
project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

from lib.configuration import load_and_validate_config


def get_status_dir() -> Path:
    json_env_file = project_root / ".env.json"

    config = load_and_validate_config(json_env_file, ["status-dir"])
    if config is None:
        sys.exit(1)

    user_home = Path.home()
    status_dir = config.get_path("status-dir", user_home)

    # Ensure the status directory exists
    status_dir.mkdir(parents=True, exist_ok=True)

    return status_dir


def report_status(status_dir: Path, service_name: str, exit_code: int) -> None:
    utc_now = (
        datetime.now(UTC)
        .replace(tzinfo=None)
        .isoformat(timespec="milliseconds")
        + "Z"
    )

    data = {
        "service": service_name,
        "timestamp": utc_now,
        "status": "success" if exit_code == 0 else "error",
        "exit_code": exit_code,
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

    status_dir = get_status_dir()

    args = parser.parse_args()
    report_status(status_dir, args.service_name, args.exit_code)
    update_manifest(status_dir, args.service_name)


if __name__ == "__main__":
    main()
