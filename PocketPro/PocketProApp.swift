import SwiftUI
import SwiftData

@main
struct PocketProApp: App {
    private let container = PersistenceController.makeContainer()
    @State private var ballDatabase = BallDatabaseService()
    @State private var importService = PinPalImportService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(ballDatabase)
                .environment(importService)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
