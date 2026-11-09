import Foundation
import AeroSpatialNative

/// Offline/native bulk geometry. This API must not be called from the real-time command callback.
public enum NativeBatch {
    public enum Error: Swift.Error { case invalidInput }

    public static func ecef(points: [GeodeticPosition]) throws -> [ECEFVector] {
        guard points.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite && $0.ellipsoidHeightMeters.isFinite &&
            abs($0.latitude) <= 90 && abs($0.longitude) <= 180 && abs($0.ellipsoidHeightMeters) <= 1e7
        }) else { throw Error.invalidInput }
        if points.isEmpty { return [] }
        let input = points.map { ASGeodetic3(latitude: $0.latitude,
                                             longitude: $0.longitude, altitude: $0.ellipsoidHeightMeters) }
        var output = [ASVector3](repeating: ASVector3(x: 0, y: 0, z: 0), count: points.count)
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                as_wgs84_ecef_batch(source.baseAddress, source.count, destination.baseAddress)
            }
        }
        guard status == AS_OK else { throw Error.invalidInput }
        return output.map { ECEFVector(x: $0.x, y: $0.y, z: $0.z) }
    }

    public static func lowpass(_ input: [Double], alpha: Double, initial: Double = 0) throws -> [Double] {
        guard alpha.isFinite, (0...1).contains(alpha), initial.isFinite,
              input.allSatisfy({ $0.isFinite }) else { throw Error.invalidInput }
        if input.isEmpty { return [] }
        var output = [Double](repeating: 0, count: input.count)
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                as_lowpass_batch(source.baseAddress, source.count, alpha, initial, destination.baseAddress)
            }
        }
        guard status == AS_OK else { throw Error.invalidInput }
        return output
    }
}
