import SwiftUI

struct PlaybackStatusView: View {
    let status: RadioPlaybackStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            if status == .connecting {
                ProgressView().controlSize(.mini).tint(status.color)
            } else {
                Circle().fill(status.color).frame(width: 6, height: 6)
            }
            if !compact {
                Text(status.title)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 4 : 5)
        .background(status.color.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
    }
}
