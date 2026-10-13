import SwiftUI
import UserNotifications

@main
struct SaleHunterApp: App {
    @StateObject private var favorites = FavoritesStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(favorites)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { AlertChecker.scheduleNext() }
        }
        .backgroundTask(.appRefresh(AlertChecker.taskID)) {
            await AlertChecker.runInBackground()
        }
    }
}

enum Theme {
    static let gold = Color(red: 0.91, green: 0.76, blue: 0.42)
    static let sale = Color(red: 1.0, green: 0.35, blue: 0.37)
    static let fresh = Color(red: 0.30, green: 0.76, blue: 0.54)
    static let card = Color(white: 0.11)
}

struct RootView: View {
    var body: some View {
        TabView {
            SaleView()
                .tabItem { Label("Sale", systemImage: "tag") }
            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "heart") }
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
    }
}
