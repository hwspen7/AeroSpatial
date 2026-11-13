"""Bounded window motion extrapolation with an explicit CV/CA model comparison.

Temporal least squares favors constant velocity unless acceleration improves BIC
on a sufficiently long interval. This predicts observations, never acts on an aircraft.
"""
from __future__ import annotations
from dataclasses import dataclass
import math
import numpy as np


@dataclass(frozen=True)
class MotionForecast:
    position_m: tuple[float,float,float]
    selected_model: str
    prediction_horizon_s: float
    residual_rms_m: float


class MotionPredictor:
    def __init__(self, *, capacity=64, maximum_horizon_s=2.0, acceleration_limit_mps2=15.0):
        if not 4 <= capacity <= 4096 or not 0 < maximum_horizon_s <= 10 or not 0 < acceleration_limit_mps2 <= 100:
            raise ValueError('invalid motion policy')
        self.capacity=capacity
        self.maximum_horizon_s=maximum_horizon_s
        self.acceleration_limit_mps2=acceleration_limit_mps2
        self.samples=[]

    def append(self, timestamp_s, position_m):
        p=np.asarray(position_m,dtype=float)
        if (not math.isfinite(timestamp_s) or timestamp_s<0 or p.shape!=(3,) or
            not np.isfinite(p).all() or (self.samples and timestamp_s<=self.samples[-1][0])):
            raise ValueError('invalid or out-of-order motion sample')
        self.samples.append((float(timestamp_s),p))
        if len(self.samples)>self.capacity:self.samples.pop(0)

    def forecast(self, timestamp_s:float) -> MotionForecast | None:
        if len(self.samples)<4 or not math.isfinite(timestamp_s):return None
        last=self.samples[-1][0]
        horizon=timestamp_s-last
        if horizon<0 or horizon>self.maximum_horizon_s:return None
        times=np.array([p[0]-last for p in self.samples])
        values=np.stack([p[1] for p in self.samples])
        # Avoid catastrophic conditioning when observing nearly identical timestamps.
        if np.ptp(times)<.15:return None
        models=[]
        for order in (1,2):
            if order==2 and len(times)<6:continue
            cols=[np.ones(len(times)),times]
            if order==2:cols.append(.5*times*times)
            x=np.column_stack(cols)
            coeff,residuals,rank,_=np.linalg.lstsq(x,values,rcond=None)
            if rank!=len(cols):continue
            if order==2 and np.linalg.norm(coeff[2])>self.acceleration_limit_mps2:continue
            residual=np.linalg.norm(x@coeff-values,axis=1)**2
            rss=max(1e-12,float(residual.sum()))
            # Number of parameters scales with three spatial axes.
            bic=len(times)*np.log(rss/len(times))+3*len(cols)*np.log(len(times))
            predicted=np.array([horizon**i/(2 if i==2 else 1) for i in range(len(cols))])@coeff
            models.append((bic,order,predicted,float(np.sqrt(rss/len(times)))))
        if not models:return None
        _,order,predicted,rms=min(models,key=lambda item:item[0])
        return MotionForecast(tuple(float(v) for v in predicted), 'constant_acceleration' if order==2
                              else 'constant_velocity',float(horizon),rms)
