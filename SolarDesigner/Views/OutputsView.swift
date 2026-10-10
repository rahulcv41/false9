import SwiftUI
import PDFKit
import AVKit

struct ExportFile: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: URL
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// Step 7 — everything the client or installer needs.
struct OutputsView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var busy: String?
    @State private var progress = 0.0
    @State private var files: [ExportFile] = []
    @State private var render: UIImage?
    @State private var previewPDF: ExportFile?
    @State private var player: AVPlayer?
    @State private var error: String?

    var body: some View {
        List {
            Section("Generate") {
                action("Project report (PDF)", "doc.richtext") { b, dir in
                    let u = dir.appendingPathComponent("Report.pdf")
                    try ReportPDF.makePDF(b, url: u); return ExportFile(title: "Project report", url: u)
                }
                action("Single-line diagram – SLD (PDF)", "bolt.horizontal") { b, dir in
                    let u = dir.appendingPathComponent("SLD.pdf")
                    try SLDRenderer.makePDF(project: b.project, design: b.design, url: u); return ExportFile(title: "Single-line diagram", url: u)
                }
                action("2D layout drawing (PDF)", "square.grid.3x3") { b, dir in
                    let u = dir.appendingPathComponent("Layout.pdf")
                    try LayoutDrawingPDF.makePDF(b, url: u); return ExportFile(title: "2D layout", url: u)
                }
                action("3D visual (image)", "cube") { b, dir in
                    guard let img = Scene3D.renderImage(b), let data = img.jpegData(compressionQuality: 0.92) else { throw ExportError.render }
                    let u = dir.appendingPathComponent("3D-view.jpg"); try data.write(to: u)
                    DispatchQueue.main.async { render = img }
                    return ExportFile(title: "3D visual", url: u)
                }
                action("3D fly-around video (MP4)", "video") { b, dir in
                    let u = dir.appendingPathComponent("3D-flyaround.mp4")
                    try Scene3D.renderVideo(b, url: u) { p in DispatchQueue.main.async { progress = p } }
                    DispatchQueue.main.async { player = AVPlayer(url: u) }
                    return ExportFile(title: "3D video", url: u)
                }
            }

            if let busy = busy {
                Section { HStack { ProgressView(); Text("Creating \(busy)…") }
                    if progress > 0 && progress < 1 { ProgressView(value: progress) } }
            }
            if let e = error { Section { Text(e).foregroundStyle(.red) } }

            if !files.isEmpty {
                Section("Ready") {
                    ForEach(files) { f in
                        HStack {
                            Button(f.title) { if f.url.pathExtension == "pdf" { previewPDF = f } }
                                .disabled(f.url.pathExtension != "pdf")
                            Spacer()
                            ShareLink(item: f.url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
            }
            if let img = render {
                Section("3D visual") { Image(uiImage: img).resizable().aspectRatio(contentMode: .fit) }
            }
            if let p = player {
                Section("3D fly-around") { VideoPlayer(player: p).frame(height: 220) }
            }
        }
        .navigationTitle("Outputs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewPDF) { f in
            NavigationStack {
                PDFPreview(url: f.url).navigationTitle(f.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: f.url) } }
            }
        }
    }

    enum ExportError: Error, LocalizedError {
        case render
        var errorDescription: String? { "3D rendering failed on this device." }
    }

    private func action(_ title: String, _ icon: String, _ work: @escaping (DesignBundle, URL) throws -> ExportFile) -> some View {
        Button {
            error = nil; busy = title; progress = 0
            let bundle = DesignBundle.make(project: project, store: store)
            let dir = store.exportsDir(for: project.id)
            Task.detached(priority: .userInitiated) {
                do {
                    let f = try work(bundle, dir)
                    await MainActor.run {
                        files.removeAll { $0.title == f.title }
                        files.append(f)
                        busy = nil
                        if f.url.pathExtension == "pdf" { previewPDF = f }
                    }
                } catch {
                    await MainActor.run { self.error = error.localizedDescription; busy = nil }
                }
            }
        } label: { Label(title, systemImage: icon) }
        .disabled(busy != nil || project.roofPolygon.count < 3 || !project.isCalibrated)
    }
}
