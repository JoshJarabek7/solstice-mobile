import UIKit

@MainActor
enum HapticManager {
  static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) async {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.prepare()
    generator.impactOccurred()
  }

  static func notification(type: UINotificationFeedbackGenerator.FeedbackType) async {
    let generator = UINotificationFeedbackGenerator()
    generator.prepare()
    generator.notificationOccurred(type)
  }

  static func selection() async {
    let generator = UISelectionFeedbackGenerator()
    generator.prepare()
    generator.selectionChanged()
  }

  // Predefined feedback patterns
  static func lightTap() async {
    await impact(style: .light)
  }

  static func mediumTap() async {
    await impact(style: .medium)
  }

  static func heavyTap() async {
    await impact(style: .heavy)
  }

  static func success() async {
    await notification(type: .success)
  }

  static func error() async {
    await notification(type: .error)
  }

  static func warning() async {
    await notification(type: .warning)
  }

  static func scroll() async {
    await selection()
  }

  static func like() async {
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.prepare()

    // Double tap pattern
    generator.impactOccurred(intensity: 0.5)
    try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
    generator.impactOccurred(intensity: 1.0)
  }
}
