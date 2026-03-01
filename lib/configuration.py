import json
from collections.abc import ItemsView, KeysView
from pathlib import Path
from typing import Self


class Configuration:
    """Holds configuration values for the application."""

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

            for key, value in data.items():
                # Ensure we are returning strings for the .env format
                config.set(str(key), str(value))

        return config

    def __init__(self) -> None:
        """Initialize an empty configuration."""
        self._config: dict[str, str] = {}

    def set(self, key: str, value: str) -> None:
        """Sets a configuration value."""
        self._config[key] = value

    def get(self, key: str, default: str = "") -> str:
        """Gets a configuration value, returning default if not found."""
        return self._config.get(key, default)

    def keys(self) -> KeysView[str]:
        """Returns the keys in the configuration."""
        return self._config.keys()

    def items(self) -> ItemsView[str, str]:
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
        val = Path(self.get(key))
        if val.is_absolute():
            return val.resolve()

        base = base_path or Path.cwd()
        return (base / val).resolve()
