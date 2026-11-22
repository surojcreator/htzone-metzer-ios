//
//  HTZoneMetzerApp.swift
//  HTZoneMetzer
//

import SwiftUI

@main
struct HTZoneMetzerApp: App {
    @StateObject private var app = AppState()
    @StateObject private var library = LibraryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(library)
        }
    }
}
