"""Offline-only diagnostic tooling for AeroSpatial session streams.

Flat import names remain stable while implementation modules are organized
in second-level subsystem directories.
"""

from pathlib import Path as _Path

__version__ = "0.4.0"

_PACKAGE_ROOT = _Path(__file__).resolve().parent
for _directory in sorted(_PACKAGE_ROOT.iterdir()):
    if _directory.is_dir() and (_directory / "__init__.py").is_file():
        __path__.append(str(_directory))

del _Path, _PACKAGE_ROOT, _directory
