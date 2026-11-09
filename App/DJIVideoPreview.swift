#if canImport(DJISDK) && canImport(DJIWidget)
import SwiftUI
import DJIWidget

/// Official DJIWidget hardware-assisted live preview when the optional SDK
/// build is installed. Preview availability is not a substitute for testing
/// decoded-frame access, timestamps or camera calibration.
struct DJIVideoPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black
        DJIVideoPreviewer.instance().setView(container)
        DJIVideoPreviewer.instance().start()
        return container
    }

    func updateUIView(_ view: UIView, context: Context) { }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        DJIVideoPreviewer.instance().unSetView()
    }
}
#endif
