import SwiftUI

@main
struct P2POfflineProApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SplashContainerView()
                .environmentObject(store)
                .preferredColorScheme(store.preferences.useDarkTheme ? .dark : .light)
                .task {
                    while !Task.isCancelled {
                        if scenePhase == .active { await store.onlineSync.sync() }
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                store.runAutomaticBackupIfNeeded()
                Task { await store.onlineSync.sync() }
            }
        }
    }
}
