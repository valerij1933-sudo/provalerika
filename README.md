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
```

## Install
`pip install confkit`

## Contributing
See CONTRIBUTING.md. Security issues: SECURITY.md.
