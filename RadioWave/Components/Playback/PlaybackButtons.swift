import SwiftUI

struct RadioIconButton: View {
    let systemName: String
    let label: String
    var isSelected = false
    var selectedColor: Color = RadioUIStyle.accent
    var size: CGFloat = 34
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(isSelected ? selectedColor : Color.primary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}


struct PlayPauseButton: View {
    var isPlaying: Bool
    var isConnecting = false
    var isEnabled = true
    var size: CGFloat = 64
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Group {
                if isConnecting {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: size * 0.30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.92), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(isConnecting ? "正在连接" : (isPlaying ? "暂停" : "播放"))
        .accessibilityLabel(isConnecting ? "正在连接电台" : (isPlaying ? "暂停播放" : "开始播放"))
    }
}


struct FavoriteButton: View {
    var isFavorite: Bool
    var size: CGFloat = 36
    var action: () -> Void = {}

    var body: some View {
        RadioIconButton(
            systemName: isFavorite ? "heart.fill" : "heart",
            label: isFavorite ? "取消收藏" : "收藏电台",
            isSelected: isFavorite,
            selectedColor: .red,
            size: size,
            action: action
        )
    }
}
