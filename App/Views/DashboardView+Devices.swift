import SwiftUI
import AeroSpatialCore

extension DashboardView {
    var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(model.mode == .simulation ? "SIMULATION" : "LIVE SDK MODE",
                      systemImage: model.mode == .simulation ? "cube.transparent" : "airplane")
                    .font(.caption.bold())
                    .foregroundStyle(model.mode == .simulation ? .blue : .orange)
                Spacer()
                Label(model.aircraft.connected ? "Connected" : "Disconnected",
                      systemImage: model.aircraft.connected ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
            }
            Text(model.message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    var deviceCard: some View {
        card("Devices", icon: "antenna.radiowaves.left.and.right") {
            Picker("Drone", selection: Binding(get: { model.mode }, set: { model.switchMode($0) })) {
                ForEach(DroneMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                metric("Battery", model.aircraft.batteryPercent.map { "\($0)%" } ?? "—")
                metric("Altitude", model.aircraft.altitudeMeters.map { String(format: "%.0f m", $0) } ?? "—")
                metric("Gimbal", model.aircraft.gimbalPitchDegrees.map { String(format: "%.1f°", $0) } ?? "—")
            }
            Label(model.synchronized ? "Time-aligned sensors available" : "Waiting for synchronized sensor inputs",
                  systemImage: model.synchronized ? "checkmark.circle" : "clock")
                .font(.caption).foregroundStyle(.secondary)
            Text("Real DJI connection requires an SDK-equipped Mac build and a registered App Key. Simulation works without hardware.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var headCard: some View {
        card("Head motion", icon: "airpodspro") {
            HStack {
                Text(model.headSource)
                    .font(.subheadline)
                Spacer()
                Text(model.calibrated ? "Calibrated" : "Uncalibrated")
                    .font(.caption).foregroundStyle(model.calibrated ? .green : .secondary)
            }
            HStack(spacing: 12) {
                metric("Yaw", model.head.map { String(format: "%.1f°", $0.pose.yaw) } ?? "—")
                metric("Pitch", model.head.map { String(format: "%.1f°", $0.pose.pitch) } ?? "—")
                metric("Roll", model.head.map { String(format: "%.1f°", $0.pose.roll) } ?? "—")
            }
            HStack {
                Button("Start AirPods") { model.startHeadMotion() }
                    .buttonStyle(.borderedProminent)
                Button("Stop") { model.stopHeadMotion() }
                    .buttonStyle(.bordered)
                Spacer()
            }
            if model.mode == .simulation {
                Button("Use demo head input") { model.useDemoHead() }
                    .font(.subheadline)
                HStack {
                    Text("Pitch")
                    Slider(value: $model.demoHeadPitch, in: -55...55)
                }
                HStack {
                    Text("Yaw")
                    Slider(value: $model.demoHeadYaw, in: -90...90)
                }
            }
            Text("AirPods yaw is relative to a motion reference, not a compass bearing. Calibration maps head pitch to the current camera pitch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

}
