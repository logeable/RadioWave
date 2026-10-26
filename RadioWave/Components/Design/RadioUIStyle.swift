import SwiftUI

enum RadioUIStyle {
    static let accent = Color.accentColor
    static let live = Color(red: 0.94, green: 0.31, blue: 0.25)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.35)
    static let cornerSmall: CGFloat = 9
    static let cornerMedium: CGFloat = 14
    static let cornerLarge: CGFloat = 22
}

// MARK: - Reusable components
