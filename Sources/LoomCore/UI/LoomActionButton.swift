import AppKit

/// NSButton subclass that adds a 120ms accent-coloured background
/// flash on press. macOS 26 / Liquid Glass made the native
/// rounded-button press feedback subtler than older system versions;
/// this gives the user an unambiguous "I just clicked that" cue
/// without departing from native button behaviour or styling
/// otherwise.
///
/// Use anywhere a click feedback matters more than the default —
/// generation tray buttons, acceptance overlay, sidebar +Scene, etc.
public final class LoomActionButton: NSButton {

    public override func mouseDown(with event: NSEvent) {
        flashOnce()
        super.mouseDown(with: event)
    }

    /// 120ms tint flash on the button's layer. Keyed animation so
    /// repeated clicks don't queue — each click resets the flash.
    private func flashOnce() {
        wantsLayer = true
        guard let layer = layer else { return }
        let originalColor = layer.backgroundColor
        let flashColor = DesignTokens.Foreground.accent.withAlphaComponent(0.25).cgColor

        let key = "loom.flash"
        layer.removeAnimation(forKey: key)

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = flashColor
        animation.toValue = originalColor ?? NSColor.clear.cgColor
        animation.duration = DesignTokens.Motion.hoverFade
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }
}
