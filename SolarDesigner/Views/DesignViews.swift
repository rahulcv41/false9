import SwiftUI
import Charts

// MARK: - Settings

struct SystemSettingsView: View {
    @Binding var project: Project

    var body: some View {
        Form {
            Section("Array geometry") {
                Picker("Roof type", selection: $project.roofType) {
                    ForEach(RoofType.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper(String(format: project.roofType == .flat ? "Tilt %.0f°" : "Roof pitch %.0f°", project.tiltDeg), value: $project.tiltDeg, in: 0...45, step: 1)
                Stepper(String(format: "Panels face %.0f° (180 = south)", project.azimuthDeg), value: $project.azimuthDeg, in: 0...359, step: 5)
                Picker("Panel orientation", selection: $project.orientation) {
                    ForEach(PanelOrientation.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper(String(format: "Edge setback %.2f m", project.setbackM), value: $project.setbackM, in: 0...3, step: 0.1)
                Stepper(String(format: "Obstacle clearance %.1f m", project.obstacleClearanceM), value: $project.obstacleClearanceM, in: 0...2, step: 0.1)
                Stepper(String(format: "Building height %.0f m (3D)", project.buildingHeight), value: $project.buildingHeight, in: 3...60, step: 1)
            }
            Section("PV module") {
                Picker("Preset", selection: Binding(get: { project.panel.name }, set: { n in
                    if let s = PanelSpec.presets.first(where: { $0.name == n }) { project.panel = s }
                })) {
                    ForEach(PanelSpec.presets, id: \.name) { Text($0.name).tag($0.name) }
                    if !PanelSpec.presets.contains(where: { $0.name == project.panel.name }) { Text(project.panel.name).tag(project.panel.name) }
                }
                NumberRow("Power (Wp)", $project.panel.watt)
                NumberRow("Length (m)", $project.panel.lengthM)
                NumberRow("Width (m)", $project.panel.widthM)
                NumberRow("Vmp (V)", $project.panel.vmp)
                NumberRow("Voc (V)", $project.panel.voc)
                NumberRow("Isc (A)", $project.panel.isc)
                NumberRow("Voc temp coeff (%/°C)", $project.panel.tempCoeffVocPct)
            }
            Section("Inverter") {
                Picker("Preset", selection: Binding(get: { project.inverter.name }, set: { n in
                    if let s = InverterSpec.presets.first(where: { $0.name == n }) { project.inverter = s }
                })) {
                    ForEach(InverterSpec.presets, id: \.name) { Text($0.name).tag($0.name) }
                    if !InverterSpec.presets.contains(where: { $0.name == project.inverter.name }) { Text(project.inverter.name).tag(project.inverter.name) }
                }
                NumberRow("AC power (kW)", $project.inverter.acKW)
                NumberRow("Max DC voltage (V)", $project.inverter.maxDCV)
                NumberRow("MPPT min (V)", $project.inverter.mpptMin)
                NumberRow("MPPT max (V)", $project.inverter.mpptMax)
                Stepper("MPPT inputs: \(project.inverter.mpptCount)", value: $project.inverter.mpptCount, in: 1...12)
                Stepper("Strings per MPPT: \(project.inverter.stringsPerMPPT)", value: $project.inverter.stringsPerMPPT, in: 1...4)
                NumberRow("Max current / MPPT (A)", $project.inverter.maxCurrentPerMPPT)
                Toggle("Three-phase", isOn: $project.inverter.threePhase)
            }
            Section("Yield & economics") {
                NumberRow("Clearness factor", $project.clearnessFactor)
                NumberRow("Performance ratio", $project.performanceRatio)
                TextField("Currency symbol", text: $project.currency)
                NumberRow("Tariff per kWh", $project.tariffPerKWh)
                NumberRow("Cost per kWp", $project.costPerKWp)
                NumberRow("Grid CO₂ (kg/kWh)", $project.gridEmissionFactor)
                Text("Clearness factor = actual ÷ clear-sky irradiation for your site (≈0.65–0.80). Use local data for best accuracy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Equipment & settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Double
    init(_ title: String, _ value: Binding<Double>) { self.title = title; self._value = value }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: $value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
    }
}

// MARK: - 2D layout

struct LayoutView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var bundle: DesignBundle?
    @State private var plan: UIImage?
    @State private var showImage = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let plan = plan {
                    Image(uiImage: plan).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                }
                Toggle("Show satellite image", isOn: $showImage).onChange(of: showImage) { _, _ in redraw() }
                if let b = bundle {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow { Text("Modules"); Text("\(b.design.panelCount) × \(Int(project.panel.watt)) Wp").bold() }
                        GridRow { Text("Capacity"); Text(String(format: "%.2f kWp", b.design.dcKWp)).bold() }
                        GridRow { Text("Strings"); Text("\(b.design.stringCount) × \(b.design.panelsPerString)").bold() }
                        GridRow { Text("Inverters"); Text("\(b.design.inverterCount) × \(project.inverter.name)").bold() }
                        GridRow { Text("Row pitch"); Text(String(format: "%.2f m", b.layout.rowPitch)).bold() }
                    }.font(.subheadline)
                    ForEach(b.design.warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                    }
                }
                if project.roofPolygon.count < 3 || !project.isCalibrated {
                    Label("Calibrate scale and outline the roof in step 2 first.", systemImage: "info.circle").foregroundStyle(.secondary)
                }
                Button { refresh() } label: { Label("Regenerate layout", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Text("Panels are packed to the roof boundary with the set-back, avoid obstacles (with clearance), and row spacing is sized so rows don't shade each other at noon on the winter solstice.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle("2D layout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        let b = DesignBundle.make(project: project, store: store)
        bundle = b
        redraw()
    }

    private func redraw() {
        guard let b = bundle else { return }
        plan = PlanRenderer.render(size: CGSize(width: 800, height: 700), project: project, layout: b.layout, shade: nil,
                                   image: b.roofImage, options: PlanOptions(showImage: showImage, showShade: false, showStrings: true, showDimensions: true))
    }
}

// MARK: - Shade analysis

struct ShadeView: View {
    @Binding var project: Project
    @EnvironmentObject var store: ProjectStore
    @State private var bundle: DesignBundle?
    @State private var plan: UIImage?
    @State private var running = false

    struct MonthPoint: Identifiable { let id = UUID(); let month: String; let series: String; let kWh: Double }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if running { ProgressView("Simulating sun path…") }
                if let b = bundle {
                    HStack(spacing: 10) {
                        StatCard(title: "Annual yield", value: String(format: "%.0f kWh", b.shade.annualKWh))
                        StatCard(title: "Shade loss", value: String(format: "%.1f %%", b.shade.annualShadeLossPct),
                                 tint: b.shade.annualShadeLossPct > 8 ? .red : (b.shade.annualShadeLossPct > 3 ? .orange : .green))
                        StatCard(title: "kWh/kWp", value: String(format: "%.0f", b.economics.specificYield))
                    }
                    Text("Monthly energy").font(.headline)
                    Chart(monthPoints(b.shade)) { p in
                        BarMark(x: .value("Month", p.month), y: .value("kWh", p.kWh))
                            .foregroundStyle(by: .value("Series", p.series))
                            .position(by: .value("Series", p.series))
                    }
                    .chartForegroundStyleScale(["Without shade": Color.gray.opacity(0.5), "With shade": Color.orange])
                    .frame(height: 200)

                    Text("Sun path & skyline").font(.headline)
                    SkylineChart(project: project).frame(height: 260)
                    Text("Orange = 21 Jun, yellow = 21 Mar/Sep, blue = 21 Dec. Red zone = surveyed obstructions.")
                        .font(.caption).foregroundStyle(.secondary)

                    Text("Shaded hours (share of panels in shade)").font(.headline)
                    ShadeHeatmap(grid: b.shade.shadeGrid)
                        .frame(height: 210)

                    Text("Shade by panel").font(.headline)
                    if let plan = plan { Image(uiImage: plan).resizable().aspectRatio(contentMode: .fit) }
                    HStack(spacing: 10) {
                        legend(.systemGreen, "<3 %"); legend(.systemYellow, "<10 %"); legend(.systemOrange, "<25 %"); legend(.systemRed, "≥25 %")
                    }.font(.caption)
                }
                Button { run() } label: { Label("Re-run analysis", systemImage: "sun.max").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                if project.horizon.isEmpty && project.obstacles.isEmpty {
                    Label("No obstacles recorded — result assumes a clear horizon.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding()
        }
        .navigationTitle("Shade analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { run() }
    }

    private func legend(_ c: UIColor, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color(c)).frame(width: 14, height: 10); Text(t) }
    }

    private func monthPoints(_ s: ShadeResult) -> [MonthPoint] {
        (0..<12).flatMap { m in
            [MonthPoint(month: Solar.monthNames[m], series: "Without shade", kWh: s.monthlyKWhNoShade[m]),
             MonthPoint(month: Solar.monthNames[m], series: "With shade", kWh: s.monthlyKWh[m])]
        }
    }

    private func run() {
        running = true
        let proj = project
        let img = store.image(for: proj)
        Task.detached(priority: .userInitiated) {
            var layout = LayoutEngine.generate(proj)
            let design = SystemDesign.make(project: proj, layout: &layout)
            let shade = ShadeAnalysis.run(proj, layout)
            let eco = Economics(project: proj, kWp: design.dcKWp, annualKWh: shade.annualKWh)
            let b = DesignBundle(project: proj, layout: layout, design: design, shade: shade, roofImage: img, economics: eco)
            let plan = PlanRenderer.render(size: CGSize(width: 800, height: 600), project: proj, layout: layout, shade: shade, image: nil,
                                           options: PlanOptions(showImage: false, showShade: true, showStrings: false, showDimensions: false))
            await MainActor.run { bundle = b; self.plan = plan; running = false }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var tint: Color = .orange
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ShadeHeatmap: View {
    let grid: [[Double]]   // [month][hour]

    var body: some View {
        Canvas { ctx, size in
            guard grid.count == 12 else { return }
            let left: CGFloat = 28, bottom: CGFloat = 16
            let cw = (size.width - left) / 24, ch = (size.height - bottom) / 12
            for m in 0..<12 {
                for h in 0..<24 {
                    let v = grid[m][h]
                    let rect = CGRect(x: left + CGFloat(h) * cw, y: CGFloat(m) * ch, width: cw, height: ch)
                    let color: Color = v < 0 ? Color.gray.opacity(0.15) : Color(red: min(1, 0.2 + v * 1.2), green: max(0, 0.75 - v * 0.9), blue: 0.2)
                    ctx.fill(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(color))
                }
                ctx.draw(Text(Solar.monthNames[m]).font(.system(size: 8)), at: CGPoint(x: 13, y: CGFloat(m) * ch + ch / 2))
            }
            for h in stride(from: 0, to: 24, by: 3) {
                ctx.draw(Text("\(h)").font(.system(size: 8)), at: CGPoint(x: left + CGFloat(h) * cw + cw / 2, y: size.height - 7))
            }
        }
    }
}
