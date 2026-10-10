import SwiftUI

@main
@MainActor
struct SolarDesignerApp: App {
    @StateObject private var store: ProjectStore
    private let demoScreen: String?
    private let demoID: UUID?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count {
            let s = ProjectStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)"))
            demoID = Demo.seed(s)
            demoScreen = args[i + 1]
            _store = StateObject(wrappedValue: s)
        } else {
            demoID = nil; demoScreen = nil
            _store = StateObject(wrappedValue: ProjectStore())
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let screen = demoScreen, let id = demoID {
                    DemoRoot(screen: screen, id: id)
                } else {
                    ProjectListView()
                }
            }
            .environmentObject(store)
            .tint(.orange)
        }
    }
}

struct DemoRoot: View {
    @EnvironmentObject var store: ProjectStore
    let screen: String
    let id: UUID

    var body: some View {
        let p = store.binding(id)
        switch screen {
        case "detail": ProjectDetailView(id: id)
        case "site": SiteCaptureView(project: p)
        case "roof": RoofEditorView(project: p)
        case "survey": SurveyView(project: p)
        case "settings": SystemSettingsView(project: p)
        case "layout": LayoutView(project: p)
        case "shade": ShadeView(project: p)
        case "outputs": OutputsView(project: p)
        default: ProjectListView()
        }
    }
}
