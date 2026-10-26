import SwiftUI

struct ContentView: View {
    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var navigation: RadioNavigationModel

    var body: some View {
        Group {
            if navigation.showingStations {
                RadioStationBrowserScreen(
                    library: library,
                    player: player,
                    onBack: { navigation.showingStations = false },
                    onSelectStation: { navigation.showingStations = false }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                RadioPlayerScreen(
                    player: player,
                    library: library,
                    onShowStations: { navigation.showingStations = true }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: navigation.showingStations)
        .frame(minWidth: 420, minHeight: 560)
        .onAppear {
            RadioWaveLog.info("Application window opened", category: "Application")
            applyLaunchBehaviorIfNeeded()
        }
        .focusable()
        .onKeyPress(.space) {
            guard player.currentStation != nil else { return .ignored }
            player.togglePlayback()
            return .handled
        }
    }

    private func applyLaunchBehaviorIfNeeded() {
        guard !navigation.didApplyLaunchBehavior else { return }
        navigation.didApplyLaunchBehavior = true
        guard UserDefaults.standard.bool(forKey: "RadioWave.autoplayOnLaunch"),
              player.currentStation != nil else { return }
        player.togglePlayback()
    }
}
