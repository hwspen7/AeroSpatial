# Spatial reference-frame contract

## WGS84 frames

`NativeFrames.ecef` produces a geocentric Earth-centered Earth-fixed vector with named `x`, `y`, `z` components. `NativeFrames.enu(from:to:)` produces a **local tangent-frame displacement** east, north, up in meters. Both inputs require WGS84 geographic latitude/longitude and **ellipsoidal heights in the same reference**.

The older `NativeGeometry.localENU` is a spherical short-range approximation, intended for relative directions over at most 50 km. It is not a replacement for WGS84 ECEF/ENU when precise geometry is needed.

**Do not feed Mavic Air 2 `relative takeoff altitude` into an ellipsoidal-height argument.** That altitude has a different vertical datum. Unknown vertical alignment must remain unknown.

## Pose composition

`SpatialTransform` maps points from a child frame into a parent frame and contains an ENU-like metric translation plus a unit quaternion. `transform.composed(with: childTransform)` returns the child-to-grandparent transform. `inverted()` reverses a measured/calibrated relation. `FrameGraph.link(parent:child:transform:)` stores both directions and rejects an already-connected alternative path. `resolve(from:to:)` fails if no calibrated path exists.

The graph does **not** infer the relationship among AirPods, phone, aircraft, camera and world frames. Those links require separate calibration and validated sensor data. The graph intentionally does not interpolate dynamic transforms or hide drift.

Quaternion conversion uses right-handed intrinsic ZYX. AirPods `CMDeviceMotion` attitude and phone true-north heading are not assumed to share the same frame without explicit calibration.

## Accuracy requirements for future modules

Future SLAM, camera-ray triangulation, target geolocation and audio HRTF systems must carry uncertainty, time-validity, camera intrinsics and frame identity. Coordinates obtained solely from the aircraft GPS do not establish a target object's location.
