import SwiftUI

@main
struct SolarDesignerApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ProjectListView()
            }
            .environmentObject(store)
            .tint(.orange)
        }
    }
}
