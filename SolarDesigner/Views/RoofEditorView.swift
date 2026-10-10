import SwiftUI

/// Step 2 — calibrate scale, draw roof boundary, place obstacles (tank, stair room, …).
struct RoofEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case outline = "Outline", obstacles = "Obstacles", scale = "Scale"
        var id: String { rawValue }
    }

    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var mode: Mode = .outline
    @State private var image: UIImage?
    @State private var selected: UUID?
    @State private var scalePts: [Pt] = []
    @State private var askDistance = false
    @State private var distanceText = ""
    @State private var dragIndex: Int?
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(8)

            GeometryReader { geo in
                let fit = fitTransform(geo.size)
                ZStack {
                    Color.black
                    if let img = image {
                        Image(uiImage: img).resizable().frame(width: fit.size.width, height: fit.size.height)
                            .position(x: fit.origin.x + fit.size.width / 2, y: fit.origin.y + fit.size.height / 2)
                    } else {
                        Text("Capture or import a roof image in step 1").foregroundStyle(.white)
                    }
                    Canvas { ctx, _ in
                        func v(_ p: Pt) -> CGPoint { CGPoint(x: fit.origin.x + p.x * fit.scale, y: fit.origin.y + p.y * fit.scale) }
                        var path = Path()
                        for (i, p) in project.roofPolygon.enumerated() { i == 0 ? path.move(to: v(p)) : path.addLine(to: v(p)) }
                        if project.roofPolygon.count >= 3 { path.closeSubpath() }
                        ctx.fill(path, with: .color(.orange.opacity(0.25)))
                        ctx.stroke(path, with: .color(.orange), lineWidth: 2.5)
                        for p in project.roofPolygon {
                            ctx.fill(Path(ellipseIn: CGRect(x: v(p).x - 6, y: v(p).y - 6, width: 12, height: 12)), with: .color(.white))
                            ctx.stroke(Path(ellipseIn: CGRect(x: v(p).x - 6, y: v(p).y - 6, width: 12, height: 12)), with: .color(.orange), lineWidth: 2)
                        }
                        for o in project.obstacles {
                            let pts = obstacleCornersPx(o).map(v)
                            var op = Path(); op.addLines(pts); op.closeSubpath()
                            ctx.fill(op, with: .color(.red.opacity(o.id == selected ? 0.55 : 0.35)))
                            ctx.stroke(op, with: .color(.red), lineWidth: o.id == selected ? 3 : 1.5)
                        }
                        if !scalePts.isEmpty {
                            var sp = Path()
                            for (i, p) in scalePts.enumerated() { i == 0 ? sp.move(to: v(p)) : sp.addLine(to: v(p)) }
                            ctx.stroke(sp, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                            for p in scalePts { ctx.fill(Path(ellipseIn: CGRect(x: v(p).x - 6, y: v(p).y - 6, width: 12, height: 12)), with: .color(.cyan)) }
                        }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil {
                            dragStart = g.startLocation
                            if mode == .outline {
                                dragIndex = nearestVertex(to: g.startLocation, fit: fit)
                            }
                        }
                        if let i = dragIndex { project.roofPolygon[i] = toPixel(g.location, fit) }
                    }
                    .onEnded { g in
                        defer { dragIndex = nil; dragStart = nil }
                        guard image != nil, dragIndex == nil, hypot(g.translation.width, g.translation.height) < 8 else { return }
                        tap(toPixel(g.location, fit))
                    })
            }
            .frame(minHeight: 280)

            controls
        }
        .navigationTitle("Roof outline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { image = store.image(for: project) }
        .alert("Real distance between the two points", isPresented: $askDistance) {
            TextField("metres", text: $distanceText).keyboardType(.decimalPad)
            Button("Set scale") { applyScale() }
            Button("Cancel", role: .cancel) { scalePts = [] }
        } message: { Text("Measure a known length on site (e.g. a roof edge) and enter it in metres.") }
    }

    // MARK: controls

    @ViewBuilder private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(project.isCalibrated ? String(format: "Scale %.3f m/px", project.metersPerPixel) : "⚠︎ Scale not set")
                        .foregroundStyle(project.isCalibrated ? Color.secondary : Color.red)
                    Spacer()
                    if project.isCalibrated && project.roofPolygon.count >= 3 {
                        Text(String(format: "Roof area %.0f m²", project.roofAreaM2)).bold()
                    }
                }.font(.footnote)

                switch mode {
                case .outline:
                    Text("Tap the roof corners in order. Drag a corner to adjust.").font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button("Undo point") { _ = project.roofPolygon.popLast() }.disabled(project.roofPolygon.isEmpty)
                        Button("Clear", role: .destructive) { project.roofPolygon = [] }.disabled(project.roofPolygon.isEmpty)
                    }.buttonStyle(.bordered)
                case .scale:
                    Text("Tap two points a known distance apart (e.g. a roof edge you can measure on site).").font(.footnote).foregroundStyle(.secondary)
                    Button("Reset points") { scalePts = [] }.buttonStyle(.bordered)
                case .obstacles:
                    Text("Tap to place a rooftop obstacle; tap an existing one to edit it.").font(.footnote).foregroundStyle(.secondary)
                    if let idx = project.obstacles.firstIndex(where: { $0.id == selected }) {
                        let o = $project.obstacles[idx]
                        Picker("Type", selection: o.kind) { ForEach(ObstacleKind.allCases) { Text($0.rawValue).tag($0) } }
                        Stepper(String(format: "Width %.1f m", project.obstacles[idx].width), value: o.width, in: 0.2...20, step: 0.1)
                        Stepper(String(format: "Depth %.1f m", project.obstacles[idx].depth), value: o.depth, in: 0.2...20, step: 0.1)
                        Stepper(String(format: "Height %.1f m", project.obstacles[idx].height), value: o.height, in: 0.1...15, step: 0.1)
                        Stepper(String(format: "Rotate %.0f°", project.obstacles[idx].rotationDeg), value: o.rotationDeg, in: -90...90, step: 5)
                        Button("Delete obstacle", role: .destructive) {
                            project.obstacles.remove(at: idx); selected = nil
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 260)
        .background(.bar)
    }

    // MARK: geometry helpers

    private struct Fit { var origin: CGPoint; var size: CGSize; var scale: CGFloat }

    private func fitTransform(_ area: CGSize) -> Fit {
        guard project.imageWidth > 0, project.imageHeight > 0 else { return Fit(origin: .zero, size: .zero, scale: 1) }
        let s = min(area.width / project.imageWidth, area.height / project.imageHeight)
        let sz = CGSize(width: project.imageWidth * s, height: project.imageHeight * s)
        return Fit(origin: CGPoint(x: (area.width - sz.width) / 2, y: (area.height - sz.height) / 2), size: sz, scale: s)
    }

    private func toPixel(_ p: CGPoint, _ fit: Fit) -> Pt {
        Pt(max(0, min(project.imageWidth, (p.x - fit.origin.x) / fit.scale)),
           max(0, min(project.imageHeight, (p.y - fit.origin.y) / fit.scale)))
    }

    private func nearestVertex(to p: CGPoint, fit: Fit) -> Int? {
        var best: (Int, CGFloat)?
        for (i, q) in project.roofPolygon.enumerated() {
            let d = hypot(fit.origin.x + q.x * fit.scale - p.x, fit.origin.y + q.y * fit.scale - p.y)
            if d < 28, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func obstacleCornersPx(_ o: RoofObstacle) -> [Pt] {
        guard project.isCalibrated else { return [] }
        let hw = o.width / 2 / project.metersPerPixel, hd = o.depth / 2 / project.metersPerPixel
        let r = o.rotationDeg * .pi / 180
        // local (x east, yw north) → pixel: pixel y points down; rotation is CCW in world space
        return [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, yw) in
            Pt(o.centerPx.x + x * cos(r) - yw * sin(r), o.centerPx.y - (x * sin(r) + yw * cos(r)))
        }
    }

    private func tap(_ p: Pt) {
        switch mode {
        case .outline:
            project.roofPolygon.append(p)
        case .scale:
            scalePts.append(p)
            if scalePts.count == 2 { distanceText = ""; askDistance = true }
        case .obstacles:
            guard project.isCalibrated else { return }
            if let hit = project.obstacles.first(where: { Geo.contains(obstacleCornersPx($0), p) }) {
                selected = hit.id
            } else {
                let o = RoofObstacle(centerPx: p)
                project.obstacles.append(o)
                selected = o.id
            }
        }
    }

    private func applyScale() {
        defer { scalePts = [] }
        guard scalePts.count == 2, let d = Double(distanceText.replacingOccurrences(of: ",", with: ".")), d > 0 else { return }
        let px = hypot(scalePts[1].x - scalePts[0].x, scalePts[1].y - scalePts[0].y)
        guard px > 0 else { return }
        project.metersPerPixel = d / px
    }
}
