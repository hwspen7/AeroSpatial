"""Covariance consistency and normalized innovation quality checks.

Chi-square thresholds are probabilistic *under correct Gaussian model assumptions*;
passing them is not a guarantee of real-world location accuracy.
"""
from __future__ import annotations
from dataclasses import dataclass
import math
import numpy as np
from scipy.stats import chi2


@dataclass(frozen=True)
class ConsistencyReport:
    sample_count: int
    mean_nees: float
    within_confidence_fraction: float
    lower_chi_square: float
    upper_chi_square: float


def validate_covariance(covariance, *, symmetry_atol=1e-8, min_eigenvalue=-1e-10):
    p = np.asarray(covariance, dtype=float)
    if (p.ndim != 2 or p.shape[0] != p.shape[1] or not 1 <= p.shape[0] <= 100 or
        not np.isfinite(p).all() or not np.allclose(p, p.T, atol=symmetry_atol)):
        raise ValueError('invalid covariance')
    if float(np.linalg.eigvalsh(p).min()) < min_eigenvalue:
        raise ValueError('covariance is not positive-semidefinite')
    return p


def evaluate_nees(errors, covariances, *, confidence=.95) -> ConsistencyReport:
    vectors = np.asarray(errors, dtype=float)
    matrices = np.asarray(covariances, dtype=float)
    if (vectors.ndim != 2 or not 1 <= len(vectors) <= 100000 or
        matrices.shape != (len(vectors), vectors.shape[1], vectors.shape[1]) or
        not 0.5 <= confidence < 1 or not np.isfinite(vectors).all()):
        raise ValueError('invalid consistency dataset')
    lower = float(chi2.ppf((1 - confidence)/2, vectors.shape[1]))
    upper = float(chi2.ppf((1 + confidence)/2, vectors.shape[1]))
    values = []
    for error, covariance in zip(vectors, matrices):
        p = validate_covariance(covariance)
        if np.linalg.eigvalsh(p).min() <= 0:
            raise ValueError('NEES needs a strictly positive covariance')
        values.append(float(error @ np.linalg.solve(p, error)))
    return ConsistencyReport(len(values), float(np.mean(values)),
                             float(np.mean((np.asarray(values) >= lower) & (np.asarray(values) <= upper))),
                             lower, upper)
