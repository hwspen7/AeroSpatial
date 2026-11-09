import Foundation
#if os(iOS)
import Darwin

/// Read-only OS diagnostics. GPU utilization is not exposed as a general public
/// iOS metric; Instruments is required for GPU and energy profiling.
struct MobileRuntimeHealth {
    let residentBytes: UInt64?
    let thermal: String

    static func sample() -> MobileRuntimeHealth {
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size /
                                           MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
            }
        }
        return MobileRuntimeHealth(residentBytes: status == KERN_SUCCESS ?
                                    UInt64(info.resident_size) : nil, thermal: thermal)
    }
}
#endif
