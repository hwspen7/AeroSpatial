"""Bounded fixed-lag, out-of-sequence position fusion with deterministic replay.

Unlike the native raw-IMU error-state filter, this reference filter accepts
WORLD-FRAME, gravity-compensated acceleration samples in ENU. It MUST NOT ingest
unrotated aircraft accelerometer readings as ENU acceleration.
"""
from __future__ import annotations
from dataclasses import dataclass
import math
import numpy as np


@dataclass(frozen=True)
class FusionSnapshot:
    timestamp_s: float
    position_m: tuple[float, float, float]
    velocity_mps: tuple[float, float, float]
    covariance: object
    accepted_positions: int
    gated_positions: int


class DelayedPositionFusion:
    def __init__(self, *, initial_timestamp_s=0.0, initial_position_m=(0., 0., 0.),
                 initial_position_std_m=10.0, initial_velocity_std_mps=2.0,
                 acceleration_noise_std_mps2=0.15, maximum_lag_s=2.0,
                 maximum_events=1024, maximum_nis=11.3449):
        if not (0 < maximum_lag_s <= 60 and 8 <= maximum_events <= 4096 and
                0 < acceleration_noise_std_mps2 < 100 and 0 < maximum_nis < 1000 and
                0 < initial_position_std_m < 1e5 and 0 < initial_velocity_std_mps < 1e5 and
                math.isfinite(initial_timestamp_s) and initial_timestamp_s >= 0):
            raise ValueError('invalid fusion policy')
        self.origin_time = float(initial_timestamp_s)
        p = np.asarray(initial_position_m, dtype=float)
        if p.shape != (3,) or not np.isfinite(p).all(): raise ValueError('invalid initial ENU position')
        self.origin = np.r_[p, np.zeros(3)]
        self.origin_covariance = np.diag([initial_position_std_m**2]*3 + [initial_velocity_std_mps**2]*3)
        self._anchor_time = self.origin_time
        self._anchor_state = self.origin.copy()
        self._anchor_covariance = self.origin_covariance.copy()
        self._anchor_acceleration = np.zeros(3)
        self._anchor_accepted = 0
        self._anchor_gated = 0
        self.accel_std = acceleration_noise_std_mps2
        self.maximum_lag_s = maximum_lag_s
        self.maximum_events = maximum_events
        self.maximum_nis = maximum_nis
        self.events = []
        self._last_imu = self.origin_time
        self._latest_time = self.origin_time
        self._sequence = 0
        self.snapshot = FusionSnapshot(self.origin_time, tuple(p), (0., 0., 0.),
                                       self.origin_covariance.copy(), 0, 0)

    def _valid_vector(self, values):
        v = np.asarray(values, dtype=float)
        if v.shape != (3,) or not np.isfinite(v).all() or np.max(np.abs(v)) > 1e6:
            raise ValueError('invalid measured vector')
        return v

    def append_acceleration(self, time_s: float, acceleration_enu_mps2) -> bool:
        if not math.isfinite(time_s) or time_s < self._last_imu or time_s < self.origin_time:
            return False
        vec = self._valid_vector(acceleration_enu_mps2)
        if len(self.events) >= self.maximum_events: return False
        self._sequence += 1
        self.events.append((time_s, 0, self._sequence, vec, 0.))
        self._last_imu = self._latest_time = time_s
        self._replay()
        return True

    def observe_position(self, time_s: float, position_enu_m, standard_deviation_m: float) -> bool:
        if (not math.isfinite(time_s) or not self.origin_time <= time_s <= self._latest_time or
            time_s < self._anchor_time or self._latest_time - time_s > self.maximum_lag_s or
            not math.isfinite(standard_deviation_m) or not 0 < standard_deviation_m <= 1e4):
            return False
        vec = self._valid_vector(position_enu_m)
        if len(self.events) >= self.maximum_events: return False
        self._sequence += 1
        marker = self._sequence
        self.events.append((time_s, 1, marker, vec, standard_deviation_m))
        decisions = self._replay()
        return decisions.get(marker, False)

    def _replay(self):
        state = self._anchor_state.copy()
        covariance = self._anchor_covariance.copy()
        now = self._anchor_time
        acceleration = self._anchor_acceleration.copy()
        accepted = self._anchor_accepted
        gated = self._anchor_gated
        cutoff = self._latest_time - self.maximum_lag_s
        to_prune = []
        checkpoint = None
        decisions = {}
        for timestamp, kind, identifier, value, sigma in sorted(self.events, key=lambda row: (row[0],row[1],row[2])):
            dt = timestamp - now
            f = np.eye(6);f[:3, 3:] = np.eye(3)*dt
            b = np.vstack([np.eye(3)*.5*dt*dt, np.eye(3)*dt])
            state = f @ state + b @ acceleration
            covariance = f @ covariance @ f.T + self.accel_std**2 * b @ b.T
            covariance = .5*(covariance + covariance.T)
            now = timestamp
            if kind == 0:
                acceleration = value
            else:
                s = covariance[:3, :3] + np.eye(3)*sigma**2
                innovation = value - state[:3]
                normalized = float(innovation @ np.linalg.solve(s, innovation))
                if normalized > self.maximum_nis:
                    gated += 1
                    decisions[identifier] = False
                else:
                    kalman = np.linalg.solve(s, covariance[:3, :]).T
                    state += kalman @ innovation
                    j = np.eye(6)
                    j[:, :3] -= kalman
                    covariance = j @ covariance @ j.T + sigma**2 * kalman @ kalman.T
                    covariance = .5*(covariance + covariance.T)
                    accepted += 1
                    decisions[identifier] = True
            if timestamp < cutoff:
                to_prune.append(identifier)
                checkpoint = (now, state.copy(), covariance.copy(), acceleration.copy(), accepted, gated)
        self.snapshot = FusionSnapshot(now, tuple(state[:3]), tuple(state[3:]),
                                       covariance, accepted, gated)
        if checkpoint is not None:
            (self._anchor_time, self._anchor_state, self._anchor_covariance,
             self._anchor_acceleration, self._anchor_accepted, self._anchor_gated) = checkpoint
            old = set(to_prune)
            self.events = [event for event in self.events if event[2] not in old]
        return decisions
