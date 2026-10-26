import SwiftUI

struct StationSearchField: View {
    @Binding var text: String
    var placeholder = "搜索电台、类型或地区"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(RadioUIStyle.surface, in: RoundedRectangle(cornerRadius: RadioUIStyle.cornerSmall))
    }
}
