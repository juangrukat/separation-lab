import SwiftUI
import ImageIO

@main
struct SeparationLabApp: App {
    var body: some Scene { WindowGroup { InspectionView().preferredColorScheme(.dark) } }
}

final class InspectionModel: ObservableObject {
    @Published var image: UIImage?
    @Published var points: [CGPoint] = []
    @Published var reference = "10"
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var report: MeasurementReport?
    @Published var exportURL: URL?
    @Published var editingPoint: Int?
    @Published var manualMode = false
    @Published var cutoutMode = false
    @Published var analysisIssue: String?
    private(set) var photos: [Data] = []
    private let worker = DispatchQueue(label:"separation.analysis",qos:.userInitiated)
    private var processor: ImageProcessor?
    private var syntheticCapture=false
    var referenceValue: Double? { Double(reference.replacingOccurrences(of:",",with:".")) }
    var instruction: String {
        if let editingPoint { return "Tap the corrected position for \(["R1","R2","E1","E2"][editingPoint])" }
        if let report { return report.frames.first?.acceptedSections==0 ? "Review selected points · no edge verification":"Review fitted edges · tap E1 or E2 to correct" }
        switch points.count {
        case 0: return "Tap the centre of the first tape marking"
        case 1: return "Tap a second tape marking, well away from the first"
        case 2: return "Tap the first material boundary"
        case 3: return "Tap the opposite boundary across the space"
        default: return "Orange line crosses the opening · Check scale, then analyze"
        }
    }
    var selectedEstimate: Double? {
        guard points.count==4,let reference=referenceValue,reference>0,Measurement.distance(points[0],points[1])>=40 else { return nil }
        return Measurement.distance(points[2],points[3])*reference/Measurement.distance(points[0],points[1])
    }
    var displayPoints:[CGPoint] {
        guard let edges=report?.frames.first?.refinedEdges,edges.count==2 else { return points }
        return Array(points.prefix(2))+edges.map { CGPoint(x:$0[0],y:$0[1]) }
    }
    func placePoint(_ p:CGPoint) {
        if let i=editingPoint,i<points.count { points[i]=p;editingPoint=nil }
        else if points.count<4 { points.append(p) }
        else { return }
        report=nil;analysisIssue=nil;exportURL=nil
        UISelectionFeedbackGenerator().selectionChanged()
    }
    func edit(_ index:Int) { report=nil;editingPoint = editingPoint==index ? nil:index;analysisIssue=nil;exportURL=nil }
    func saveDiagnosticSelection() {
        guard !syntheticCapture else { return }
        let selection:[String:Any] = ["points":points.map { [$0.x,$0.y] },"referenceMM":referenceValue ?? 0,"mode":manualMode ? "manual":cutoutMode ? "cutout":"assisted"]
        if let data=try? JSONSerialization.data(withJSONObject:selection,options:.prettyPrinted) {
            let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LatestCapture")
            try? data.write(to:folder.appendingPathComponent("selection.json"),options:.atomic)
        }
    }
    func receive(_ photos:[Data],persist:Bool=true,onReady:(()->Void)?=nil) {
        self.photos = photos;points = [];report = nil;exportURL = nil;error = nil;busy = true;editingPoint=nil;analysisIssue=nil
        syntheticCapture = !persist && (ProcessInfo.processInfo.arguments.contains("--ui-fixture") || ProcessInfo.processInfo.arguments.contains("--replay-inspection"))
        worker.async {
            do {
                let processor = self.processor ?? ImageProcessor();self.processor = processor
                let cg = try processor.decode(photos[0])
                if persist {
                    let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LatestCapture")
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    for (i,data) in photos.enumerated() { try data.write(to:folder.appendingPathComponent("original-\(i+1).jpg"),options:.atomic) }
                    try? FileManager.default.removeItem(at:folder.appendingPathComponent("selection.json"))
                }
                DispatchQueue.main.async { self.image = UIImage(cgImage:cg);self.busy = false;onReady?() }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription;self.busy = false } }
        }
    }
    func loadInspectionReplay() {
        do {
            let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("ReplayInspection")
            let photos=try (1...3).map { try Data(contentsOf:folder.appendingPathComponent("original-\($0).jpg")) }
            let selection=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("selection.json"))) as? [String:Any]
            guard let coordinates=selection?["points"] as? [[Double]],coordinates.count==4,coordinates.allSatisfy({$0.count==2 && $0.allSatisfy(\.isFinite)}),let reference=selection?["referenceMM"] as? Double,reference.isFinite,reference>0 else { throw MeasureError.invalid("Replay selection is invalid.") }
            receive(photos,persist:false) {
                self.points=coordinates.map { CGPoint(x:$0[0],y:$0[1]) }
                self.reference=String(reference);self.cutoutMode=true;self.analyze()
            }
        } catch { self.error=error.localizedDescription }
    }
    func restoreLatestCapture()->Bool {
        let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LatestCapture")
        let photos=(1...3).compactMap { try? Data(contentsOf:folder.appendingPathComponent("original-\($0).jpg")) }
        guard photos.count==3 else { return false }
        receive(photos,persist:false)
        return true
    }
    func loadUIFixture() {
        // Only invoked by an explicit developer launch argument; never a camera result.
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:600,height:900),format:format)
        let image=renderer.image { context in
            UIColor(white:0.75,alpha:1).setFill();context.fill(CGRect(x:0,y:0,width:600,height:900))
            UIColor(white:0.08,alpha:1).setFill();context.fill(CGRect(x:280,y:220,width:20,height:500))
            UIColor.systemYellow.setFill();context.fill(CGRect(x:40,y:100,width:520,height:60))
            UIColor.black.setStroke()
            for x in stride(from:60,through:540,by:20) {
                let p=UIBezierPath();p.move(to:CGPoint(x:x,y:100));p.addLine(to:CGPoint(x:x,y:135));p.lineWidth=2;p.stroke()
            }
            ("SYNTHETIC UI CHECK — NOT A MEASUREMENT" as NSString).draw(at:CGPoint(x:35,y:800),withAttributes:[.font:UIFont.systemFont(ofSize:17),.foregroundColor:UIColor.black])
        }
        guard let data=image.jpegData(compressionQuality:1) else { return }
        receive([data,data,data],persist:false)
        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) {
            self.reference="20"
            self.points=[CGPoint(x:60,y:120),CGPoint(x:260,y:120),CGPoint(x:280,y:450),CGPoint(x:300,y:450)]
            if ProcessInfo.processInfo.arguments.contains("--keyboard-check") {
                DispatchQueue.main.asyncAfter(deadline:.now()+2) {
                    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).forEach { window in
                        func focus(_ view:UIView) {
                            if let field=view as? UITextField { field.becomeFirstResponder();return }
                            view.subviews.forEach(focus)
                        }
                        focus(window)
                    }
                }
            } else { self.analyze() }
        }
    }
    func reset() { image = nil;points = [];report = nil;photos = [];error = nil;exportURL = nil;editingPoint=nil;analysisIssue=nil }
    func analyze() {
        guard let reference = referenceValue,reference.isFinite,reference > 0,reference <= 10000,points.count == 4 else {
            error = "Enter a positive reference distance in millimetres.";return
        }
        saveDiagnosticSelection()
        busy = true;error = nil;report = nil;exportURL = nil;analysisIssue=nil;status = "Preparing original-resolution images…"
        let photos = self.photos,points = self.points,manual=self.manualMode,cutout=self.cutoutMode
        worker.async {
            do {
                let processor = self.processor ?? ImageProcessor();self.processor = processor
                let first = try processor.gray(processor.decode(photos[0]))
                let thumbnail = first.thumbnail()
                func measure(_ image:GrayImage,_ selected:[CGPoint]) throws -> FrameMeasurement {
                    if manual { return try Measurement.manual(points:selected,referenceMM:reference) }
                    if cutout { return try Measurement.cutout(image,points:selected,referenceMM:reference) }
                    return try Measurement.measure(image,points:selected,referenceMM:reference)
                }
                var frames = [try measure(first,points)]
                var rejected: [String] = []
                for i in 1..<photos.count {
                    if manual { continue }
                    DispatchQueue.main.async { self.status = "Checking photograph \(i+1) of \(photos.count)…" }
                    do {
                        let result: FrameMeasurement = try autoreleasepool {
                            let gray = try processor.gray(processor.decode(photos[i]))
                            let next = gray.thumbnail()
                            guard gray.width == first.width,gray.height == first.height,next.1 == thumbnail.1 else { throw MeasureError.invalid("Image dimensions differ.") }
                            let shift=try ImageRegistration.shift(reference:thumbnail.0,target:next.0)
                            let tracked = try Measurement.track(reference:thumbnail.0,target:next.0,points:points,step:thumbnail.1,globalShift:shift)
                            let refined = Measurement.refineTracking(reference:first,target:gray,original:points,tracked:tracked,radius:Int(thumbnail.1)+2)
                            return try measure(gray,refined)
                        }
                        frames.append(result)
                    } catch { rejected.append("Photo \(i+1): \(error.localizedDescription)") }
                }
                let report = MeasurementReport(created:Date(),referenceMM:reference,points:points.map { [Double($0.x),Double($0.y)] },frames:frames,rejectedFrames:rejected,
                    processing:processor.backend + (manual ? " · manual selection":" · Vision registration"),imageWidth:first.width,imageHeight:first.height,
                    limitations:"Experimental visible in-plane separation. Scalar reference calibration; no perspective/lens correction. Coplanar tape and feature required. Frame range is consistency, not accuracy or uncertainty. Local sections may include real surface roughness. Not validated for tolerance decisions. Height/offset not measured.")
                DispatchQueue.main.async { self.report = report;self.busy = false }
            } catch { DispatchQueue.main.async { self.analysisIssue = error.localizedDescription;self.busy = false } }
        }
    }
    func export() {
        guard !photos.isEmpty else { return }
        saveDiagnosticSelection()
        busy = true
        let photos = self.photos,report=self.report,issue=analysisIssue
        worker.async {
            do {
                let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                let folder = root.appendingPathComponent("Inspection-\(Int(Date().timeIntervalSince1970))")
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
                if let report { try encoder.encode(report).write(to:folder.appendingPathComponent("measurement.json"),options:.atomic) }
                let selection=root.appendingPathComponent("LatestCapture/selection.json")
                if let data=try? Data(contentsOf:selection) { try data.write(to:folder.appendingPathComponent("selection.json"),options:.atomic) }
                for (i,photo) in photos.enumerated() { try photo.write(to:folder.appendingPathComponent("original-\(i+1).jpg"),options:.atomic) }
                let text: String
                if let report {
                    text = "Separation Lab — EXPERIMENTAL\nMethod: \(report.frames.first?.method ?? "Unknown")\nEstimate: \(String(format:"%.3f",report.mean)) mm\nAccepted photos: \(report.frames.count)/\(photos.count)\nBetween-photo range: \(String(format:"%.3f",report.range)) mm\n\n\(report.limitations)\n\n\(report.rejectedFrames.joined(separator:"\n"))"
                } else { text="Separation Lab — unresolved capture\n\(issue ?? "Not yet analyzed")\nOriginal photos and selection included for diagnosis. No verified measurement." }
                try text.write(to:folder.appendingPathComponent("Read me.txt"),atomically:true,encoding:.utf8)
                DispatchQueue.main.async { self.exportURL = folder;self.busy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription;self.busy = false } }
        }
    }
}

struct InspectionView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var model = InspectionModel()
    @State private var help = false
    @State private var showShare = false
    @State private var photoReset=0
    @Environment(\.scenePhase) private var scenePhase
    private let teal = Color(red:0.32,green:0.89,blue:0.78)
    var body: some View {
        VStack(spacing:0) {
            HStack {
                VStack(alignment:.leading,spacing:3) {
                    Text("SEPARATION LAB").font(.system(size:13,weight:.semibold,design:.monospaced)).tracking(2)
                    Text(model.image == nil ? "Capture inspection" : "Measure separation").font(.title2.bold())
                }
                Spacer()
                Button { help = true } label: { Image(systemName:"questionmark.circle").font(.title2).frame(width:44,height:44) }.accessibilityLabel("Capture instructions")
            }.padding(.horizontal,20).padding(.vertical,12)
            HStack(spacing:8) {
                Image(systemName:"flask");Text("EXPERIMENTAL · IN-PLANE SEPARATION").font(.system(size:10,weight:.semibold,design:.monospaced));Spacer()
            }.foregroundStyle(teal).padding(.horizontal,20).padding(.bottom,12)
            if let image = model.image { review(image) } else { capture }
        }
        .background(Color(red:0.035,green:0.055,blue:0.07))
        .tint(teal)
        .onAppear {
            camera.onCapture = { photos in camera.stop();model.receive(photos) }
            if let saved=UserDefaults.standard.string(forKey:"referenceMM") { model.reference=saved }
            if ProcessInfo.processInfo.arguments.contains("--ui-fixture") { model.loadUIFixture() }
            else if ProcessInfo.processInfo.arguments.contains("--replay-inspection") { model.loadInspectionReplay() }
            else if ProcessInfo.processInfo.arguments.contains("--restore-latest"),model.restoreLatestCapture() { }
            else { camera.start() }
        }
        .onChange(of:scenePhase) { _,phase in
            if phase == .active,model.image == nil,!model.busy { camera.start() }
            else if phase == .background { camera.stop() }
        }
        .onChange(of:model.exportURL) { _,url in if url != nil { showShare = true } }
        .onChange(of:model.manualMode) { _,_ in model.report=nil;model.analysisIssue=nil;model.exportURL=nil }
        .onChange(of:model.cutoutMode) { _,_ in model.report=nil;model.analysisIssue=nil;model.exportURL=nil }
        .onChange(of:model.reference) { _,value in
            if !ProcessInfo.processInfo.arguments.contains("--ui-fixture") { UserDefaults.standard.set(value,forKey:"referenceMM") }
        }
        .sheet(isPresented:$showShare) { if let url = model.exportURL { ShareSheet(items:[url]) } }
        .sheet(isPresented:$help) { helpView }
        .alert("Inspection needs attention",isPresented:Binding(get:{model.error != nil || camera.error != nil},set:{if !$0 { model.error = nil;camera.error = nil }})) {
            Button("OK",role:.cancel) { model.error = nil;camera.error = nil }
        } message: { Text(model.error ?? camera.error ?? "") }
        .overlay { if model.busy { ZStack { Color.black.opacity(0.75).ignoresSafeArea();VStack(spacing:16) { ProgressView();Text(model.status.isEmpty ? "Preparing photograph…" : model.status).font(.callout) }.padding(25) } } }
    }
    private var capture: some View {
        VStack(spacing:14) {
            ZStack {
                CameraPreview(session:camera.session)
                if camera.permissionDenied {
                    VStack(spacing:15) { Image(systemName:"camera.fill").font(.largeTitle);Text("Camera access is required").font(.headline)
                        Button("Open Settings") { if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }.padding().background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:16))
                } else {
                    RoundedRectangle(cornerRadius:8).stroke(teal.opacity(0.7),style:StrokeStyle(lineWidth:1,dash:[12,6])).padding(.horizontal,38).padding(.vertical,60).allowsHitTesting(false)
                    VStack { Spacer();Text("TAPE + BOTH BOUNDARIES").font(.system(size:10,weight:.semibold,design:.monospaced)).padding(8).background(.black.opacity(0.65),in:Capsule()).padding(.bottom,15) }.allowsHitTesting(false)
                }
            }.frame(maxHeight:.infinity).background(.black).clipShape(RoundedRectangle(cornerRadius:16)).padding(.horizontal,16)
            VStack(alignment:.leading,spacing:10) {
                Label(camera.guidance,systemImage:camera.stable && !camera.focusing ? "checkmark.circle" : "viewfinder").font(.callout).foregroundStyle(camera.stable ? teal : .white)
                Text(camera.minimumFocus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("High detail",isOn:$camera.highDetail).font(.callout)
                    Spacer(minLength:24)
                    Toggle("Light",isOn:$camera.torch).font(.callout).onChange(of:camera.torch) { _,v in camera.setTorch(v) }
                }.disabled(camera.capturing)
                Button { camera.capture() } label: {
                    HStack { Image(systemName:"camera.aperture");Text(camera.capturing ? "Hold steady · \(camera.captureProgress)/3" : "Capture 3 photographs").fontWeight(.semibold) }.frame(maxWidth:.infinity).frame(height:54)
                }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!camera.ready || camera.capturing)
                Text("Use a supported phone and diffuse light. Tape and feature must share the same plane.").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal,20).padding(.bottom,12)
        }
    }
    private func review(_ image:UIImage) -> some View {
        VStack(spacing:10) {
            HStack { Text("\(min(model.points.count+1,4)) / 4").font(.system(.caption,design:.monospaced)).foregroundStyle(teal)
                Text(model.instruction).font(.callout.weight(.medium));Spacer()
            }.padding(.horizontal,20)
            PointPicker(image:image,points:model.displayPoints,resetToken:photoReset) { p in
                hideKeyboard();model.placePoint(p)
            }.frame(minHeight:140,maxHeight:.infinity).clipShape(RoundedRectangle(cornerRadius:14)).padding(.horizontal,16)
            HStack {
                Text("Pinch to zoom · Drag to pan").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Fit photo",systemImage:"arrow.down.right.and.arrow.up.left") { hideKeyboard();photoReset += 1 }.font(.caption).frame(minHeight:32)
            }.padding(.horizontal,20)
            VStack(spacing:10) {
                HStack(spacing:8) {
                    ForEach(0..<model.points.count,id:\.self) { i in
                        Button { model.edit(i) } label: {
                            HStack(spacing:4) {
                                if i>=2,let crop=edgeCrop(image,at:model.displayPoints[i]) {
                                    Image(uiImage:crop).resizable().interpolation(.none).scaledToFill().frame(width:36,height:36).clipped()
                                        .overlay { Image(systemName:"plus").font(.caption).foregroundStyle(.orange) }
                                }
                                Text(["R1","R2","E1","E2"][i]).font(.system(size:12,weight:.bold,design:.monospaced))
                                Image(systemName:"pencil").font(.system(size:10))
                            }.frame(maxWidth:.infinity,minHeight:42)
                                .background(model.editingPoint==i ? Color.white.opacity(0.18):Color.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                        }.tint(i<2 ? teal:.orange).accessibilityLabel("Reposition \(["reference one","reference two","edge one","edge two"][i])")
                    }
                }
                if let issue=model.analysisIssue {
                    Text(issue).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading)
                }
                if let report = model.report {
                    result(report).fixedSize(horizontal:false,vertical:true)
                } else {
                    Picker("Measurement method",selection:$model.manualMode) {
                        Text("Assisted edges").tag(false)
                        Text("Point-to-point").tag(true)
                    }.pickerStyle(.segmented)
                    if !model.manualMode {
                        Toggle("Full cutout · ignore interior tab",isOn:$model.cutoutMode).font(.caption)
                    }
                    if model.manualMode {
                        Text("Manual selection only. Boundaries will not be automatically verified.").font(.caption2).foregroundStyle(.orange)
                    }
                    HStack {
                        Text("Reference distance").font(.callout)
                        Spacer()
                        ReferenceField(text:$model.reference) { photoReset += 1 }
                            .frame(width:90,height:30).padding(9).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                        Text("mm").foregroundStyle(.secondary)
                    }
                    if let estimate=model.selectedEstimate {
                        Text("Selected span: about \(estimate,specifier:"%.2f") mm · before edge refinement").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button { hideKeyboard();model.analyze() } label: { Text(model.points.count<4 ? "Select \(4-model.points.count) more points on the photo" : model.manualMode ? "Measure selected points":"Refine and measure edges").fontWeight(.semibold).frame(maxWidth:.infinity).frame(height:48) }
                        .buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.points.count != 4 || model.editingPoint != nil)
                }
                HStack {
                    Button("Recapture",systemImage:"camera.rotate") { model.reset();camera.start() }
                    Spacer()
                    if model.report != nil {
                        Button("Edit edges",systemImage:"pencil") { model.edit(2) }
                        Spacer()
                        Button("Save",systemImage:"square.and.arrow.up") { model.export() }
                    } else {
                        Button("Undo",systemImage:"arrow.uturn.backward") { if !model.points.isEmpty { model.points.removeLast();model.editingPoint=nil;model.analysisIssue=nil } }.disabled(model.points.isEmpty)
                        Button("Save",systemImage:"square.and.arrow.up") { model.export() }
                    }
                }.font(.callout).frame(minHeight:44)
            }.padding(.horizontal,20).padding(.bottom,8)
        }
    }
    private func result(_ r:MeasurementReport) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(alignment:.firstTextBaseline) {
                Text(r.mean,format:.number.precision(.fractionLength(2))).font(.system(size:37,weight:.semibold,design:.rounded)).monospacedDigit()
                Text("mm").foregroundStyle(.secondary);Spacer()
                Text("ESTIMATE").font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(teal)
            }
            Text(r.frames[0].acceptedSections==0 ? "Photo 1 · manually selected points · \(r.imageWidth) × \(r.imageHeight)":"\(r.frames.count)/3 photos accepted · \(r.imageWidth) × \(r.imageHeight)").font(.caption)
            Text(r.frames[0].method).font(.caption).foregroundStyle(r.frames[0].acceptedSections==0 ? .orange:teal)
            if r.frames.count > 1 { Text("Between-photo range: \(r.range, specifier:"%.3f") mm").font(.caption) }
            else { Text(r.frames[0].acceptedSections==0 ? "Manual estimate · edge fit and repeatability not checked":"Single photo only: frame consistency unavailable").font(.caption).foregroundStyle(.orange) }
            Text("\(r.frames[0].mmPerPixel,specifier:"%.4f") mm/px · \(r.frames[0].pixelWidth,specifier:"%.2f") px across space").font(.caption).foregroundStyle(.secondary)
            if r.frames[0].acceptedSections>0 {
                Text("Nearby-section range: \(r.frames[0].sectionSpreadMM,specifier:"%.2f") mm").font(.caption)
                    .foregroundStyle(r.frames[0].sectionSpreadMM>max(0.05,r.mean*0.03) ? Color.orange:Color.secondary)
            }
            Text(r.processing).font(.caption2).foregroundStyle(.secondary)
            Text("Displayed digits are not verified accuracy. Tape calibration and frame agreement cannot certify small openings.").font(.caption2).foregroundStyle(.orange)
            if !r.rejectedFrames.isEmpty { Text(r.rejectedFrames[0]).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(13).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func edgeCrop(_ image:UIImage,at p:CGPoint) -> UIImage? {
        guard let cg=image.cgImage else { return nil }
        let rect=CGRect(x:p.x-40,y:p.y-40,width:80,height:80).intersection(CGRect(x:0,y:0,width:cg.width,height:cg.height))
        guard let crop=cg.cropping(to:rect) else { return nil }
        return UIImage(cgImage:crop)
    }
    private var helpView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("Start with a visible opening").font(.title2.bold())
                    Text("Place the tape next to the feature, with the markings and both edges in the same plane. Face the surface straight on. Keep the feature near the image centre.")
                    Text("Support the phone").font(.headline)
                    Text("Use a stand or brace your hands. Capture records three separate photographs; hold still until it finishes. Improve diffuse lighting before turning on the phone light, which may create reflections.")
                    Text("Select four points").font(.headline)
                    Text("Pinch to zoom. Tap the centres of two tape markings and enter the actual distance between them in millimetres. Then tap the two physical boundaries across the space, perpendicular to the edges. Undo lets you correct a point.")
                    Text("Read the result carefully").font(.headline)
                    Text("This prototype refines boundaries between pixels and compares nearby sections and repeated photos. It does not measure hidden spaces or surface height offsets. A tape establishes approximate scale, not submillimetre accuracy. Validate with finer reference openings before using results for acceptance decisions.")
                    Text("High detail uses the largest supported main-camera photo size. It is slower. Neural models and LiDAR depth measurement are not part of this experiment.").font(.callout).foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("Capture guide").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { help = false } } }
        }
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) }
}

struct ShareSheet:UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context) {}
}
