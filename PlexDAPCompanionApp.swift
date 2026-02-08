import SwiftUI

@main
struct PlexDAPCompanionApp: App {
    @StateObject private var authService = PlexAuthService.shared

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
            } else {
                PlexLoginView() // This matches the code we added above
            }
        }
        .windowResizability(.contentSize) // Optional: keeps the login window small
    }
}
