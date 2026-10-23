import SwiftUI

struct ContentView: View {
    @StateObject private var library = RadioLibraryViewModel()
    @StateObject private var player = RadioPlayerViewModel()
    @State private var showingFavorites = false

    var body: some View {
        VStack(spacing: 0) {
            StationBrowserView(library: library, player: player, showingFavorites: $showingFavorites)
            RadioPlayerBar(player: player, library: library)
        }
        .background(RadioPalette.canvas)
        .frame(minWidth: 760, minHeight: 560)
    }
}

#Preview {
    ContentView()
}
