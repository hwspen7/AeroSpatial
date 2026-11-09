"""Bounded 6-DoF relative-pose graph, optimized with robust least squares.

All positions are local metric coordinates and quaternions are represented as
scipy rotation vectors. The anchor remains fixed to remove the gauge freedom.
This is a small offline pose graph, not a production global SLAM backend.
"""
from __future__ import annotations
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class RelativeEdge:
    first: str
    second: str
    translation_first_m: tuple[float, float, float]
    rotation_first_to_second: tuple[float, float, float]
    translation_std_m: float = .3
    rotation_std_radians: float = .1


@dataclass(frozen=True)
class GraphSolution:
    poses: dict[str, tuple[tuple[float, ...], tuple[float, ...]]]
    root_mean_square_normalized_residual: float
    iterations: int
    success: bool


class PoseGraph:
    def __init__(self, *, maximum_nodes=64, maximum_edges=512):
        if not 2 <= maximum_nodes <= 1000 or not 1 <= maximum_edges <= 20000:
            raise ValueError('invalid graph capacity')
        self.nodes: dict[str, tuple[tuple[float, ...], tuple[float, ...]]] = {}
        self.edges: list[RelativeEdge] = []
        self.maximum_nodes, self.maximum_edges = maximum_nodes, maximum_edges

    def add_pose(self, identifier: str, translation_m, rotation_vector_rad):
        import numpy as np
        if type(identifier) is not str or not identifier or len(identifier) > 64 or (
            identifier in self.nodes or len(self.nodes) >= self.maximum_nodes
        ):
            raise ValueError('duplicate/invalid pose')
        t, r = np.asarray(translation_m, dtype=float), np.asarray(rotation_vector_rad, dtype=float)
        if t.shape != (3,) or r.shape != (3,) or not np.isfinite(t).all() or not np.isfinite(r).all():
            raise ValueError('invalid pose coordinates')
        self.nodes[identifier] = (tuple(t), tuple(r))

    def add_edge(self, edge: RelativeEdge):
        import numpy as np
        if edge.first == edge.second or edge.first not in self.nodes or edge.second not in self.nodes or (
            len(self.edges) >= self.maximum_edges
        ) or not (0 < edge.translation_std_m <= 1000 and 0 < edge.rotation_std_radians <= 10):
            raise ValueError('invalid relative pose constraint')
        if any(np.asarray(v).shape != (3,) or not np.isfinite(v).all()
               for v in (edge.translation_first_m, edge.rotation_first_to_second)):
            raise ValueError('invalid edge transform')
        self.edges.append(edge)

    def optimize(self, *, maximum_iterations=75, huber_scale=2.5) -> GraphSolution:
        import numpy as np
        from scipy.optimize import least_squares
        from scipy.spatial.transform import Rotation as R
        if not self.edges or not 5 <= maximum_iterations <= 500 or not math.isfinite(huber_scale) or huber_scale <= 0:
            raise ValueError('invalid graph optimization')
        names = list(self.nodes)
        accessible = {names[0]}
        for _ in range(len(names)):
            for edge in self.edges:
                if edge.first in accessible: accessible.add(edge.second)
                if edge.second in accessible: accessible.add(edge.first)
        if len(accessible) != len(names):
            raise ValueError('disconnected pose graph')
        estimate = np.asarray([self.nodes[name][0] + self.nodes[name][1] for name in names], dtype=float)
        def residual(flat):
            all_poses = np.concatenate([estimate[:1], flat.reshape(-1, 6)], axis=0)
            poses = {name: (p[:3], R.from_rotvec(p[3:])) for name, p in zip(names, all_poses)}
            values = []
            for edge in self.edges:
                ti, ri = poses[edge.first]
                tj, rj = poses[edge.second]
                predicted_t = ri.inv().apply(tj - ti)
                predicted_r = ri.inv() * rj
                error_r = (R.from_rotvec(edge.rotation_first_to_second).inv() * predicted_r).as_rotvec()
                values.extend((predicted_t - edge.translation_first_m) / edge.translation_std_m)
                values.extend(error_r / edge.rotation_std_radians)
            return np.asarray(values)
        opt = least_squares(residual, estimate[1:].ravel(), loss='huber', f_scale=huber_scale,
                            max_nfev=maximum_iterations)
        x = np.concatenate([estimate[:1], opt.x.reshape(-1, 6)], axis=0)
        final = {name: (tuple(p[:3]), tuple(p[3:])) for name, p in zip(names, x)}
        return GraphSolution(final, float(np.sqrt(np.mean(residual(opt.x)**2))),
                             int(opt.nfev), bool(opt.success))
