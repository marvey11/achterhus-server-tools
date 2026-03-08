import json
import sys
from collections.abc import ItemsView, KeysView
from pathlib import Path
from typing import Any, Self

# Define a more descriptive type alias
type ConfigurationValue = str | int | dict[str, Any]


class Configuration:
    """
    Holds configuration values for the application with strict dependency
    resolution.
    """

    SCHEMA_VERSION = 2

    @classmethod
    def from_json(cls, json_path: Path) -> Self:
        """Loads configuration from a JSON file."""
        config = cls()

        if not json_path.exists():
            print(
                f"⚠️  Note: {json_path.name} not found. Using defaults.",
                file=sys.stderr,
            )
            return config

        try:
            with open(json_path, encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse configuration JSON: {e}") from e

        if not isinstance(data, dict):
            raise ValueError("Root of configuration JSON must be a dictionary")

        # Load raw data
        for k, v in data.items():
            config.set(str(k), v)

        return config

    def __init__(self) -> None:
        self._config: dict[str, ConfigurationValue] = {}

    def check_version(self) -> None:
        """Validates the 'version' key. Raises ValueError if incompatible."""
        # Note: We use _get_raw to avoid resolution loops during version check
        user_version = self._config.get("version", 0)
        if user_version != self.SCHEMA_VERSION:
            raise ValueError(
                f"⚠️ Configuration version mismatch! "
                f"Expected {self.SCHEMA_VERSION}, found {user_version}."
            )

    def set(self, key: str, value: ConfigurationValue) -> None:
        self._config[key] = value

    def get(self, key: str, default: Any = None) -> Any:
        """
        Gets a configuration value.
        If key is missing and no default is provided, raises KeyError.
        """
        if key not in self._config:
            if default is not None:
                return default
            raise KeyError(f"Configuration key '{key}' not found.")

        return self._resolve(self._config[key])

    def _resolve(self, value: Any) -> Any:
        """
        Recursively resolves configuration values.
        Fails explicitly if referenced keys are missing.
        """
        if not isinstance(value, dict):
            return value

        val_type = value.get("type")
        if not val_type:
            return value

        if val_type == "relative-path":
            base_key_raw = value.get("base-path")
            if not base_key_raw:
                raise KeyError("Type 'relative-path' requires 'base-path'.")

            base_key = base_key_raw.strip("{}")

            # Check for the reserved "HOME" keyword
            if base_key.upper() == "HOME":
                base_path = Path.home()
            else:
                # Fall back to standard config lookup
                try:
                    base_path = Path(self.get(base_key))
                except KeyError:
                    raise KeyError(
                        f"Reference '{base_key}' not found in config."
                    )

            sub_path = value.get("name", "")
            return (base_path / sub_path).resolve()

        return value

    def validate(self, required_keys: list[str]) -> None:
        """Ensures all required keys are present."""
        missing = [key for key in required_keys if key not in self._config]
        if missing:
            raise ValueError(
                f"Missing required configuration keys: {', '.join(missing)}"
            )

    def get_path(self, key: str, base_path: Path | None = None) -> Path:
        """Returns a resolved Path object."""
        value = self.get(key)
        path = Path(str(value))

        if path.is_absolute():
            return path.resolve()

        base = base_path or Path.home()
        return (base / path).resolve()

    def keys(self) -> KeysView[str]:
        return self._config.keys()

    def items(self) -> ItemsView[str, ConfigurationValue]:
        return self._config.items()


def load_and_validate_config(
    json_env_file: Path, expected_keys: list[str]
) -> Configuration | None:
    try:
        config = Configuration.from_json(json_env_file)
    except (json.JSONDecodeError, ValueError):
        print(
            f"❌ Error: {json_env_file.name} is not valid JSON configuration.",
            file=sys.stderr,
        )
        return None

    try:
        config.check_version()
        config.validate(expected_keys)
    except ValueError as e:
        print(f"❌ Configuration error: {e}", file=sys.stderr)
        return None

    return config
