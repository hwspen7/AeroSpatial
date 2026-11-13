"""First-order uncertainty propagation for measured camera rays and 3D poses.

Covariance is metric or angular covariance (radians^2), not an arbitrary score.
These are local Jacobian approximations, not certified confidence bounds.
"""
from __future__ import annotations
import numpy as np
from .estimation_quality import validate_covariance


def camera_ray_with_covariance(pixel_xy, camera_matrix, pixel_covariance):
    """Return unit optical ray, 3x3 tangent covariance and analytic 3x2 Jacobian."""
    uv = np.asarray(pixel_xy, dtype=float)
    k = np.asarray(camera_matrix, dtype=float)
    covariance = validate_covariance(pixel_covariance)
    if (uv.shape != (2,) or k.shape != (3,3) or covariance.shape != (2,2) or
        not np.isfinite(uv).all() or not np.isfinite(k).all() or k[0,0] <= 0 or
        k[1,1] <= 0 or not np.allclose(k[2], [0,0,1], atol=1e-12)):
        raise ValueError('invalid optical propagation input')
    direction = np.array([(uv[0]-k[0,2])/k[0,0],(uv[1]-k[1,2])/k[1,1],1.])
    length = np.linalg.norm(direction)
    ray = direction / length
    jacobian = (np.eye(3)-np.outer(ray,ray)) @ np.array([[1/k[0,0],0],
                                                            [0,1/k[1,1]],[0,0]]) / length
    ray_covariance = jacobian @ covariance @ jacobian.T
    return ray, ray_covariance, jacobian


def rigid_point_with_covariance(pose_translation, rotation_matrix, body_point,
                                pose_covariance, point_covariance):
    """Left-multiplicative SE(3) pose error, twist ordering [translation, rotation]."""
    translation=np.asarray(pose_translation,dtype=float)
    rotation=np.asarray(rotation_matrix,dtype=float)
    point=np.asarray(body_point,dtype=float)
    cp=validate_covariance(pose_covariance)
    cl=validate_covariance(point_covariance)
    if (translation.shape!=(3,) or rotation.shape!=(3,3) or point.shape!=(3,) or
        cp.shape!=(6,6) or cl.shape!=(3,3) or
        not np.isfinite(translation).all() or not np.isfinite(rotation).all() or
        not np.isfinite(point).all() or not np.allclose(rotation.T@rotation,np.eye(3),atol=1e-6) or
        abs(np.linalg.det(rotation)-1)>1e-6):
        raise ValueError('invalid rigid point propagation input')
    transformed=rotation@point + translation
    skew=np.array([[0,-transformed[2],transformed[1]],
                   [transformed[2],0,-transformed[0]],[-transformed[1],transformed[0],0]])
    jacobian=np.column_stack([np.eye(3),-skew])
    output=jacobian@cp@jacobian.T + rotation@cl@rotation.T
    return transformed,.5*(output+output.T)
