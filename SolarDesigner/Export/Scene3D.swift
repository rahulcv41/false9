import SceneKit
import UIKit
import AVFoundation

/// Builds a 3D model of the building, array and obstacles. SceneKit axes: x = east, y = up, z = south.
enum Scene3D {
    struct Built {
        var scene: SCNScene
        var center: SCNVector3
        var radius: Float
    }

    static func build(_ b: DesignBundle, sunHour: Double = 11) -> Built {
        let p = b.project, layout = b.layout
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.62, green: 0.78, blue: 0.95, alpha: 1)

        let roof = p.roofWorld
        let bounds = Geo.bounds(roof)
        let cx = Float((bounds.min.x + bounds.max.x) / 2), cy = Float((bounds.min.y + bounds.max.y) / 2)
        let extent = Float(max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, 5))
        let H = CGFloat(p.buildingHeight)

        // ground (satellite image if we have it)
        let groundHolder = SCNNode()
        if let img = b.roofImage, p.isCalibrated {
            let plane = SCNPlane(width: p.imageWidth * p.metersPerPixel, height: p.imageHeight * p.metersPerPixel)
            let m = SCNMaterial(); m.diffuse.contents = img; m.isDoubleSided = true; m.lightingModel = .constant
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.eulerAngles.x = -.pi / 2
            let c = p.toWorld(Pt(p.imageWidth / 2, p.imageHeight / 2))
            groundHolder.position = SCNVector3(Float(c.x), -0.05, -Float(c.y))
            groundHolder.eulerAngles.y = Float(-p.imageNorthBearing * .pi / 180)
            groundHolder.addChildNode(n)
        } else {
            let plane = SCNPlane(width: 200, height: 200)
            plane.firstMaterial?.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            let n = SCNNode(geometry: plane); n.eulerAngles.x = -.pi / 2
            n.position = SCNVector3(cx, -0.05, -cy)
            groundHolder.addChildNode(n)
        }
        scene.rootNode.addChildNode(groundHolder)

        // building: walls as thin boxes + roof slab
        let wallMat = SCNMaterial(); wallMat.diffuse.contents = UIColor(red: 0.90, green: 0.86, blue: 0.78, alpha: 1)
        for i in 0..<roof.count {
            let a = roof[i], c = roof[(i + 1) % roof.count]
            let len = hypot(c.x - a.x, c.y - a.y)
            guard len > 0.01 else { continue }
            let box = SCNBox(width: CGFloat(len), height: H, length: 0.25, chamferRadius: 0)
            box.materials = [wallMat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(Float((a.x + c.x) / 2), Float(H / 2), -Float((a.y + c.y) / 2))
            n.eulerAngles.y = Float(atan2(c.y - a.y, c.x - a.x))
            scene.rootNode.addChildNode(n)
        }
        let path = UIBezierPath()
        for (i, q) in roof.enumerated() {
            let pt = CGPoint(x: q.x, y: q.y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        let slab = SCNShape(path: path, extrusionDepth: 0.15)
        slab.firstMaterial?.diffuse.contents = UIColor(white: 0.72, alpha: 1)
        let slabNode = SCNNode(geometry: slab)
        slabNode.eulerAngles.x = -.pi / 2          // shape y (north) → -z, extrusion → +y
        slabNode.position = SCNVector3(0, Float(H), 0)
        scene.rootNode.addChildNode(slabNode)

        // obstacles
        for o in p.obstacles {
            let c = p.toWorld(o.centerPx)
            let geo: SCNGeometry
            if o.kind == .tank {
                geo = SCNCylinder(radius: CGFloat(max(o.width, o.depth) / 2), height: CGFloat(o.height))
            } else {
                geo = SCNBox(width: CGFloat(o.width), height: CGFloat(o.height), length: CGFloat(o.depth), chamferRadius: 0)
            }
            geo.firstMaterial?.diffuse.contents = o.kind == .tank ? UIColor.systemTeal : UIColor.systemGray
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(Float(c.x), Float(H) + 0.15 + Float(o.height) / 2, -Float(c.y))
            n.eulerAngles.y = Float(o.rotationDeg * .pi / 180)
            scene.rootNode.addChildNode(n)
        }

        // panels
        let tilt = Float(layout.tiltDeg * .pi / 180)
        let yaw = Float(.pi - layout.azimuthDeg * .pi / 180)
        let panelMat = SCNMaterial()
        panelMat.diffuse.contents = UIColor(red: 0.06, green: 0.12, blue: 0.30, alpha: 1)
        panelMat.specular.contents = UIColor.white
        panelMat.shininess = 0.9
        let frame = SCNMaterial(); frame.diffuse.contents = UIColor(white: 0.8, alpha: 1)
        for pn in layout.panels {
            let box = SCNBox(width: CGFloat(layout.uSize), height: 0.035, length: CGFloat(layout.slope), chamferRadius: 0)
            box.materials = [frame, frame, frame, frame, panelMat, frame]   // top face = index 4
            let yawNode = SCNNode()
            let lift = Float(layout.slope) * sin(tilt) / 2 + (p.roofType == .flat ? 0.35 : 0.12)
            yawNode.position = SCNVector3(Float(pn.center.x), Float(H) + 0.15 + lift, -Float(pn.center.y))
            yawNode.eulerAngles.y = yaw
            let tiltNode = SCNNode(geometry: box)
            tiltNode.eulerAngles.x = tilt
            yawNode.addChildNode(tiltNode)
            scene.rootNode.addChildNode(yawNode)
        }

        // sun for lighting, from the real sun position on 21 Jun at the chosen solar hour
        let start = Solar.date(month: 5, day: 21).addingTimeInterval(-p.longitude / 15 * 3600)
        let sun = Solar.sunPosition(date: start.addingTimeInterval(sunHour * 3600), latitude: p.latitude, longitude: p.longitude)
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowRadius = 4
        light.shadowSampleCount = 8
        light.intensity = 1300
        let ln = SCNNode()
        ln.light = light
        let el = Float(max(sun.elevation, 15) * .pi / 180), az = Float(sun.azimuth * .pi / 180)
        let d: Float = 60
        ln.position = SCNVector3(cx + d * cos(el) * sin(az), d * sin(el), -cy - d * cos(el) * cos(az))
        ln.look(at: SCNVector3(cx, Float(H), -cy))
        scene.rootNode.addChildNode(ln)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 500
        scene.rootNode.addChildNode(amb)

        return Built(scene: scene, center: SCNVector3(cx, Float(H), -cy), radius: max(extent * 1.1, 12))
    }

    private static func cameraNode(_ built: Built, angle: Float, elevationDeg: Float = 38) -> SCNNode {
        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zFar = 2000
        let n = SCNNode()
        n.camera = cam
        let el = elevationDeg * .pi / 180
        n.position = SCNVector3(built.center.x + built.radius * cos(el) * sin(angle),
                                built.center.y + built.radius * sin(el),
                                built.center.z + built.radius * cos(el) * cos(angle))
        n.look(at: built.center)
        return n
    }

    static func renderImage(_ b: DesignBundle, size: CGSize = CGSize(width: 1600, height: 1000)) -> UIImage? {
        let built = build(b)
        let cam = cameraNode(built, angle: .pi * 0.85)
        built.scene.rootNode.addChildNode(cam)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = built.scene
        r.pointOfView = cam
        return r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    /// Orbit fly-around MP4 (H.264, 30 fps).
    static func renderVideo(_ b: DesignBundle, url: URL, seconds: Double = 8,
                            size: CGSize = CGSize(width: 1280, height: 720),
                            progress: ((Double) -> Void)? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let built = build(b)
        let cam = cameraNode(built, angle: 0)
        built.scene.rootNode.addChildNode(cam)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = built.scene
        renderer.pointOfView = cam

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                          kCVPixelBufferWidthKey as String: Int(size.width),
                                          kCVPixelBufferHeightKey as String: Int(size.height)])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 30
        let frames = Int(seconds * Double(fps))
        for i in 0..<frames {
            let t = Float(i) / Float(frames)
            let angle = .pi * 0.85 + t * 2 * .pi
            let elev: Float = 30 + 14 * sin(t * 2 * .pi)
            let tmp = cameraNode(built, angle: angle, elevationDeg: elev)
            cam.position = tmp.position
            cam.look(at: built.center)
            let img = renderer.snapshot(atTime: TimeInterval(i) / Double(fps), with: size, antialiasingMode: .multisampling4X)
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            if let buf = pixelBuffer(from: img, size: size, pool: adaptor.pixelBufferPool) {
                adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            }
            progress?(Double(i + 1) / Double(frames))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Scene3D", code: 1) }
    }

    private static func pixelBuffer(from image: UIImage, size: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        if let pool = pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        } else {
            CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &out)
        }
        guard let buf = out, let cg = image.cgImage else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        return buf
    }
}
