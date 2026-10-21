#!/usr/bin/env bash
set -euo pipefail

NAME="confkit"   # смените, если имя занято на PyPI
mkdir "$NAME" && cd "$NAME"
mkdir -p src/confkit tests .github/workflows

cat > src/confkit/__init__.py <<'EOF'
from .core import ConfigError, Secret, load

__all__ = ["ConfigError", "Secret", "load"]
__version__ = "0.1.0"
EOF

cat > src/confkit/core.py <<'EOF'
from __future__ import annotations

import os
from dataclasses import MISSING, fields
from typing import Any, Mapping, TypeVar, get_type_hints

T = TypeVar("T")


class ConfigError(Exception):
    """Ошибка конфигурации: перечисляет все проблемы сразу."""


class Secret:
    """Обёртка, которая не раскрывает значение в логах и repr."""

    __slots__ = ("_value",)

    def __init__(self, value: str) -> None:
        self._value = value

    def reveal(self) -> str:
        return self._value

    def __repr__(self) -> str:
        return "Secret('***')"

    __str__ = __repr__


_TRUE = {"1", "true", "yes", "on"}
_FALSE = {"0", "false", "no", "off"}


def _cast(raw: str, tp: Any) -> Any:
    if tp is Secret:
        return Secret(raw)
    if tp is bool:
        v = raw.strip().lower()
        if v in _TRUE:
            return True
        if v in _FALSE:
            return False
        raise ValueError(f"invalid bool {raw!r}")
    return tp(raw)


def load(cls: type[T], env: Mapping[str, str] | None = None, prefix: str = "") -> T:
    """Загрузить dataclass `cls` из переменных окружения с валидацией типов."""
    env = os.environ if env is None else env
    hints = get_type_hints(cls)
    values: dict[str, Any] = {}
    errors: list[str] = []

    for f in fields(cls):  # type: ignore[arg-type]
        key = (prefix + f.name).upper()
        if key in env:
            try:
                values[f.name] = _cast(env[key], hints[f.name])
            except (ValueError, TypeError) as exc:
                errors.append(f"{key}: {exc}")
        elif f.default is MISSING and f.default_factory is MISSING:
            errors.append(f"{key}: required variable is missing")

    if errors:
        raise ConfigError("; ".join(errors))
    return cls(**values)
EOF

cat > tests/test_core.py <<'EOF'
from dataclasses import dataclass

import pytest

from confkit import ConfigError, Secret, load


@dataclass
class Settings:
    port: int
    debug: bool = False
    api_key: Secret = Secret("")


def test_loads_and_casts():
    s = load(Settings, env={"PORT": "8080", "DEBUG": "yes", "API_KEY": "abc"})
    assert s.port == 8080 and s.debug is True
    assert s.api_key.reveal() == "abc"


def test_secret_is_masked():
    s = load(Settings, env={"PORT": "1", "API_KEY": "topsecret"})
    assert "topsecret" not in repr(s)


def test_reports_all_errors():
    with pytest.raises(ConfigError) as e:
        load(Settings, env={"DEBUG": "maybe"})
    assert "PORT" in str(e.value) and "DEBUG" in str(e.value)
EOF

cat > pyproject.toml <<'EOF'
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "confkit"
version = "0.1.0"
description = "Type-safe configuration loader with secret masking"
readme = "README.md"
requires-python = ">=3.9"
license = { text = "MIT" }
classifiers = ["Programming Language :: Python :: 3", "Typing :: Typed"]

[project.optional-dependencies]
dev = ["pytest", "pytest-cov", "ruff", "mypy"]

[tool.hatch.build.targets.wheel]
packages = ["src/confkit"]
EOF

cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python: ["3.9", "3.10", "3.11", "3.12", "3.13"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "${{ matrix.python }}" }
      - run: pip install -e ".[dev]"
      - run: ruff check .
      - run: pytest --cov=confkit
EOF

cat > README.md <<'EOF'
# confkit

Type-safe configuration loading for Python services: validates env at startup
and keeps secrets out of your logs.

```python
from dataclasses import dataclass
from confkit import load, Secret

@dataclass
class Settings:
    port: int
    debug: bool = False
    api_key: Secret = Secret("")

settings = load(Settings)   # reads PORT, DEBUG, API_KEY
print(settings)             # api_key=Secret('***')
