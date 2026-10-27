import SwiftUI

struct StationMetadataView: View {
    let station: RadioStationInfo
    var alignment: HorizontalAlignment = .leading
    var compact = false
    var detailColor: Color = .secondary

    var body: some View {
        VStack(alignment: alignment, spacing: compact ? 2 : 5) {
            Text(station.name)
                .font(.system(size: compact ? 13 : 20, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Text(station.detail)
                .font(.system(size: compact ? 10 : 12))
                .lineLimit(1)
                .foregroundStyle(detailColor)
        }
        .accessibilityElement(children: .combine)
    }
}
