"""Local distance matching with wrapped longitude; no network geocoding."""

from __future__ import annotations

import math

EARTH_RADIUS_METERS = 6_371_000.0


def great_circle_meters(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    rad = math.pi / 180
    lat1, lat2 = a_lat * rad, b_lat * rad
    delta_lat = (lat2 - lat1) / 2
    delta_lon = math.remainder(b_lon - a_lon, 360) * rad / 2
    h = math.sin(delta_lat) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon) ** 2
    return 2 * EARTH_RADIUS_METERS * math.asin(math.sqrt(max(0, min(1, h))))
