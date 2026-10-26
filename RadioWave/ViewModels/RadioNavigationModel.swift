import Combine

@MainActor
final class RadioNavigationModel: ObservableObject {
    @Published var showingStations = false
    @Published var didApplyLaunchBehavior = false
}
