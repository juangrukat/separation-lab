import SwiftUI
import AVFoundation
import CoreMotion

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label:"separation.camera",qos:.userInitiated)
    private let videoQueue = DispatchQueue(label:"separation.preview",qos:.utility)
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private var camera: AVCaptureDevice?
    private var configured = false
    private var photos: [Data] = []
    private var expectedPhotos = 3
    private var captureHighDetail = false
    private var frameNumber = 0
    private let motion = CMMotionManager()
    @Published var permissionDenied = false
    @Published var ready = false
    @Published var capturing = false
    @Published var captureProgress = 0
    @Published var error: String?
    @Published var guidance = "Starting camera…"
    @Published var stable = false
    @Published var focusing = true
    @Published var highDetail = false
    @Published var torch = false
    @Published var dimensions = ""
    @Published var minimumFocus = ""
    var onCapture: (([Data]) -> Void)?
    func start() {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] allowed in
                if allowed { self?.configure() } else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default: DispatchQueue.main.async { self.permissionDenied = true }
        }
    }
    private func configure() {
        sessionQueue.async {
            guard !self.configured else { if !self.session.isRunning { self.session.startRunning() }; return }
            self.session.beginConfiguration(); self.session.sessionPreset = .photo
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else {
                    throw MeasureError.invalid("A physical main camera is required.")
                }
                let input = try AVCaptureDeviceInput(device:camera)
                guard self.session.canAddInput(input),self.session.canAddOutput(self.output),self.session.canAddOutput(self.video) else {
                    throw MeasureError.invalid("Camera configuration is unavailable.")
                }
                self.camera = camera; self.session.addInput(input); self.session.addOutput(self.output)
                self.video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                self.video.alwaysDiscardsLateVideoFrames = true
                self.video.setSampleBufferDelegate(self,queue:self.videoQueue); self.session.addOutput(self.video)
                self.output.maxPhotoQualityPrioritization = .quality
                if let largest = camera.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width)*Int64($0.height) < Int64($1.width)*Int64($1.height) }) {
                    self.output.maxPhotoDimensions = largest
                }
                if let c = self.output.connection(with:.video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                camera.unlockForConfiguration()
                self.session.commitConfiguration(); self.configured = true; self.session.startRunning()
                DispatchQueue.main.async {
                    self.ready = true
                    self.minimumFocus = camera.minimumFocusDistance > 0 ? "Main lens minimum focus: \(camera.minimumFocusDistance) mm" : "Keep both surfaces sharply focused"
                    self.startMotion()
                }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to:.main) { [weak self] data,_ in
            guard let self,let data else { return }
            let r = data.rotationRate, a = data.userAcceleration
            self.stable = sqrt(r.x*r.x+r.y*r.y+r.z*r.z) < 0.045 && sqrt(a.x*a.x+a.y*a.y+a.z*a.z) < 0.035
        }
    }
    func stop() {
        motion.stopDeviceMotionUpdates()
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
    func setTorch(_ value: Bool) {
        sessionQueue.async {
            guard let camera = self.camera,camera.hasTorch else { return }
            do { try camera.lockForConfiguration(); camera.torchMode = value ? .on : .off; camera.unlockForConfiguration() }
            catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func capture() {
        guard ready,!capturing else { return }
        capturing = true; captureProgress = 0; error = nil
        let detail=highDetail
        sessionQueue.async {
            self.captureHighDetail=detail
            self.photos = []
            if let camera=self.camera {
                do {
                    try camera.lockForConfiguration()
                    if camera.isFocusModeSupported(.locked) { camera.focusMode = .locked }
                    if camera.isExposureModeSupported(.locked) { camera.exposureMode = .locked }
                    if camera.isWhiteBalanceModeSupported(.locked) { camera.whiteBalanceMode = .locked }
                    camera.unlockForConfiguration()
                } catch { self.finish(error:error.localizedDescription);return }
            }
            self.takePhoto()
        }
    }
    private func takePhoto() {
        let settings = AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.jpeg])
        let supported = camera?.activeFormat.supportedMaxPhotoDimensions ?? []
        let largest = output.maxPhotoDimensions
        let standard = supported.filter { Int64($0.width)*Int64($0.height) <= 13_000_000 }.max { Int64($0.width)*Int64($0.height) < Int64($1.width)*Int64($1.height) }
        settings.maxPhotoDimensions = captureHighDetail ? largest : (standard ?? largest)
        settings.photoQualityPrioritization = .quality
        output.capturePhoto(with:settings,delegate:self)
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        let data = photo.fileDataRepresentation()
        sessionQueue.async {
            if let error { self.finish(error:error.localizedDescription); return }
            guard let data else { self.finish(error:"The camera returned no photograph."); return }
            self.photos.append(data)
            let count=self.photos.count
            DispatchQueue.main.async { self.captureProgress = count }
        }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishCaptureFor resolvedSettings:AVCaptureResolvedPhotoSettings,error:Error?) {
        sessionQueue.async {
            if let error { self.finish(error:error.localizedDescription); return }
            guard !self.photos.isEmpty else { return }
            if self.photos.count < self.expectedPhotos {
                self.sessionQueue.asyncAfter(deadline:.now()+0.2) { self.takePhoto() }
            } else { self.finish(error:nil) }
        }
    }
    private func finish(error:String?) {
        let result = photos
        if let camera {
            do {
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { camera.whiteBalanceMode = .continuousAutoWhiteBalance }
                camera.unlockForConfiguration()
            } catch { /* Capture completion still reports its original outcome. */ }
        }
        DispatchQueue.main.async {
            self.capturing = false
            if let error { self.error = error } else { self.onCapture?(result) }
        }
    }
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection) {
        frameNumber += 1; guard frameNumber % 12 == 0,let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer,.readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        guard let address = CVPixelBufferGetBaseAddressOfPlane(buffer,0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(buffer,0),h = CVPixelBufferGetHeightOfPlane(buffer,0),stride = CVPixelBufferGetBytesPerRowOfPlane(buffer,0)
        let p = address.assumingMemoryBound(to:UInt8.self)
        var sum = 0.0,count = 0,clipped = 0
        for y in Swift.stride(from:h/4,to:3*h/4,by:24) { for x in Swift.stride(from:w/4,to:3*w/4,by:24) {
            let value = Int(p[y*stride+x]); sum += Double(value);count += 1;if value > 248 { clipped += 1 }
        } }
        let mean = sum/Double(max(count,1)),over = Double(clipped)/Double(max(count,1))
        let focus = camera?.isAdjustingFocus ?? false
        DispatchQueue.main.async {
            self.focusing = focus
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { self.guidance = "Phone is warm. Pause for consistent captures." }
            else if mean < 45 { self.guidance = "Add diffuse light to show both boundaries." }
            else if over > 0.15 { self.guidance = "Reduce glare on the material and tape." }
            else if focus { self.guidance = "Let the main lens focus. Move back if needed." }
            else if !self.stable { self.guidance = "Support the phone and hold steady." }
            else { self.guidance = "Keep tape and edges in one plane. Ready to capture." }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = previewLayer.connection,c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        }
    }
    func makeUIView(context:Context) -> Preview { let v = Preview(); v.previewLayer.session = session;v.previewLayer.videoGravity = .resizeAspect; return v }
    func updateUIView(_ uiView:Preview,context:Context) {}
}
