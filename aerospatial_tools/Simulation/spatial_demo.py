"""Seeded, hardware-free spatial geometry experiment with independently known truth."""
from __future__ import annotations
import numpy as np


def run(*, seed=42) -> dict[str, float | int | str]:
    import cv2
    from .visual_geometry import solve_camera_pose, triangulate_observations
    from .bundle_adjustment import optimize_bundle, Reprojection
    from .pose_graph import PoseGraph, RelativeEdge
    from .estimation_quality import validate_covariance
    if type(seed) is not int or not 0 <= seed < 2**32:
        raise ValueError('invalid seed')
    rng = np.random.default_rng(seed)
    k = np.array([[580.,0,320.],[0,585.,240.],[0,0,1.]])
    points = np.column_stack([rng.uniform(-1,1,12),rng.uniform(-1,1,12),rng.uniform(4,8,12)])
    poses = np.array([[0.,0,0,0,0,0],[0,.03,0,-.7,0,0]])
    observations=[]
    pixels=[]
    for camera_id,pose in enumerate(poses):
        uv,_=cv2.projectPoints(points, pose[:3], pose[3:], k, None)
        noisy=uv.reshape(-1,2) + rng.normal(0,.08,(len(points),2))
        pixels.append(noisy)
        observations.extend(Reprojection(camera_id,j,float(p[0]),float(p[1]),.08)
                            for j,p in enumerate(noisy))
    estimate=solve_camera_pose(points,pixels[1],k, minimum_inliers=8)
    if estimate is None:
        raise RuntimeError('PnP failed fixture validation')
    p0=k@np.c_[np.eye(3),np.zeros(3)]
    r1,_=cv2.Rodrigues(poses[1,:3])
    p1=k@np.c_[r1,poses[1,3:]]
    triangles,indices=triangulate_observations(pixels[0],pixels[1],p0,p1,
                                                maximum_reprojection_error=2)
    init=poses.copy();init[1]+=[.01,-.01,.01,.03,-.02,.02]
    estimated_points=points+rng.normal(0,.02,points.shape)
    estimated_points[0]=points[0]
    bundle=optimize_bundle(init,estimated_points,observations,k,
                           maximum_iterations=100,metric_anchor_landmark_index=0)
    graph=PoseGraph()
    graph.add_pose('zero',[0,0,0],[0,0,0])
    graph.add_pose('one',[1.2,.1,0],[0,0,.02])
    graph.add_pose('two',[2.3,.3,0],[0,0,.01])
    graph.add_edge(RelativeEdge('zero','one',(1,0,0),(0,0,0)))
    graph.add_edge(RelativeEdge('one','two',(1,0,0),(0,0,0)))
    graph.add_edge(RelativeEdge('zero','two',(2,0,0),(0,0,0)))
    optimized=graph.optimize()
    position_error=float(np.linalg.norm(estimate.translation-poses[1,3:]))
    triangulation_error=float(np.mean(np.linalg.norm(triangles-points[list(indices)],axis=1)))
    output={
        'seed':seed, 'pnp_inliers':len(estimate.inlier_indices),
        'pnp_translation_error_m':round(position_error,8),
        'triangulated_landmarks':len(indices),
        'triangulation_mean_error_m':round(triangulation_error,8),
        'bundle_rms_reprojection_pixels':round(bundle.root_mean_square_pixels,8),
        'pose_graph_normalized_rms':round(optimized.root_mean_square_normalized_residual,8),
        'status':'passed' if (bundle.success and optimized.success and len(indices)>=10 and
           len(estimate.inlier_indices)>=10 and position_error<.1 and
           triangulation_error<.2 and bundle.root_mean_square_pixels<.5 and
           optimized.root_mean_square_normalized_residual<1e-5) else 'failed'
    }
    return output
