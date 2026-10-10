import SwiftUI
import UIKit

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    let root: URL

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SolarProjects", isDirectory: true)
        self.root = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        load()
    }

    private var indexURL: URL { root.appendingPathComponent("projects.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = list
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(projects) { try? data.write(to: indexURL, options: .atomic) }
    }

    @discardableResult
    func create() -> Project {
        let p = Project()
        projects.insert(p, at: 0)
        save()
        return p
    }

    func delete(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: dir(for: projects[i].id)) }
        projects.remove(atOffsets: offsets)
        save()
    }

    func update(_ p: Project) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        projects[i] = p
        save()
    }

    func binding(_ id: UUID) -> Binding<Project> {
        Binding(
            get: { self.projects.first(where: { $0.id == id }) ?? Project() },
            set: { self.update($0) }
        )
    }

    // MARK: Files

    func dir(for id: UUID) -> URL {
        let u = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func exportsDir(for id: UUID) -> URL {
        let u = dir(for: id).appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func image(for p: Project) -> UIImage? {
        guard let n = p.roofImageName else { return nil }
        return UIImage(contentsOfFile: dir(for: p.id).appendingPathComponent(n).path)
    }

    func videoURL(for p: Project) -> URL? {
        guard let n = p.videoName else { return nil }
        let u = dir(for: p.id).appendingPathComponent(n)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Stores a new roof image (normalised to 1 px = 1 pixel) and resets the outline/scale.
    func setRoofImage(_ img: UIImage, metersPerPixel: Double, in project: inout Project) {
        let norm = img.normalizedToPixels()
        let name = "roof-\(Int(Date().timeIntervalSince1970)).jpg"
        if let data = norm.jpegData(compressionQuality: 0.9) {
            try? data.write(to: dir(for: project.id).appendingPathComponent(name))
        }
        project.roofImageName = name
        project.imageWidth = norm.size.width
        project.imageHeight = norm.size.height
        project.metersPerPixel = metersPerPixel
        project.imageNorthBearing = 0
        project.roofPolygon = []
        project.obstacles = []
    }

    func importVideo(from src: URL, into project: inout Project) throws {
        let name = "survey-\(Int(Date().timeIntervalSince1970)).mov"
        let dst = dir(for: project.id).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
        project.videoName = name
    }
}

extension UIImage {
    /// Re-renders so that size == pixel size (scale 1) and orientation is baked in.
    func normalizedToPixels() -> UIImage {
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: px, format: f).image { _ in draw(in: CGRect(origin: .zero, size: px)) }
    }
}
