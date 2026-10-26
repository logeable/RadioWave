import SwiftUI

enum RadioPlaybackStatus: Equatable {
    case connecting
    case live
    case paused
    case failed

    var title: String {
        switch self {
        case .connecting: "正在连接"
        case .live: "直播中"
        case .paused: "已暂停"
        case .failed: "播放失败"
        }
    }

    var color: Color {
        switch self {
        case .connecting: .orange
        case .live: RadioUIStyle.live
        case .paused: .secondary
        case .failed: .red
        }
    }

    var symbol: String {
        switch self {
        case .connecting: "arrow.trianglehead.2.clockwise.rotate.90"
        case .live: "dot.radiowaves.left.and.right"
        case .paused: "pause.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }
}
