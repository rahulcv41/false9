import Foundation

enum RoofType: String, Codable, CaseIterable, Identifiable {
    case flat = "Flat roof – tilted frames"
    case pitched = "Pitched roof – flush mount"
    var id: String { rawValue }
}

enum PanelOrientation: String, Codable, CaseIterable, Identifiable {
    case landscape = "Landscape"
    case portrait = "Portrait"
    var id: String { rawValue }
}

enum ObstacleKind: String, Codable, CaseIterable, Identifiable {
    case tank = "Water tank"
    case stair = "Stair / head-room"
    case chimney = "Chimney / vent"
    case parapet = "Parapet wall"
    case equipment = "AC / equipment"
    case other = "Other"
    var id: String { rawValue }
}

struct RoofObstacle: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ObstacleKind = .tank
    var centerPx: Pt                // position on the roof image (pixels)
    var width: Double = 1.0         // metres
    var depth: Double = 1.0
    var height: Double = 1.5        // metres above roof
    var rotationDeg: Double = 0     // CCW
}

/// One point of the skyline: where an obstruction's top edge appears.
struct HorizonPoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var azimuth: Double             // ° clockwise from true north
    var elevation: Double           // ° above horizon
    var label: String = ""
    var halfWidth: Double = 3       // ° each side that the mark covers
}

struct PanelSpec: Codable, Hashable {
    var name = "Generic 550 W mono"
    var watt = 550.0
    var lengthM = 2.279
    var widthM = 1.134
    var vmp = 41.8
    var voc = 49.9
    var isc = 14.0
    var tempCoeffVocPct = -0.27     // %/°C
    static let presets: [PanelSpec] = [
        PanelSpec(),
        PanelSpec(name: "Generic 440 W mono", watt: 440, lengthM: 1.762, widthM: 1.134, vmp: 33.5, voc: 40.2, isc: 13.8, tempCoeffVocPct: -0.27),
        PanelSpec(name: "Generic 620 W TOPCon", watt: 620, lengthM: 2.382, widthM: 1.134, vmp: 45.6, voc: 54.4, isc: 14.4, tempCoeffVocPct: -0.25)
    ]
}

struct InverterSpec: Codable, Hashable {
    var name = "Generic 10 kW 3-phase"
    var acKW = 10.0
    var maxDCV = 1000.0
    var mpptMin = 200.0
    var mpptMax = 800.0
    var mpptCount = 2
    var stringsPerMPPT = 2
    var maxCurrentPerMPPT = 26.0
    var threePhase = true
    static let presets: [InverterSpec] = [
        InverterSpec(name: "Generic 3 kW 1-phase", acKW: 3, maxDCV: 600, mpptMin: 100, mpptMax: 500, mpptCount: 1, stringsPerMPPT: 2, maxCurrentPerMPPT: 16, threePhase: false),
        InverterSpec(name: "Generic 5 kW 1-phase", acKW: 5, maxDCV: 600, mpptMin: 120, mpptMax: 500, mpptCount: 2, stringsPerMPPT: 1, maxCurrentPerMPPT: 16, threePhase: false),
        InverterSpec(),
        InverterSpec(name: "Generic 25 kW 3-phase", acKW: 25, maxDCV: 1100, mpptMin: 200, mpptMax: 1000, mpptCount: 3, stringsPerMPPT: 2, maxCurrentPerMPPT: 32, threePhase: true),
        InverterSpec(name: "Generic 50 kW 3-phase", acKW: 50, maxDCV: 1100, mpptMin: 200, mpptMax: 1000, mpptCount: 5, stringsPerMPPT: 2, maxCurrentPerMPPT: 32, threePhase: true)
    ]
}

struct Project: Codable, Identifiable {
    var id = UUID()
    var name = "New solar project"
    var client = ""
    var address = ""
    var createdAt = Date()

    // Site
    var hasLocation = false
    var latitude = 0.0
    var longitude = 0.0

    // Roof image
    var roofImageName: String?
    var imageWidth = 0.0            // px
    var imageHeight = 0.0
    var metersPerPixel = 0.0        // 0 = not calibrated yet
    var imageNorthBearing = 0.0     // ° bearing of the image's "up" direction (0 = north-up)
    var roofPolygon: [Pt] = []      // pixels
    var obstacles: [RoofObstacle] = []

    // 360° / skyline survey
    var videoName: String?
    var horizon: [HorizonPoint] = []

    // System
    var roofType: RoofType = .flat
    var buildingHeight = 10.0       // m, for 3D
    var tiltDeg = 15.0              // tilt (flat) or roof pitch (pitched)
    var azimuthDeg = 180.0          // direction panels face, clockwise from north
    var orientation: PanelOrientation = .landscape
    var setbackM = 0.6
    var obstacleClearanceM = 0.3
    var panel = PanelSpec()
    var inverter = InverterSpec()

    // Yield & economics
    var clearnessFactor = 0.72      // actual / clear-sky irradiation
    var performanceRatio = 0.80
    var tariffPerKWh = 8.0
    var costPerKWp = 45000.0
    var currency = "₹"
    var gridEmissionFactor = 0.82   // kg CO₂ / kWh

    // MARK: Derived geometry

    var isCalibrated: Bool { metersPerPixel > 0 }

    func toWorld(_ p: Pt) -> Pt {
        let a = imageNorthBearing * .pi / 180
        let x = p.x * metersPerPixel, y = -p.y * metersPerPixel
        return Pt(x * cos(a) + y * sin(a), -x * sin(a) + y * cos(a))
    }

    var roofWorld: [Pt] { roofPolygon.map(toWorld) }
    var roofAreaM2: Double { Geo.area(roofWorld) }

    func obstacleCorners(_ o: RoofObstacle, clearance: Double = 0) -> [Pt] {
        Geo.rect(center: toWorld(o.centerPx), w: o.width + 2 * clearance, d: o.depth + 2 * clearance,
                 rotation: o.rotationDeg * .pi / 180)
    }
}
