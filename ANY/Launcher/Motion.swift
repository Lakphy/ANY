import SwiftUI

/// Shared animation curves, so the launcher moves with one consistent rhythm.
enum Motion {
    static let page = Animation.spring(duration: 0.34, bounce: 0.12)
    static let selection = Animation.snappy(duration: 0.16)
    static let hoverSelection = Animation.snappy(duration: 0.12)
    static let press = Animation.snappy(duration: 0.12)
    static let overlay = Animation.spring(duration: 0.3, bounce: 0.18)

    static let dismissDuration: TimeInterval = 0.14
    /// Panel scale at the start of its entrance and the end of its exit.
    static let presentScale: CGFloat = 0.97
    static let dismissScale: CGFloat = 0.98
}

extension AnyTransition {
    /// New page slides in from the side it's coming from; the old page simply fades out.
    static func page(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? 28 : -28).combined(with: .opacity),
            removal: .opacity
        )
    }

    static let pop = AnyTransition.scale(scale: 0.94).combined(with: .opacity)
}
