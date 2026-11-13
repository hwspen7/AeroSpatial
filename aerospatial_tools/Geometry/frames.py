"""Independent WGS84 reference implementation for numerical parity tests."""

from __future__ import annotations

import math

A = 6378137.0
E2 = 6.6943799901413165e-3


def ecef(latitude: float, longitude: float, height: float) -> tuple[float, float, float]:
    if not all(map(math.isfinite, (latitude, longitude, height))) or \
            abs(latitude) > 90 or abs(longitude) > 180 or abs(height) > 1e7:
        raise ValueError("invalid geodetic position")
    phi = math.radians(latitude)
    lam = math.radians(longitude)
    n = A / math.sqrt(1 - E2 * math.sin(phi) ** 2)
    return ((n + height) * math.cos(phi) * math.cos(lam),
            (n + height) * math.cos(phi) * math.sin(lam),
            (n * (1 - E2) + height) * math.sin(phi))


def enu(origin: tuple[float, float, float],
        target: tuple[float, float, float]) -> tuple[float, float, float]:
    x0, y0, z0 = ecef(*origin)
    x1, y1, z1 = ecef(*target)
    dx, dy, dz = x1-x0, y1-y0, z1-z0
    phi = math.radians(origin[0])
    lam = math.radians(origin[1])
    return (-math.sin(lam) * dx + math.cos(lam) * dy,
            -math.sin(phi) * math.cos(lam) * dx - math.sin(phi) * math.sin(lam) * dy + math.cos(phi) * dz,
            math.cos(phi) * math.cos(lam) * dx + math.cos(phi) * math.sin(lam) * dy + math.sin(phi) * dz)
