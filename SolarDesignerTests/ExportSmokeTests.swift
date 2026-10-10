import XCTest
@testable import SolarDesigner

@MainActor
final class ExportSmokeTests: XCTestCase {
    func testExportsAreGenerated() throws {
        let store = ProjectStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("smoke-\(UUID().uuidString)"))
        let id = Demo.seed(store)
        let project = store.projects.first { $0.id == id }!
        let b = DesignBundle.make(project: project, store: store)

        XCTAssertGreaterThan(b.design.panelCount, 20)
        XCTAssertGreaterThan(b.shade.annualKWh, 1000)
        XCTAssertGreaterThan(b.shade.annualShadeLossPct, 0)
        print("DEMO panels=\(b.design.panelCount) kWp=\(b.design.dcKWp) strings=\(b.design.stringCount)x\(b.design.panelsPerString) kWh=\(b.shade.annualKWh) shade=\(b.shade.annualShadeLossPct)% warnings=\(b.design.warnings)")

        let out = URL(fileURLWithPath: "/tmp/solar-exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try ReportPDF.makePDF(b, url: out.appendingPathComponent("Report.pdf"))
        try SLDRenderer.makePDF(project: b.project, design: b.design, url: out.appendingPathComponent("SLD.pdf"))
        try LayoutDrawingPDF.makePDF(b, url: out.appendingPathComponent("Layout.pdf"))
        for n in ["Report", "SLD", "Layout"] {
            let size = (try FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("\(n).pdf").path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 2000, "\(n).pdf too small")
        }
        if let img = Scene3D.renderImage(b), let data = img.jpegData(compressionQuality: 0.9) {
            try data.write(to: out.appendingPathComponent("3D-view.jpg"))
        } else {
            print("DEMO 3D render unavailable in this environment")
        }
    }
}
