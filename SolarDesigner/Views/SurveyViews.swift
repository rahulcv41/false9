import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { received in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return MovieFile(url: dst)
        }
    }
}

/// Step 3 — obstacle mapping: import a 360° video (shot on site or pre-recorded) or mark the skyline live with the camera.
struct SurveyView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var pick: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Capture") {
                NavigationLink { RecordTurnView(project: $project) } label: {
                    Label("Record video turning around (recommended)", systemImage: "record.circle")
                }
                PhotosPicker(selection: $pick, matching: .videos) {
                    Label(project.videoName == nil ? "Import a turn-around video" : "Replace video", systemImage: "video.badge.plus")
                }
                if importing { ProgressView("Importing…") }
                if let e = error { Text(e).foregroundStyle(.red).font(.footnote) }
                if store.videoURL(for: project) != nil {
                    NavigationLink { VideoTaggerView(project: $project) } label: {
                        Label("Tag obstacles in the video", systemImage: "scope")
                    }
                }
                NavigationLink { LiveSkylineView(project: $project) } label: {
                    Label("Mark skyline live on site (camera + compass)", systemImage: "camera.metering.center.weighted")
                }
                Text("Any normal phone video works: stand in the middle of the roof and turn one full circle. Recording it here also logs the compass so directions are exact; an imported video assumes one steady full turn. Or skip video and mark obstacle tops live with the camera.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Skyline preview") {
                SkylineChart(project: project).frame(height: 190)
                if !project.horizon.isEmpty {
                    Text("Max obstruction \(Int(project.horizon.map { $0.elevation }.max() ?? 0))° above the horizon").font(.footnote)
                }
            }

            Section("Marked points (\(project.horizon.count))") {
                ForEach(project.horizon.sorted { $0.azimuth < $1.azimuth }) { h in
                    HStack {
                        Text(h.label.isEmpty ? "Obstacle" : h.label)
                        Spacer()
                        Text(String(format: "Az %.0f°  El %.0f°", h.azimuth, h.elevation)).font(.footnote.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    let sorted = project.horizon.sorted { $0.azimuth < $1.azimuth }
                    let ids = Set(idx.map { sorted[$0].id })
                    project.horizon.removeAll { ids.contains($0.id) }
                }
                if !project.horizon.isEmpty {
                    Button("Clear all", role: .destructive) { project.horizon = [] }
                }
            }
        }
        .navigationTitle("Obstacle survey")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pick) { _, item in
            guard let item = item else { return }
            importing = true; error = nil
            Task {
                defer { importing = false }
                do {
                    if let movie = try await item.loadTransferable(type: MovieFile.self) {
                        try store.importVideo(from: movie.url, into: &project)
                        project.videoSamples = []
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

/// Polar skyline: centre = zenith, rim = horizon, north up.
struct SkylineChart: View {
    let project: Project

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = min(size.width, size.height) / 2 - 12
            func pt(_ az: Double, _ el: Double) -> CGPoint {
                let r = R * (90 - el) / 90, a = az * .pi / 180
                return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
            }
            for el in [0.0, 30, 60] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * (90 - el) / 90, y: c.y - R * (90 - el) / 90, width: 2 * R * (90 - el) / 90, height: 2 * R * (90 - el) / 90)),
                           with: .color(.gray.opacity(0.4)), lineWidth: 0.7)
            }
            for az in stride(from: 0.0, to: 360, by: 90) {
                var l = Path(); l.move(to: c); l.addLine(to: pt(az, 0)); ctx.stroke(l, with: .color(.gray.opacity(0.4)), lineWidth: 0.7)
            }
            for (t, az) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
                let p = pt(az, -9)
                ctx.draw(Text(t).font(.caption.bold()), at: p)
            }
            // horizon fill
            let prof = HorizonProfile(points: project.horizon)
            var sky = Path()
            for az in 0...360 {
                let p = pt(Double(az), prof.elevation(at: Double(az % 360)))
                az == 0 ? sky.move(to: p) : sky.addLine(to: p)
            }
            sky.closeSubpath()
            var outer = Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
            outer.addPath(sky)
            ctx.fill(outer, with: .color(.red.opacity(0.35)), style: FillStyle(eoFill: true))
            // sun paths
            if project.hasLocation {
                for (m, d, col) in [(5, 21, Color.orange), (2, 21, Color.yellow), (11, 21, Color.blue)] {
                    let pts = Solar.sunPath(month: m, day: d, latitude: project.latitude, longitude: project.longitude)
                    var path = Path()
                    for (i, s) in pts.enumerated() { i == 0 ? path.move(to: pt(s.azimuth, s.elevation)) : path.addLine(to: pt(s.azimuth, s.elevation)) }
                    ctx.stroke(path, with: .color(col), lineWidth: 1.8)
                }
            }
        }
    }
}

// MARK: - Video tagging

struct VideoTaggerView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var asset: AVAsset?
    @State private var duration = 1.0
    @State private var time = 0.0
    @State private var frame: UIImage?
    @State private var label = ""

    private var hasLog: Bool { !project.videoSamples.isEmpty }
    private var aspect: Double { frame.map { Double($0.size.width / max($0.size.height, 1)) } ?? 0.75 }
    private var vfov: Double { project.videoHFOV / aspect }

    /// Where the camera pointed at video time t.
    private func aimAt(_ t: Double) -> (az: Double, el: Double) {
        let s = project.videoSamples
        guard let first = s.first, let last = s.last else {
            var az = (project.videoStartHeading + 360 * t / max(duration, 0.1)).truncatingRemainder(dividingBy: 360)
            if az < 0 { az += 360 }
            return (az, 0)
        }
        if t <= first.t { return (first.az, first.el) }
        if t >= last.t { return (last.az, last.el) }
        let i = s.lastIndex { $0.t <= t } ?? 0
        let a = s[i], b = s[min(i + 1, s.count - 1)]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        var d = b.az - a.az
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        var az = (a.az + d * f).truncatingRemainder(dividingBy: 360)
        if az < 0 { az += 360 }
        return (az, a.el + (b.el - a.el) * f)
    }

    var body: some View {
        let aimNow = aimAt(time)
        VStack(spacing: 10) {
            GeometryReader { geo in
                let rect = fitRect(geo.size)
                ZStack {
                    Color.black
                    if let f = frame { Image(uiImage: f).resizable().aspectRatio(contentMode: .fit) }
                    Canvas { ctx, _ in
                        for h in project.horizon {
                            var rel = (h.azimuth - aimNow.az).truncatingRemainder(dividingBy: 360)
                            if rel > 180 { rel -= 360 } else if rel < -180 { rel += 360 }
                            guard abs(rel) < project.videoHFOV / 2 else { continue }
                            let x = rect.minX + (rel / project.videoHFOV + 0.5) * rect.width
                            let y = rect.minY + (0.5 - (h.elevation - aimNow.el) / vfov) * rect.height
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(.red))
                        }
                    }.allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in
                    guard rect.contains(v.location) else { return }
                    let nx = (v.location.x - rect.minX) / rect.width, ny = (v.location.y - rect.minY) / rect.height
                    var az = (aimNow.az + (nx - 0.5) * project.videoHFOV).truncatingRemainder(dividingBy: 360)
                    if az < 0 { az += 360 }
                    let el = aimNow.el + (0.5 - ny) * vfov
                    project.horizon.append(HorizonPoint(azimuth: az, elevation: max(0, el), label: label))
                })
            }
            .frame(height: 340)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scrub the video and tap the TOP edge of every obstacle (trees, buildings, towers). Red dots = already marked.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $time, in: 0...max(duration, 0.1), onEditingChanged: { editing in
                        if !editing { Task { await loadFrame() } }
                    })
                    Text(String(format: "Camera aim: heading %.0f°, tilt %.0f°", aimNow.az, aimNow.el)).font(.footnote.monospaced())
                    if !hasLog {
                        Text(String(format: "Start heading (compass direction you faced at 0:00): %.0f°", project.videoStartHeading)).font(.footnote)
                        Slider(value: $project.videoStartHeading, in: 0...359, step: 1)
                        Text("Assumes you turned one steady full circle over the whole video.").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(String(format: "Camera field of view %.0f° (wide lens ≈ 45–65° depending on orientation)", project.videoHFOV)).font(.footnote)
                    Slider(value: $project.videoHFOV, in: 30...120, step: 1)
                    TextField("Label for next mark (optional)", text: $label).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Undo last") { _ = project.horizon.popLast() }.buttonStyle(.bordered).disabled(project.horizon.isEmpty)
                        Spacer()
                        Text("\(project.horizon.count) marks")
                    }
                }.padding(.horizontal)
            }
        }
        .navigationTitle("Tag obstacles")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let url = store.videoURL(for: project) else { return }
            let a = AVURLAsset(url: url)
            asset = a
            duration = (try? await a.load(.duration).seconds) ?? 1
            await loadFrame()
        }
    }

    private func fitRect(_ size: CGSize) -> CGRect {
        var w = size.width, h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func loadFrame() async {
        guard let asset = asset else { return }
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 1600, height: 1600)
        if let r = try? await g.image(at: CMTime(seconds: time, preferredTimescale: 600)) {
            frame = UIImage(cgImage: r.image)
        }
    }
}

final class CameraController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movie = AVCaptureMovieFileOutput()
    private var configured = false
    @Published var recording = false
    var onFinished: ((URL) -> Void)?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if !self.configured {
                    self.session.beginConfiguration()
                    if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                       let input = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(input) {
                        self.session.addInput(input)
                    }
                    if self.session.canAddOutput(self.movie) { self.session.addOutput(self.movie) }
                    self.session.commitConfiguration()
                    self.configured = true
                }
                self.session.startRunning()
            }
        }
    }
    func stop() { DispatchQueue.global().async { self.session.stopRunning() } }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("turn-\(UUID().uuidString).mov")
        movie.startRecording(to: url, recordingDelegate: self)
        recording = true
    }
    func stopRecording() { movie.stopRecording() }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.recording = false
            self.onFinished?(outputFileURL)
        }
    }
}

/// Record a normal video while turning on the spot; compass + tilt are logged so every frame has a known direction.
struct RecordTurnView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraController()
    @StateObject private var aim = AimService()
    @StateObject private var loc = LocationService()
    @State private var samples: [HeadingSample] = []
    @State private var startedAt = Date()
    @State private var swept = Set<Int>()
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            CameraPreview(session: cam.session).ignoresSafeArea()
            VStack {
                Text(String(format: "Heading %.0f°   Tilt %.0f°   Covered %d%%", aim.azimuth, aim.elevation, swept.count * 100 / 36))
                    .font(.headline.monospaced()).padding(8).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                Spacer()
                Text(cam.recording ? "Turn slowly on the spot until Covered reaches 100 %, then stop."
                                   : "Stand in the middle of the roof, hold the phone upright, press record and turn one full circle (about 30 s). Keep the horizon in the middle of the screen.")
                    .font(.footnote).padding(10).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                Button {
                    if cam.recording { cam.stopRecording() } else { samples = []; swept = []; startedAt = Date(); cam.startRecording() }
                } label: {
                    Circle().fill(.red).frame(width: 70, height: 70)
                        .overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 82, height: 82))
                        .overlay(cam.recording ? AnyView(RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 26, height: 26)) : AnyView(EmptyView()))
                }.padding(.bottom, 24)
            }.padding(.top, 8)
        }
        .navigationTitle("Record turn-around")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { _ in
            guard cam.recording else { return }
            samples.append(HeadingSample(t: Date().timeIntervalSince(startedAt), az: aim.azimuth, el: aim.elevation))
            swept.insert(Int(aim.azimuth / 10) % 36)
        }
        .onAppear {
            cam.onFinished = { url in
                do {
                    try store.importVideo(from: url, into: &project)
                    project.videoSamples = samples
                    dismiss()
                } catch {}
            }
            cam.start(); aim.start(); loc.request()
        }
        .onDisappear { cam.stop(); aim.stop() }
    }
}

struct LiveSkylineView: View {
    @Binding var project: Project
    @StateObject private var cam = CameraController()
    @StateObject private var aim = AimService()
    @StateObject private var loc = LocationService()
    @State private var label = ""

    var body: some View {
        ZStack {
            CameraPreview(session: cam.session).ignoresSafeArea()
            Image(systemName: "plus").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.yellow)
            VStack {
                Text(String(format: "Heading %.0f°   Elevation %.0f°", aim.azimuth, aim.elevation))
                    .font(.title3.monospaced()).padding(8).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                if !aim.available { Text("Motion sensors unavailable on this device").foregroundStyle(.red) }
                Spacer()
                VStack(spacing: 10) {
                    SkylineChart(project: project).frame(height: 120).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    TextField("Label (tree, tower…)", text: $label).textFieldStyle(.roundedBorder)
                    HStack {
                        Button { _ = project.horizon.popLast() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(.bordered).disabled(project.horizon.isEmpty)
                        Button {
                            project.horizon.append(HorizonPoint(azimuth: aim.azimuth, elevation: max(0, aim.elevation), label: label))
                        } label: { Label("Mark top of obstacle", systemImage: "scope").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("Hold the phone upright on the roof, centre the + on the top of the obstacle, tap Mark. Walk the full circle. Keep away from metal for a good compass.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.8))
                }.padding()
            }.padding(.top, 8)
        }
        .navigationTitle("Live skyline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cam.start(); aim.start(); loc.request() }
        .onDisappear { cam.stop(); aim.stop() }
    }
}
