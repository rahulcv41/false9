import XCTest
@testable import SolarDesigner

final class CoreTests: XCTestCase {
    func testSunAtEquatorEquinoxNoonIsNearZenith() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2025, month: 3, day: 20, hour: 12))!
        let s = Solar.sunPosition(date: d, latitude: 0, longitude: 0)
        XCTAssertGreaterThan(s.elevation, 85)
    }

    func testDelhiSummerSolsticeNoonElevation() {
        // Delhi 28.6°N, 77.2°E. Solar noon ≈ 12:00 − 77.2/15 h UTC ≈ 06:51 UTC (± equation of time)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2025, month: 6, day: 21, hour: 6, minute: 51))!
        let s = Solar.sunPosition(date: d, latitude: 28.6, longitude: 77.2)
        XCTAssertEqual(s.elevation, 90 - 28.6 + 23.44, accuracy: 1.0)
    }

    func testNorthernNoonSunIsSouth() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2025, month: 12, day: 21, hour: 6, minute: 51))!
        let s = Solar.sunPosition(date: d, latitude: 28.6, longitude: 77.2)
        XCTAssertEqual(s.azimuth, 180, accuracy: 6)
    }

    func testPolygonHelpers() {
        let sq = [Pt(0, 0), Pt(4, 0), Pt(4, 3), Pt(0, 3)]
        XCTAssertEqual(Geo.area(sq), 12, accuracy: 1e-9)
        XCTAssertTrue(Geo.contains(sq, Pt(2, 1)))
        XCTAssertFalse(Geo.contains(sq, Pt(5, 1)))
        XCTAssertEqual(Geo.edgeDistance(sq, Pt(1, 1)), 1, accuracy: 1e-9)
        XCTAssertTrue(Geo.overlap(sq, [Pt(3, 2), Pt(6, 2), Pt(6, 5), Pt(3, 5)]))
        XCTAssertFalse(Geo.overlap(sq, [Pt(5, 0), Pt(6, 0), Pt(6, 1), Pt(5, 1)]))
    }

    private func roofProject(obstacle: Bool = false) -> Project {
        var p = Project()
        p.hasLocation = true; p.latitude = 28.6; p.longitude = 77.2
        p.metersPerPixel = 0.1
        p.imageWidth = 400; p.imageHeight = 300
        // 20 m × 12 m roof
        p.roofPolygon = [Pt(50, 50), Pt(250, 50), Pt(250, 170), Pt(50, 170)]
        if obstacle { p.obstacles = [RoofObstacle(centerPx: Pt(150, 110), width: 2, depth: 2, height: 2)] }
        return p
    }

    func testLayoutKeepsPanelsInsideRoofAndSetback() {
        let p = roofProject()
        let layout = LayoutEngine.generate(p)
        XCTAssertGreaterThan(layout.panels.count, 20)
        for pn in layout.panels {
            for c in pn.corners {
                XCTAssertTrue(Geo.contains(p.roofWorld, c))
                XCTAssertGreaterThanOrEqual(Geo.edgeDistance(p.roofWorld, c), p.setbackM - 1e-6)
            }
        }
    }

    func testLayoutAvoidsObstacle() {
        let p = roofProject(obstacle: true)
        let layout = LayoutEngine.generate(p)
        let blocked = p.obstacleCorners(p.obstacles[0], clearance: p.obstacleClearanceM)
        XCTAssertFalse(layout.panels.contains { Geo.overlap($0.corners, blocked) })
        XCTAssertLessThan(layout.panels.count, LayoutEngine.generate(roofProject()).panels.count)
    }

    func testStringsDivideEvenly() {
        let p = roofProject()
        var layout = LayoutEngine.generate(p)
        let d = SystemDesign.make(project: p, layout: &layout)
        XCTAssertGreaterThan(d.stringCount, 0)
        XCTAssertEqual(d.panelCount, d.stringCount * d.panelsPerString)
        XCTAssertEqual(layout.panels.count, d.panelCount)
        XCTAssertLessThanOrEqual(d.panelsPerString, d.maxPerString)
    }

    func testShadeLossIncreasesWithTallSkylineToTheSouth() {
        var p = roofProject()
        var layout = LayoutEngine.generate(p)
        _ = SystemDesign.make(project: p, layout: &layout)
        let clear = ShadeAnalysis.run(p, layout)
        XCTAssertGreaterThan(clear.annualKWh, 0)
        XCTAssertEqual(clear.annualShadeLossPct, 0, accuracy: 0.01)

        p.horizon = (120...240).map { HorizonPoint(azimuth: Double($0), elevation: 40) }
        let shaded = ShadeAnalysis.run(p, layout)
        XCTAssertGreaterThan(shaded.annualShadeLossPct, 5)
        XCTAssertLessThan(shaded.annualKWh, clear.annualKWh)
    }

    func testRoofObstacleCastsShadowOnNearbyPanels() {
        var p = roofProject(obstacle: true)
        p.obstacles[0].height = 6
        var layout = LayoutEngine.generate(p)
        _ = SystemDesign.make(project: p, layout: &layout)
        let r = ShadeAnalysis.run(p, layout)
        XCTAssertGreaterThan(r.perPanelLoss.max() ?? 0, 0.02)
    }
}
