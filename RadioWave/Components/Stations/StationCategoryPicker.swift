import SwiftUI

enum RadioStationCategory: String, CaseIterable, Identifiable {
    case recommended = "推荐"
    case favorites = "收藏"
    case all = "全部"
    var id: String { rawValue }
}


struct StationCategoryPicker: View {
    @Binding var selection: RadioStationCategory

    var body: some View {
        Picker("电台分类", selection: $selection) {
            ForEach(RadioStationCategory.allCases) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("电台分类")
    }
}
