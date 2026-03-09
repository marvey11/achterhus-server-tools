import sys
from pathlib import Path
from typing import Any

import requests


def download_file(
    url: str,
    local_path: Path,
    session: requests.Session | None = None,
    **kwargs: Any,
) -> Path:
    """
    Downloads a file. If no session is provided, one is created temporarily.
    Uses a temporary file to ensure atomic completion.
    """

    # Create the directory if it doesn't exist
    local_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = local_path.with_suffix(".tmp")

    # Use the provided session or a temporary one
    # Note: 'with' ensures a temporary session is closed,
    # but a passed-in session remains open for the caller.
    s = session or requests.Session()

    try:
        # Pass kwargs through to allow custom headers/auth per call
        kwargs.setdefault("stream", True)
        kwargs.setdefault("timeout", (10, 30))  # (connect, read)

        with s.get(url, **kwargs) as res:
            res.raise_for_status()

            with open(temp_path, "wb") as f:
                for chunk in res.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)

            # Move temp file to final destination only after full success
            temp_path.replace(local_path)
            return local_path

    except Exception as e:
        if temp_path.exists():
            temp_path.unlink()  # Clean up failed download
        print(f"Error downloading {url}: {e}", file=sys.stderr)
        raise
    finally:
        # Close the session if we actually created it
        if session is None:
            s.close()
