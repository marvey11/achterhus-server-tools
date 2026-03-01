import json
from collections.abc import ItemsView, KeysView
from pathlib import Path
from typing import Self


class Configuration:
    """Holds configuration values for the application."""

    # Increment whenever a breaking change to the JSON keys is introduced
    SCHEMA_VERSION = 1

    @classmethod
    def from_json(cls, json_path: Path) -> Self:
        """Loads configuration from a JSON file."""

        config = cls()

        if not json_path.exists():
            print(f"⚠️  Note: {json_path.name} not found. Using defaults.")
            return config

        with open(json_path, encoding="utf-8") as f:
            data = json.load(f)

            if not isinstance(data, dict):
                raise ValueError("Root must be a dictionary")

            for k, v in data.items():
                key = str(k)
                value = v if isinstance(v, str | int) else str(v)
                config.set(key, value)

        return config

    def __init__(self) -> None:
        """Initialize an empty configuration."""
        self._config: dict[str, str | int] = {}

    def check_version(self) -> None:
        """
        Validates the 'version' key in the JSON.
        Raises ValueError if version is missing or incompatible.
        """
        user_version = self.get("version", 0)
        if user_version != self.SCHEMA_VERSION:
            raise ValueError(
                f"⚠️ Configuration version mismatch! "
                f"Expected {self.SCHEMA_VERSION}, found {user_version}. "
                f"Please update your .env.json."
            )

    def set(self, key: str, value: str | int) -> None:
        """Sets a configuration value."""
        self._config[key] = value

    def get(self, key: str, default: str | int = "") -> str | int:
        """Gets a configuration value, returning default if not found."""
        return self._config.get(key, default)

    def keys(self) -> KeysView[str]:
        """Returns the keys in the configuration."""
        return self._config.keys()

    def items(self) -> ItemsView[str, str | int]:
        """Returns the key-value pairs in the configuration."""
        return self._config.items()

    def validate(self, required_keys: list[str]) -> None:
        """
        Ensures all required keys are present.
        Raises ValueError with a helpful message if any are missing.
        """
        missing = [key for key in required_keys if key not in self._config]
        if missing:
            raise ValueError(
                f"Missing required configuration keys: {', '.join(missing)}"
            )

    def get_path(self, key: str, base_path: Path | None = None) -> Path:
        """
        Returns a resolved Path. If the config value is relative,
        it is joined with base_path (defaults to current dir).
        """
        value = str(self.get(key))
        path = Path(value)
        if path.is_absolute():
            return path.resolve()

        base = base_path or Path.cwd()
        return (base / path).resolve()
