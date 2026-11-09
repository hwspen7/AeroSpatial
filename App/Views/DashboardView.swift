import SwiftUI
import AeroSpatialCore

struct DashboardView: View {
    @StateObject var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @State var confirmLiveArm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    banner
                    deviceCard
                    headCard
                    controlCard
                    awarenessCard
                    diagnosticsCard
                    recordingCard
                    Text("No flight commands are implemented. Maintain visual line of sight, obey applicable regulations, and keep the remote controller available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("AeroSpatial")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, value in
            if value != .active { model.stop() }
            else { model.start() }
        }
        .alert("Enable live gimbal control?", isPresented: $confirmLiveArm) {
            Button("Cancel", role: .cancel) { }
            Button("Enable pitch only") { model.arm() }
        } message: {
            Text("This controls the real aircraft camera pitch. Verify the gimbal direction and limits with propellers removed before any flight test. The aircraft never receives flight-control commands.")
        }
    }

}
