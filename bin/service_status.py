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

from lib.configuration import Configuration


def report_status(service_name: str, exit_code: int) -> None:
    json_env_file = project_root / ".env.json"

    try:
        config = Configuration.from_json(json_env_file)
    except (json.JSONDecodeError, ValueError):
        print(
            f"❌ Error: {json_env_file.name} is not valid JSON configuration.",
            file=sys.stderr,
        )
        return

    try:
        config.validate(["status-dir"])
    except ValueError as e:
        print(f"❌ Configuration error: {e}", file=sys.stderr)
        sys.exit(1)

    user_home = Path.home()
    status_dir = config.get_path("status-dir", user_home)

    # Ensure the status directory exists
    status_dir.mkdir(parents=True, exist_ok=True)

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Report service status to a JSON file."
    )
    parser.add_argument("service_name", help="Name of the service")
    parser.add_argument("exit_code", type=int, help="Exit code of the service")

    args = parser.parse_args()
    report_status(args.service_name, args.exit_code)


if __name__ == "__main__":
    main()
