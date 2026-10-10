import SwiftUI
import MapKit
import PhotosUI

/// Step 1 — find the roof (search / paste Google-Maps coordinates / GPS), zoom in, then capture the satellite view.
struct SiteCaptureView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @StateObject private var loc = LocationService()

    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var query = ""
    @State private var mapSize: CGSize = .zero
    @State private var busy = false
    @State private var message: String?
    @State private var photoItem: PhotosPickerItem?
    @AppStorage("googleMapsKey") private var gKey = ""
    @State private var showKey = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Address, place, or paste lat, lon from Google Maps", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button { loc.request() } label: { Image(systemName: "location.fill") }
            }
            .padding(10)
            .background(.bar)

            GeometryReader { geo in
                ZStack {
                    Map(position: $position) {
                        UserAnnotation()
                    }
                    .mapStyle(.imagery(elevation: .flat))
                    .onMapCameraChange(frequency: .onEnd) { ctx in region = ctx.region }
                    .mapControls { MapCompass(); MapScaleView() }

                    // aiming reticle
                    Image(systemName: "plus").font(.title.weight(.thin)).foregroundStyle(.white).shadow(radius: 2)
                        .allowsHitTesting(false)
                }
                .onAppear { mapSize = geo.size }
                .onChange(of: geo.size) { _, s in mapSize = s }
            }

            VStack(spacing: 8) {
                if let region = region {
                    Text(String(format: "Centre: %.6f, %.6f", region.center.latitude, region.center.longitude))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Zoom to roof") { zoomIn() }.buttonStyle(.bordered)
                    if let region = region {
                        Link("Open in Google Maps", destination: URL(string: "https://www.google.com/maps/search/?api=1&query=\(region.center.latitude),\(region.center.longitude)")!)
                            .font(.footnote)
                    }
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Import", systemImage: "photo")
                    }.buttonStyle(.bordered)
                }
                Button { if gKey.isEmpty { showKey = true } else { Task { await captureGoogle() } } } label: {
                    HStack {
                        if busy { ProgressView() }
                        Label("Confirm location & capture Google satellite", systemImage: "camera.viewfinder")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || region == nil)
                HStack {
                    Button("Capture from Apple Maps instead") { Task { await capture() } }
                        .font(.footnote).disabled(busy || region == nil)
                    Spacer()
                    Button("Google API key") { showKey = true }.font(.footnote)
                }
                if let m = message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                Text("Tip: pinch to zoom until the roof fills the screen and centre the + on it (the map is only for locating; the captured image comes from Google at that spot). Scale is calibrated automatically.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Site & roof image")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: loc.location) { _, l in
            guard let l = l else { return }
            position = .region(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 120, longitudinalMeters: 120))
        }
        .alert("Google Maps API key", isPresented: $showKey) {
            TextField("Paste key (Maps Static API enabled)", text: $gKey).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save") {}
        } message: { Text("Create a key in Google Cloud Console and enable “Maps Static API”. The key stays on this device.") }
        .onChange(of: photoItem) { _, item in Task { await importPhoto(item) } }
        .onAppear {
            if project.hasLocation {
                position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: project.latitude, longitude: project.longitude),
                                                      latitudinalMeters: 120, longitudinalMeters: 120))
            }
        }
    }

    private func zoomIn() {
        guard let c = region?.center else { return }
        position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 60, longitudinalMeters: 60))
    }

    private func search() async {
        let parts = query.split(whereSeparator: { ",; ".contains($0) }).compactMap { Double($0) }
        if parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 {
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]),
                                                  latitudinalMeters: 100, longitudinalMeters: 100))
            return
        }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let r = region { req.region = r }
        if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
            position = .region(MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 150, longitudinalMeters: 150))
            if project.address.isEmpty { project.address = item.placemark.title ?? query }
        } else {
            message = "Nothing found for “\(query)”."
        }
    }

    private func capture() async {
        guard let region = region, mapSize.width > 0 else { return }
        busy = true; defer { busy = false }
        let opts = MKMapSnapshotter.Options()
        opts.region = region
        opts.size = mapSize
        opts.scale = 3
        opts.mapType = .satellite
        opts.showsBuildings = false
        do {
            let snap = try await MKMapSnapshotter(options: opts).start()
            let c = region.center, span = region.span
            let a = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude - span.longitudeDelta / 4)
            let b = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude + span.longitudeDelta / 4)
            let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let pa = snap.point(for: a), pb = snap.point(for: b)
            let px = hypot(Double(pb.x - pa.x), Double(pb.y - pa.y)) * Double(snap.image.scale)
            guard px > 0 else { message = "Could not calibrate scale."; return }
            if !project.hasLocation, c.latitude < 0 { project.azimuthDeg = 0 }   // southern hemisphere: face north
            project.latitude = c.latitude; project.longitude = c.longitude; project.hasLocation = true
            store.setRoofImage(snap.image, metersPerPixel: meters / px, in: &project)
            message = String(format: "Captured. Scale %.3f m/pixel — now outline the roof (step 2).", project.metersPerPixel)
        } catch {
            message = "Snapshot failed: \(error.localizedDescription)"
        }
    }

    /// Google Static Maps satellite tile centred on the map reticle, zoomed to roughly match the visible area.
    private func captureGoogle() async {
        guard let region = region else { return }
        busy = true; defer { busy = false }
        let lat = region.center.latitude, lon = region.center.longitude
        let widthM = region.span.longitudeDelta / 360 * 40_075_016 * cos(lat * .pi / 180)
        let base = 156_543.03392 * cos(lat * .pi / 180)
        let z = max(17, min(21, Int(floor(log2(640 * base / max(widthM, 10))))))
        var c = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        c.queryItems = [
            .init(name: "center", value: "\(lat),\(lon)"), .init(name: "zoom", value: "\(z)"),
            .init(name: "size", value: "640x640"), .init(name: "scale", value: "2"),
            .init(name: "maptype", value: "satellite"), .init(name: "key", value: gKey)
        ]
        do {
            let (data, resp) = try await URLSession.shared.data(from: c.url!)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else {
                message = "Google returned an error — check the API key and that Maps Static API is enabled."; return
            }
            if !project.hasLocation, lat < 0 { project.azimuthDeg = 0 }
            project.latitude = lat; project.longitude = lon; project.hasLocation = true
            let mpp = base / pow(2, Double(z)) / 2          // scale=2 → 2 px per map pixel
            store.setRoofImage(img, metersPerPixel: mpp, in: &project)
            message = String(format: "Google image captured (zoom %d, %.3f m/pixel). Now outline the roof (step 2).", z, mpp)
        } catch {
            message = "Download failed: \(error.localizedDescription)"
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        if let r = region, !project.hasLocation {
            project.latitude = r.center.latitude; project.longitude = r.center.longitude; project.hasLocation = true
        }
        store.setRoofImage(img, metersPerPixel: 0, in: &project)
        message = "Imported. Set the scale in step 2 (tap two points a known distance apart). Image must be north-up."
    }
}
