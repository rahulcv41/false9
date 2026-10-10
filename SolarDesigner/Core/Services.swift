import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import SwiftUI

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request() {
        mgr.requestWhenInUseAuthorization()
        mgr.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { self.location = locations.last }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

/// Where the phone's rear camera is pointing: true-north azimuth and elevation above the horizon.
final class AimService: ObservableObject {
    @Published var azimuth = 0.0
    @Published var elevation = 0.0
    @Published var available = true
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { available = false; return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] m, _ in
            guard let self = self, let m = m else { return }
            let r = m.attitude.rotationMatrix
            // rear camera direction in the reference frame (x = north, y = west, z = up)
            let dx = -r.m31, dy = -r.m32, dz = -r.m33
            self.elevation = asin(max(-1, min(1, dz))) * 180 / .pi
            var az = atan2(-dy, dx) * 180 / .pi
            if az < 0 { az += 360 }
            self.azimuth = az
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
