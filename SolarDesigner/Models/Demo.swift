import UIKit

/// Synthetic project used for CI screenshots and export smoke tests (launch with `-demoScreen <name>`).
@MainActor
enum Demo {
    static func makeImage() -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { rc in
            let c = rc.cgContext
            UIColor(red: 0.42, green: 0.50, blue: 0.36, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.62, alpha: 1).setFill(); c.fill(CGRect(x: 200, y: 150, width: 800, height: 500))   // roof
            UIColor(white: 0.45, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 700, width: 1200, height: 100))    // road
            UIColor(red: 0.1, green: 0.35, blue: 0.1, alpha: 1).setFill()
            for (x, y) in [(60, 200), (90, 330), (70, 460), (1120, 250), (1100, 520)] {
                c.fillEllipse(in: CGRect(x: x - 40, y: y - 40, width: 80, height: 80))
            }
        }
    }

    static func seed(_ store: ProjectStore) -> UUID {
        var p = Project()
        p.name = "Demo rooftop 25 kW"
        p.client = "Demo client"
        p.address = "Demo building, New Delhi"
        p.hasLocation = true; p.latitude = 28.6139; p.longitude = 77.2090
        store.setRoofImage(makeImage(), metersPerPixel: 0.05, in: &p)
        p.roofPolygon = [Pt(200, 150), Pt(1000, 150), Pt(1000, 650), Pt(200, 650)]
        p.obstacles = [
            RoofObstacle(kind: .tank, centerPx: Pt(300, 250), width: 2, depth: 2, height: 2),
            RoofObstacle(kind: .stair, centerPx: Pt(900, 560), width: 4, depth: 3, height: 3)
        ]
        p.horizon = (240...290).map { HorizonPoint(azimuth: Double($0), elevation: 22, label: "Trees") }
            + (130...150).map { HorizonPoint(azimuth: Double($0), elevation: 14, label: "Building") }
        p.tiltDeg = 15
        store.insert(p)
        return p.id
    }
}
