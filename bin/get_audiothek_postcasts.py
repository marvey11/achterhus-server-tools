#! /usr/bin/env python3

import json
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import requests
from jsonpath_ng import parse as jp_parse
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Add the project root to sys.path, so that our libraries can be loaded
project_root = Path(__file__).resolve().parent.parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))


from lib.configuration import load_and_validate_config
from lib.download import download_file

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

# Configure the retry strategy
retry_strategy = Retry(
    total=5,  # Total attempts (initial + 4 retries)
    connect=5,  # Specifically retry on connection errors
    backoff_factor=2,  # Wait times: 1s, 2s, 4s, 8s...
    status_forcelist=[
        429,
        500,
        502,
        503,
        504,
    ],  # Also retry on these server errors
)

# -----------------------------------------------------------------------------
# Additional configuration
# -----------------------------------------------------------------------------

SERVICE_NAME = "get-audiothek-podcasts"

PODCAST_TEMPLATE = "https://api.ardaudiothek.de/programsets/{podcast_urn}"
EPISODE_QUERY = jp_parse("$.data.programSet.items.nodes[*]")

# -----------------------------------------------------------------------------
# Type definitions
# -----------------------------------------------------------------------------

type PodcastMetadata = dict[str, dict[str, str]]
type EpisodeManifest = dict[str, dict[str, dict[str, str]]]

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------


def slugify(text: str) -> str:
    """Returns a filesystem-friendly version of a string."""
    return re.sub(r"[^\w\s-]", "", text).strip().replace(" ", "_")


def get_safe_filename(date_str: str, title: str) -> str:
    """Parses ISO date and creates a YYYY-MM-DD_Title.mp3 filename."""
    dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
    return f"{dt.strftime('%Y-%m-%d')}_{slugify(title)}.mp3"


def atomic_write_json(file_path: Path, data: dict[str, Any]) -> None:
    """Writes JSON to a temp file then renames it to prevent corruption."""
    fd, temp_path = tempfile.mkstemp(dir=file_path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        os.replace(temp_path, file_path)
    except Exception:
        os.remove(temp_path)
        raise


# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------


def process_podcast(
    podcast_urn: str, download_dir: Path, manifest_path: Path
) -> None:
    download_url = PODCAST_TEMPLATE.format(podcast_urn=podcast_urn)

    download_dir.mkdir(exist_ok=True, parents=True)

    # Load Manifest
    manifest: EpisodeManifest = {}
    if manifest_path.exists():
        print(f"Loading manifest from {manifest_path}...")
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)

    if podcast_urn not in manifest:
        manifest[podcast_urn] = {}

    with requests.Session() as shared_session:
        # Mount the strategy to a session
        adapter = HTTPAdapter(max_retries=retry_strategy)

        shared_session.headers.update(
            {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    + "PodcastDownloader/1.0"
                )
            }
        )

        shared_session.mount("https://", adapter)
        shared_session.mount("http://", adapter)

        # Fetch Feed
        print(f"Fetching feed from {download_url}...")
        response = shared_session.get(download_url)
        response.raise_for_status()

        if response.encoding is None or response.encoding == "ISO-8859-1":
            response.encoding = "utf-8"

        raw_data = response.json()

        # Process Episodes
        matches = EPISODE_QUERY.find(raw_data)
        for match in matches:
            ep = match.value

            episode_urn: str = ep.get("publicationId", "")
            title: str = ep.get("title", "Unknown Title")
            date_str: str = ep.get("publicationStartDateAndTime", "")
            synopsis: str = ep.get("synopsis", "")

            if not episode_urn or episode_urn in manifest[podcast_urn]:
                continue

            # Extract URL with fallback logic
            audios: list[dict[str, str | None]] = ep.get("audios", [])
            if not audios:
                continue

            audio_url = audios[0].get("downloadUrl") or audios[0].get("url")
            if not audio_url:
                continue

            # Execute Download
            filename = get_safe_filename(date_str, title)
            dest_path = download_dir / filename

            print(f"Downloading: {filename}...")
            try:
                download_file(audio_url, dest_path, session=shared_session)

                # Update and Save Manifest
                manifest[podcast_urn][episode_urn] = {
                    "file_path": str(dest_path),
                    "title": title,
                    "synopsis": synopsis,
                    "downloaded_at": datetime.now().isoformat(),
                }
                atomic_write_json(manifest_path, manifest)
            except Exception as e:
                print(f"Failed to download {episode_urn}: {e}")


def get_configuration_paths() -> tuple[Path, Path]:
    json_env_file = project_root / ".env.json"

    config = load_and_validate_config(
        json_env_file, ["podcast-storage", "service-shared-dir"]
    )

    if config is None:
        raise ValueError("Failed to load configuration")

    service_shared_dir = config.get_path("service-shared-dir")
    storage_base = config.get("podcast-storage")

    return service_shared_dir, storage_base


def get_service_file_paths(service_shared_dir: Path) -> tuple[Path, Path]:
    shared_path = (service_shared_dir / SERVICE_NAME).resolve()
    shared_path.mkdir(exist_ok=True, parents=True)

    metadata_path = (shared_path / "metadata.json").resolve()
    manifest_path = (shared_path / "manifest.json").resolve()

    return metadata_path, manifest_path


def main() -> int:
    try:
        service_shared_dir, storage_base = get_configuration_paths()
    except ValueError as e:
        print(f"Failed to retrieve configuration paths: {e}")
        return 1

    metadata_path, manifest_path = get_service_file_paths(service_shared_dir)

    if not metadata_path.exists():
        print("No metadata file found. Exiting...")
        return 1

    podcast_metadata: PodcastMetadata = {}

    print(f"Loading metadata from {metadata_path}")
    with open(metadata_path, encoding="utf-8") as f:
        podcast_metadata = json.load(f)

    for urn, metadata in podcast_metadata.items():
        download_dir = (storage_base / metadata["target_dir"]).resolve()

        process_podcast(urn, download_dir, manifest_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
