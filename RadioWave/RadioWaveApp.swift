//
//  RadioWaveApp.swift
//  RadioWave
//
//  Created by 李小龙 on 2026/10/20.
//

import SwiftUI

@main
struct RadioWaveApp: App {
    @StateObject private var library = RadioLibraryViewModel()
    @StateObject private var player = RadioPlayerViewModel()
    @StateObject private var navigation = RadioNavigationModel()

    var body: some Scene {
        Window("Radio", id: "main") {
            ContentView(library: library, player: player, navigation: navigation)
        }
        .defaultSize(width: 760, height: 600)

        MenuBarExtra("Radio", systemImage: "dot.radiowaves.left.and.right") {
            RadioMenuBarView(player: player, library: library, navigation: navigation)
        }
        .menuBarExtraStyle(.window)

        Settings {
            RadioSettingsView(library: library)
        }
    }
}
