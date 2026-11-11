import SwiftUI

/// A button for irreversible actions: the first click arms it for a few seconds, the second performs.
struct TwoStepButton: View {
    let title: String
    let confirmTitle: String
    let action: () -> Void

    @State private var isArmed = false
    @State private var resetTask: Task<Void, Never>?

    init(_ title: String, confirmTitle: String = "再次点击以确认", action: @escaping () -> Void) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.action = action
    }

    var body: some View {
        Button(isArmed ? confirmTitle : title, action: tap)
            .contentTransition(.interpolate)
    }

    private func tap() {
        resetTask?.cancel()
        guard isArmed else {
            withAnimation(Motion.press) { isArmed = true }
            resetTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.press) { isArmed = false }
            }
            return
        }
        action()
        withAnimation(Motion.press) { isArmed = false }
    }
}
