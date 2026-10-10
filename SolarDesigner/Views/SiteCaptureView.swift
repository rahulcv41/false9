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
                Button { Task { await capture() } } label: {
                    HStack {
                        if busy { ProgressView() }
                        Label("Confirm location & capture screenshot", systemImage: "camera.viewfinder")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || region == nil)
                if let m = message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                Text("Tip: pinch to zoom until the roof fills the screen, centre the + on it, then capture. The pixel scale is calibrated automatically from the map.")
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

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        if let r = region, !project.hasLocation {
            project.latitude = r.center.latitude; project.longitude = r.center.longitude; project.hasLocation = true
        }
        store.setRoofImage(img, metersPerPixel: 0, in: &project)
        message = "Imported. Set the scale in step 2 (tap two points a known distance apart). Image must be north-up."
    }
}
