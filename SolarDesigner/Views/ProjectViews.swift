import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        List {
            if store.projects.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "sun.max",
                                       description: Text("Tap + to start designing a solar plant."))
            }
            ForEach(store.projects) { p in
                NavigationLink(value: p.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.headline)
                        Text(p.client.isEmpty ? "No client" : p.client).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .navigationTitle("Solar Designer")
        .navigationDestination(for: UUID.self) { ProjectDetailView(id: $0) }
        .toolbar {
            Button { store.create() } label: { Image(systemName: "plus") }
        }
    }
}

struct ProjectDetailView: View {
    @EnvironmentObject var store: ProjectStore
    let id: UUID

    var body: some View {
        let p = store.binding(id)
        let v = p.wrappedValue
        Form {
            Section("Project") {
                TextField("Project name", text: p.name)
                TextField("Client", text: p.client)
                TextField("Site address", text: p.address)
            }
            Section("Design steps") {
                NavigationLink { SiteCaptureView(project: p) } label: {
                    StepLabel(n: 1, title: "Site & roof image", detail: "Find the roof on the map, zoom, capture", done: v.roofImageName != nil)
                }
                NavigationLink { RoofEditorView(project: p) } label: {
                    StepLabel(n: 2, title: "Roof outline & obstacles", detail: "Scale, boundary, tanks, stair-rooms", done: v.roofPolygon.count >= 3 && v.isCalibrated)
                }
                NavigationLink { SurveyView(project: p) } label: {
                    StepLabel(n: 3, title: "360° / skyline survey", detail: "Mark obstacles around the site", done: !v.horizon.isEmpty)
                }
                NavigationLink { SystemSettingsView(project: p) } label: {
                    StepLabel(n: 4, title: "Equipment & settings", detail: "Panel, inverter, tilt, tariff", done: true)
                }
                NavigationLink { LayoutView(project: p) } label: {
                    StepLabel(n: 5, title: "2D layout", detail: "Auto-place panels & strings", done: false)
                }
                NavigationLink { ShadeView(project: p) } label: {
                    StepLabel(n: 6, title: "Shade & yield analysis", detail: "Sun path, shade loss, kWh", done: false)
                }
                NavigationLink { OutputsView(project: p) } label: {
                    StepLabel(n: 7, title: "Report, SLD, drawings, 3D", detail: "PDF report, SLD, layout, render & video", done: false)
                }
            }
        }
        .navigationTitle(v.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StepLabel: View {
    let n: Int
    let title: String
    let detail: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.orange.opacity(0.2)).frame(width: 30, height: 30)
                if done { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) }
                else { Text("\(n)").font(.footnote.bold()).foregroundStyle(.orange) }
            }
            VStack(alignment: .leading) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
