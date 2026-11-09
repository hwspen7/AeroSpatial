import Foundation

/// Hardware output is disabled in the standard application binary.
/// The development flag must never be enabled in a distributed production build.
enum BenchSafety {
    static var allowsExperimentalGimbal: Bool {
        #if AEROSPATIAL_EXPERIMENTAL_BENCH
        return true
        #else
        return false
        #endif
    }
}
