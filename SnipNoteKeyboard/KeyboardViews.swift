import UIKit

/// Keyboard colours close to Apple's own keys, following the keyboard's light/dark appearance.
enum KeyboardPalette {
  static let key = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white }
  static let specialKey = UIColor {
    $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
  }
  static let keyShadow = UIColor { $0.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.35) : UIColor.black.withAlphaComponent(0.3) }
  static let pressed = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.85, alpha: 1) }
}

/// A plain key in the style of the system keyboard: no tint, a 1-pt bottom shadow.
final class KeyButton: UIButton {
  private let isSpecial: Bool

  init(title: String? = nil, symbol: String? = nil, special: Bool) {
    isSpecial = special
    super.init(frame: .zero)
    var config = UIButton.Configuration.plain()
    config.baseForegroundColor = .label
    if let title {
      var attributed = AttributedString(title)
      attributed.font = .systemFont(ofSize: 16)
      config.attributedTitle = attributed
    }
    if let symbol {
      config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
    }
    configuration = config
    layer.cornerRadius = 7
    layer.shadowOffset = CGSize(width: 0, height: 1)
    layer.shadowRadius = 0
    layer.shadowOpacity = 1
    configurationUpdateHandler = { [weak self] button in
      guard let self else { return }
      button.backgroundColor = button.isHighlighted ? KeyboardPalette.pressed : (self.isSpecial ? KeyboardPalette.specialKey : KeyboardPalette.key)
    }
    setNeedsUpdateConfiguration()
    // The layer's CGColor shadow does not follow light/dark by itself.
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: KeyButton, _: UITraitCollection) in
      button.updateShadowColor()
      button.setNeedsUpdateConfiguration()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateShadowColor()
  }

  private func updateShadowColor() {
    layer.shadowColor = KeyboardPalette.keyShadow.resolvedColor(with: traitCollection).cgColor
  }
}

/// A monochrome waveform of the most recent input levels, newest on the right.
final class WaveformView: UIView {
  private var levels: [CGFloat]
  private let barCount: Int

  init(barCount: Int = 28) {
    self.barCount = barCount
    levels = Array(repeating: 0, count: barCount)
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  override var intrinsicContentSize: CGSize { CGSize(width: CGFloat(barCount) * 6, height: 30) }

  func push(_ level: Float) {
    levels.removeFirst()
    levels.append(CGFloat(max(0, min(1, level))))
    setNeedsDisplay()
  }

  func reset() {
    levels = Array(repeating: 0, count: barCount)
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    let barWidth: CGFloat = 3
    let step = bounds.width / CGFloat(barCount)
    UIColor.label.setFill()
    for (index, level) in levels.enumerated() {
      let height = max(3, level * bounds.height)
      let x = CGFloat(index) * step + (step - barWidth) / 2
      let bar = CGRect(x: x, y: (bounds.height - height) / 2, width: barWidth, height: height)
      UIBezierPath(roundedRect: bar, cornerRadius: barWidth / 2).fill()
    }
  }
}
