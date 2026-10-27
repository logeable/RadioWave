import SwiftUI

struct ContentView: View {
    private struct BackgroundImageLayer: Identifiable {
        let id = UUID()
        let image: NSImage
    }

    @ObservedObject var library: RadioLibraryViewModel
    @ObservedObject var player: RadioPlayerViewModel
    @ObservedObject var navigation: RadioNavigationModel
    @ObservedObject private var imageGeneration = ImageGenerationService.shared
    @State private var backgroundImageLayers: [BackgroundImageLayer] = []

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
        .background(windowBackground)
        .onAppear {
            RadioWaveLog.info("Application window opened", category: "Application")
            if backgroundImageLayers.isEmpty, let image = player.generatedBackgroundImage {
                backgroundImageLayers = [BackgroundImageLayer(image: image)]
            }
            applyLaunchBehaviorIfNeeded()
        }
        .onChange(of: player.generatedBackgroundImage) { _, image in
            withAnimation(.easeInOut(duration: 1.2)) {
                backgroundImageLayers = image.map { [BackgroundImageLayer(image: $0)] } ?? []
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard player.currentStation != nil else { return .ignored }
            player.togglePlayback()
            return .handled
        }
    }

    private var windowBackground: some View {
        GeometryReader { geometry in
            ZStack {
                RadioUIStyle.canvas
                ForEach(backgroundImageLayers) { layer in
                    Image(nsImage: layer.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: imageGeneration.backgroundBlurRadius)
                        .opacity(1 - imageGeneration.backgroundTransparency)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
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
