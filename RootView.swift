import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var locked = false

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                DashboardView()
                    .tabItem { Label("Главная", systemImage: "house.fill") }
                    .tag(0)

                TransactionsView()
                    .tabItem { Label("Операции", systemImage: "arrow.left.arrow.right") }
                    .tag(1)

                ReportsView()
                    .tabItem { Label("Отчёты", systemImage: "doc.text.fill") }
                    .tag(2)

                SettingsView()
                    .tabItem { Label("Ещё", systemImage: "ellipsis.circle.fill") }
                    .tag(3)
            }
            .tint(AppTheme.green)
            .blur(radius: locked ? 12 : 0)

            if locked {
                AppLockView(
                    faceIDEnabled: store.preferences.faceIDEnabled,
                    pinEnabled: store.preferences.pinEnabled && PINManager.hasPIN,
                    onUnlocked: { withAnimation(.easeOut(duration: 0.18)) { locked = false } },
                    onFaceID: authenticateFaceID
                )
                .transition(.opacity)
            }
        }
        .onAppear { prepareLock() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background && securityEnabled {
                locked = true
            }
        }
    }

    private var securityEnabled: Bool {
        store.preferences.faceIDEnabled || (store.preferences.pinEnabled && PINManager.hasPIN)
    }

    private func prepareLock() {
        // Avoid a lockout after restore/reinstall if preference says PIN is on
        // but the Keychain PIN is not present on this device.
        if store.preferences.pinEnabled && !PINManager.hasPIN {
            var updated = store.preferences
            updated.pinEnabled = false
            store.preferences = updated
            store.save()
        }

        guard securityEnabled else {
            locked = false
            return
        }

        locked = true
        if store.preferences.faceIDEnabled { authenticateFaceID() }
    }

    private func authenticateFaceID() {
        guard store.preferences.faceIDEnabled else { return }
        SecurityManager.authenticateFaceID { success in
            if success {
                withAnimation(.easeOut(duration: 0.18)) { locked = false }
            }
        }
    }
}
