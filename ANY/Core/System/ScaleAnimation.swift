import AppKit

/// Scales a layer-backed view about its center using a layer animation only; the model transform
/// stays identity, so an interrupted animation can never leave the view scaled.
enum ScaleAnimation {
    enum Curve {
        case spring(duration: TimeInterval, bounce: CGFloat)
        case easeIn(duration: TimeInterval)
    }

    private static let key = "any.scale"

    static func animate(_ view: NSView, from: CGFloat, to: CGFloat, curve: Curve) {
        guard let layer = view.layer else { return }
        // Pivot on the view's center, expressed relative to the layer's anchor point, which
        // AppKit may place at the corner or the center.
        let size = view.bounds.size
        let center = CGPoint(x: size.width * (0.5 - layer.anchorPoint.x), y: size.height * (0.5 - layer.anchorPoint.y))
        func transform(_ scale: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(center.x, center.y, 0)
            t = CATransform3DScale(t, scale, scale, 1)
            return CATransform3DTranslate(t, -center.x, -center.y, 0)
        }

        let animation: CABasicAnimation
        switch curve {
        case .spring(let duration, let bounce):
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            spring.duration = spring.settlingDuration
            animation = spring
        case .easeIn(let duration):
            animation = CABasicAnimation()
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        }
        animation.keyPath = "transform"
        // When interrupting (e.g. reopened mid-exit), continue from wherever the view currently is.
        if layer.animation(forKey: key) != nil, let current = layer.presentation()?.transform {
            animation.fromValue = current
        } else {
            animation.fromValue = transform(from)
        }
        animation.toValue = transform(to)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = to == 1
        layer.add(animation, forKey: key)
    }

    static func reset(_ view: NSView) {
        view.layer?.removeAnimation(forKey: key)
    }
}
