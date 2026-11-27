import Foundation
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import SwiftSignalKit
import DeviceModel
import Camera
import os.log

private let frontCameraLog = OSLog(subsystem: "org.telegram.CameraNeo", category: "FrontRound")

enum RoundVideoCenterStageSuppression {
    private static let activeCount = Atomic<Int>(value: 0)

    static func acquire() {
        var shouldDisable = false
        let _ = self.activeCount.modify { current in
            shouldDisable = (current == 0)
            return current + 1
        }
        if shouldDisable {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }
    }

    static func release() {
        var shouldRestore = false
        let _ = self.activeCount.modify { current in
            let next = max(0, current - 1)
            shouldRestore = (current > 0 && next == 0)
            return next
        }
        if shouldRestore {
            AVCaptureDevice.centerStageControlMode = .user
        }
    }
}

public final class FrontRoundCameraImpl: CameraImpl {
    private let roundVideoMode: NeoCameraImpl.RoundVideoMode
    private let log: ((String) -> Void)?

    public init(roundVideoMode: NeoCameraImpl.RoundVideoMode = .hdBilinear, log: ((String) -> Void)? = nil) {
        self.roundVideoMode = roundVideoMode
        self.log = log
        RoundVideoDecorationProvider.shared.warmUp()
    }

    public var isIpad: Bool {
        return DeviceModel.current.isIpad
    }

    public func isDualCameraSupported(forRoundVideo: Bool) -> Bool {
        return false
    }

    public func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?
    ) -> CameraProtocol {
        return self.makeCamera(configuration: configuration, previewView: previewView, secondaryPreviewView: secondaryPreviewView, initialZoom: 1.0)
    }

    func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?,
        initialZoom: CGFloat
    ) -> CameraProtocol {
        let preview: CameraPreviewView?
        if let previewView {
            guard let typed = previewView as? CameraPreviewView else {
                preconditionFailure("Unexpected preview view type for FrontRoundCameraImpl")
            }
            preview = typed
        } else {
            preview = nil
        }
        return FrontRoundCamera(
            configuration: configuration,
            previewView: preview,
            roundVideoMode: self.roundVideoMode,
            initialZoom: initialZoom,
            log: self.log
        )
    }

    public func makeCameraSimplePreviewView(frame: CGRect, main: Bool, roundVideo: Bool) -> CameraSimplePreviewView {
        return CameraPreviewView(frame: frame, main: main, roundVideo: roundVideo)
    }
}

final class FrontRoundCamera: NSObject, CameraProtocol {
    private let configuration: Camera.Configuration
    private let roundVideoMode: NeoCameraImpl.RoundVideoMode
    private let initialZoom: CGFloat
    private let log: ((String) -> Void)?
    private let previewView: CameraPreviewView?

    private let sessionQueue = DispatchQueue(label: "Camera.FrontRound.Session", qos: .userInitiated)
    private let mediaQueue = DispatchQueue(label: "Camera.FrontRound.Media", qos: .userInitiated)
    private let sessionQueueKey = DispatchSpecificKey<Void>()
    private let mediaQueueKey = DispatchSpecificKey<Void>()

    private let session = AVCaptureSession()
    private var wantsRunning = false
    private var isConfigured = false
    private var isInvalidated = false
    private let holdsCenterStageSuppression: Bool

    private var frontDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let audioOutputIdentity = Atomic<ObjectIdentifier?>(value: nil)

    private var recordingOrientation: AVCaptureVideoOrientation = .portrait
    private let digitalZoomValue = Atomic<Float>(value: 1.0)
    private var zoomLevels: [Float] = [1.0, 2.0]
    private var currentMaxZoom: CGFloat = 2.0
    private var currentZoom: CGFloat = 1.0

    private var frameProcessor: RoundVideoFrameProcessor?
    private var recorder: VideoRecorder?
    private let recordingActive = Atomic<Bool>(value: false)
    private let recordingStopRequested = Atomic<Bool>(value: false)
    private let recordingDuration = Atomic<Double>(value: 0.0)
    private let recordingCompletionPipe = ValuePipe<VideoCaptureResult>()
    private var initFailedError: CameraRecordingError?

    private var mainVideoOutput: CameraVideoOutput?

    private var deliveredFrameCount: Int = 0
    private var deliveredFpsWindowStart: CFTimeInterval = 0.0

    private let positionPromise = ValuePromise<Camera.Position>(.front)
    private let zoomStatePromise = ValuePromise<CameraZoomState>(ignoreRepeated: true)
    private let flashModePromise = ValuePromise<Camera.FlashMode>(.off)
    private let hasTorchPromise = ValuePromise<Bool>(false)
    private let isFlashActivePromise = ValuePromise<Bool>(false)
    private let transitionImagePromise = ValuePromise<UIImage?>(nil)
    private let modeChangePromise = ValuePromise<Camera.ModeChange>(.none)

    let metrics: Camera.Metrics

    init(
        configuration: Camera.Configuration,
        previewView: CameraPreviewView?,
        roundVideoMode: NeoCameraImpl.RoundVideoMode,
        initialZoom: CGFloat,
        log: ((String) -> Void)?
    ) {
        self.configuration = configuration
        self.previewView = previewView
        self.roundVideoMode = roundVideoMode
        self.initialZoom = initialZoom
        self.log = log
        self.metrics = Camera.Metrics(model: DeviceModel.current)
        self.holdsCenterStageSuppression = configuration.isRoundVideo

        super.init()

        self.session.usesApplicationAudioSession = true
        self.session.automaticallyConfiguresApplicationAudioSession = false

        self.sessionQueue.setSpecific(key: self.sessionQueueKey, value: ())
        self.mediaQueue.setSpecific(key: self.mediaQueueKey, value: ())

        self.previewView?.setSession(self.session, automaticallyConnect: true)

        if self.holdsCenterStageSuppression {
            RoundVideoCenterStageSuppression.acquire()
        }

        self.emitLog("FrontRoundCamera.init: isRoundVideo=\(configuration.isRoundVideo) targetFps=\(roundVideoCaptureFrameRate)")

        self.sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    deinit {
        if self.holdsCenterStageSuppression {
            RoundVideoCenterStageSuppression.release()
        }
        let cleanUpSession = {
            self.videoOutput?.setSampleBufferDelegate(nil, queue: nil)
            self.audioOutput?.setSampleBufferDelegate(nil, queue: nil)
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.tearDownSession()
        }
        if DispatchQueue.getSpecific(key: self.sessionQueueKey) != nil {
            cleanUpSession()
        } else {
            self.sessionQueue.sync(execute: cleanUpSession)
        }
        if DispatchQueue.getSpecific(key: self.mediaQueueKey) != nil {
            self.recorder?.cancel()
        } else {
            self.mediaQueue.sync {
                self.recorder?.cancel()
            }
        }
    }

    private func emitLog(_ message: String) {
        os_log("%{public}@", log: frontCameraLog, type: .info, message)
        self.log?(message)
    }

    func startCapture() {
        self.sessionQueue.async { [weak self] in
            guard let self, !self.isInvalidated else {
                return
            }
            self.wantsRunning = true
            if !self.isConfigured {
                self.configureSession()
            }
            if self.isConfigured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopCapture(invalidate: Bool) {
        self.sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.wantsRunning = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if invalidate {
                self.isInvalidated = true
                self.tearDownSession()
                let session = self.session
                DispatchQueue.main.async { [weak self] in
                    self?.previewView?.invalidate(for: session)
                }
            }
        }

        if invalidate {
            self.mediaQueue.async { [weak self] in
                guard let self else {
                    return
                }
                self.recorder?.cancel()
                self.recorder = nil
                let _ = self.recordingActive.modify { _ in false }
                let _ = self.recordingStopRequested.modify { _ in false }
            }
        }
    }

    var position: Signal<Camera.Position, NoError> {
        return self.positionPromise.get()
    }

    func togglePosition() {
    }

    func setPosition(_ position: Camera.Position) {
    }

    func setDualCameraEnabled(_ enabled: Bool) {
    }

    func setCaptureMode(_ mode: CameraCaptureMode) -> Signal<Void, NoError> {
        return .single(Void())
    }

    func setZoomScale(_ zoomScale: CGFloat) {
        self.sessionQueue.async { [weak self] in
            self?.applyZoomScale(zoomScale)
        }
    }

    private func applyZoomScale(_ zoomScale: CGFloat) {
        guard !self.isInvalidated, zoomScale.isFinite, let device = self.frontDevice else {
            return
        }
        let requested = min(self.currentMaxZoom, max(1.0, zoomScale))
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, requested))
            device.unlockForConfiguration()
        } catch {
            self.emitLog("FrontRoundCamera lockForConfiguration(zoom) failed: \(error.localizedDescription)")
        }
        let hardwareZoom = device.videoZoomFactor
        let digitalZoom = max(1.0, requested / hardwareZoom)
        self.applyDigitalZoom(digitalZoom)
        self.currentZoom = hardwareZoom * digitalZoom
        self.zoomStatePromise.set(CameraZoomState(levels: self.zoomLevels, maxZoom: self.currentMaxZoom, currentZoom: self.currentZoom))
    }

    func setZoomLevel(_ zoomLevel: CGFloat) {
        self.setZoomScale(1.0 + zoomLevel)
    }

    func setZoomDelta(_ zoomDelta: CGFloat) {
        self.sessionQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.applyZoomScale(self.currentZoom * zoomDelta)
        }
    }

    func rampZoom(_ zoomLevel: CGFloat, rate: CGFloat) {
    }

    func beginExposureTargetBiasChange() {
    }

    func setExposureTargetBias(_ bias: CGFloat) {
    }

    func endExposureTargetBiasChange() {
    }

    func takePhoto() -> Signal<PhotoCaptureResult, NoError> {
        return .complete()
    }

    func startRecording(captureMode: CameraCaptureMode) -> Signal<CameraRecordingData, CameraRecordingError> {
        return self.startRecording()
    }

    func startRecording() -> Signal<CameraRecordingData, CameraRecordingError> {
        guard self.configuration.isRoundVideo else {
            return .complete()
        }
        if let error = self.initFailedError {
            return .fail(error)
        }

        var wasActive = false
        let _ = self.recordingActive.modify { current in
            wasActive = current
            return true
        }
        guard !wasActive else {
            return .complete()
        }
        let _ = self.recordingStopRequested.modify { _ in false }

        let outputUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        let orientation: AVCaptureVideoOrientation = cameraRecordsRoundVideoInPreviewOrientation ? (self.previewView?.captureOrientation ?? .portrait) : .portrait
        let _ = self.recordingDuration.modify { _ in 0.0 }
        self.transitionImagePromise.set(nil)

        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }

            let subscriberActive = Atomic<Bool>(value: true)
            let recordingPrepared = Atomic<Bool>(value: false)
            let beginRecording: (RoundVideoDecorationResources?) -> Void = { [weak self] decorationResources in
                guard let self else {
                    return
                }
                self.mediaQueue.async { [weak self] in
                    guard let self else {
                        return
                    }
                    guard subscriberActive.with({ $0 }), self.recordingActive.with({ $0 }) else {
                        let _ = self.recordingActive.modify { _ in false }
                        let _ = self.recordingStopRequested.modify { _ in false }
                        return
                    }
                    if let error = self.initFailedError {
                        let _ = self.recordingActive.modify { _ in false }
                        let _ = self.recordingStopRequested.modify { _ in false }
                        if subscriberActive.swap(false) {
                            subscriber.putError(error)
                        }
                        return
                    }

                    let processor: RoundVideoFrameProcessor
                    if let current = self.frameProcessor {
                        processor = current
                    } else if let decorationResources, let current = RoundVideoFrameProcessor(mediaQueue: self.mediaQueue, decorationResources: decorationResources, mode: self.roundVideoMode) {
                        self.frameProcessor = current
                        processor = current
                    } else {
                        guard let current = RoundVideoFrameProcessor(mediaQueue: self.mediaQueue, decorationResources: nil, mode: self.roundVideoMode) else {
                            let _ = self.recordingActive.modify { _ in false }
                            let _ = self.recordingStopRequested.modify { _ in false }
                            if subscriberActive.swap(false) {
                                subscriber.putError(.videoRecorderInitializationError)
                            }
                            return
                        }
                        self.frameProcessor = current
                        processor = current
                    }

                    self.recordingOrientation = orientation
                    self.emitLog("FrontRoundCamera startRecording: initialPosition=front activeDevicePos=\(self.frontDevice?.position.rawValue ?? -1)")
                    let recorder = VideoRecorder(
                        mediaQueue: self.mediaQueue,
                        processor: processor,
                        url: outputUrl,
                        hasAudio: self.configuration.audio,
                        initialPosition: .front,
                        mode: self.roundVideoMode,
                        usesMultiCam: false,
                        log: self.log,
                        durationUpdated: { [weak self] duration in
                            let _ = self?.recordingDuration.modify { _ in duration }
                        },
                        transitionImageUpdated: { [weak self] image in
                            self?.transitionImagePromise.set(image)
                        },
                        runtimeFailure: { error in
                            if subscriberActive.swap(false) {
                                subscriber.putError(error)
                            }
                        },
                        completion: { [weak self] result in
                            guard let self else {
                                return
                            }
                            self.recorder = nil
                            let _ = self.recordingActive.modify { _ in false }
                            let _ = self.recordingStopRequested.modify { _ in false }
                            switch result {
                            case let .success(url, thumbnail, duration, positionChangeTimestamps):
                                self.recordingCompletionPipe.putNext(.finished(
                                    main: VideoCaptureResult.Result(
                                        path: url.path,
                                        thumbnail: thumbnail ?? UIImage(),
                                        isMirrored: false,
                                        dimensions: CGSize(width: RoundVideoFrameProcessor.outputWidth, height: RoundVideoFrameProcessor.outputHeight)
                                    ),
                                    additional: nil,
                                    duration: duration,
                                    positionChangeTimestamps: positionChangeTimestamps.map { ($0.0 == .front, $0.1) },
                                    captureTimestamp: CACurrentMediaTime()
                                ))
                            case .failed:
                                self.recordingCompletionPipe.putNext(.failed)
                            }
                        }
                    )
                    self.recorder = recorder
                    let _ = recordingPrepared.modify { _ in true }
                    if self.recordingStopRequested.with({ $0 }) {
                        recorder.stop()
                    }
                }
            }

            RoundVideoDecorationProvider.shared.prepare(completion: beginRecording)

            let timer = SwiftSignalKit.Timer(timeout: 0.09, repeat: true, completion: { [weak self] in
                guard let self, subscriberActive.with({ $0 }), recordingPrepared.with({ $0 }) else {
                    return
                }
                subscriber.putNext(CameraRecordingData(
                    duration: self.recordingDuration.with { $0 },
                    filePath: outputUrl.path
                ))
            }, queue: Queue.mainQueue())
            timer.start()

            return ActionDisposable {
                let _ = subscriberActive.modify { _ in false }
                timer.invalidate()
            }
        }
    }

    func stopRecording() -> Signal<VideoCaptureResult, NoError> {
        guard self.recordingActive.with({ $0 }) else {
            return .complete()
        }
        let _ = self.recordingStopRequested.modify { _ in true }
        self.mediaQueue.async { [weak self] in
            self?.recorder?.stop()
        }
        return self.recordingCompletionPipe.signal()
        |> take(1)
    }

    func focus(at point: CGPoint, autoFocus: Bool) {
        self.sessionQueue.async { [weak self] in
            guard let device = self?.frontDevice else {
                return
            }
            do {
                try device.lockForConfiguration()
                let focusMode: AVCaptureDevice.FocusMode = autoFocus ? .continuousAutoFocus : .autoFocus
                let exposureMode: AVCaptureDevice.ExposureMode = autoFocus ? .continuousAutoExposure : .autoExpose
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = point
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = exposureMode
                }
                device.unlockForConfiguration()
            } catch {
            }
        }
    }

    func setFps(_ fps: Double) {
        self.sessionQueue.async { [weak self] in
            guard let self, !self.isInvalidated, let device = self.frontDevice, let input = self.videoInput else {
                return
            }
            self.session.beginConfiguration()
            self.applyFrameRate(fps, device: device, input: input)
            self.session.commitConfiguration()
        }
    }

    func setFlashMode(_ flashMode: Camera.FlashMode) {
        self.flashModePromise.set(flashMode)
    }

    func setTorchActive(_ active: Bool) {
        self.isFlashActivePromise.set(false)
    }

    var hasTorch: Signal<Bool, NoError> {
        return self.hasTorchPromise.get()
    }

    var isFlashActive: Signal<Bool, NoError> {
        return self.isFlashActivePromise.get()
    }

    var flashMode: Signal<Camera.FlashMode, NoError> {
        return self.flashModePromise.get()
    }

    var zoomState: Signal<CameraZoomState, NoError> {
        return self.zoomStatePromise.get()
    }

    func setMainVideoOutput(_ output: CameraVideoOutput?) {
        self.mediaQueue.async { [weak self] in
            self?.mainVideoOutput = output
        }
    }

    func setAdditionalVideoOutput(_ output: CameraVideoOutput?) {
    }

    func attachSimplePreviewView(_ view: CameraSimplePreviewView) {
    }

    var detectedCodes: Signal<[CameraCode], NoError> {
        return .never()
    }

    var audioLevel: Signal<Float, NoError> {
        return .never()
    }

    var transitionImage: Signal<UIImage?, NoError> {
        return self.transitionImagePromise.get()
    }

    var modeChange: Signal<Camera.ModeChange, NoError> {
        return self.modeChangePromise.get()
    }

    private func selectFrontCapture(targetFps: Double) -> (device: AVCaptureDevice, format: AVCaptureDevice.Format)? {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTrueDepthCamera]
        if #available(iOS 13.0, *) {
            deviceTypes.insert(.builtInUltraWideCamera, at: 1)
        }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .front).devices
        let targetShortSide: Int32 = self.roundVideoMode == .vga ? 480 : 1080
        let candidates = devices.flatMap { device in
            device.formats.compactMap { format -> (device: AVCaptureDevice, format: AVCaptureDevice.Format, fps: Double, sizeDistance: Int32, area: Int64)? in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let shortSide = min(dimensions.width, dimensions.height)
                guard shortSide >= 480, let duration = roundVideoFrameDuration(targetFps, format: format) else {
                    return nil
                }
                return (device, format, 1.0 / duration.seconds, abs(shortSide - targetShortSide), Int64(dimensions.width) * Int64(dimensions.height))
            }
        }
        guard let selected = candidates.min(by: { lhs, rhs in
            // 59.94 and 60 FPS are equivalent for ranking the capture formats.
            let lhsFps = lhs.fps.rounded()
            let rhsFps = rhs.fps.rounded()
            if lhsFps != rhsFps {
                return lhsFps > rhsFps
            }
            if lhs.sizeDistance != rhs.sizeDistance {
                return lhs.sizeDistance < rhs.sizeDistance
            }
            let lhsNV12 = isRoundVideoNV12Format(lhs.format)
            let rhsNV12 = isRoundVideoNV12Format(rhs.format)
            if lhsNV12 != rhsNV12 {
                return lhsNV12
            }
            return lhs.area < rhs.area
        }) else {
            return nil
        }
        return (selected.device, selected.format)
    }

    private func configureSession() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        guard !self.isConfigured, !self.isInvalidated else {
            return
        }

        let targetFps = roundVideoCaptureFrameRate
        guard let (device, selectedFormat) = self.selectFrontCapture(targetFps: targetFps) else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        guard let vInput = try? AVCaptureDeviceInput(device: device) else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        let vOutput = AVCaptureVideoDataOutput()
        vOutput.alwaysDiscardsLateVideoFrames = true
        vOutput.setSampleBufferDelegate(self, queue: self.mediaQueue)

        self.session.beginConfiguration()
        self.session.sessionPreset = .inputPriority

        guard self.session.canAddInput(vInput), self.session.canAddOutput(vOutput) else {
            self.session.commitConfiguration()
            self.initFailedError = .videoRecorderInitializationError
            return
        }
        self.session.addInput(vInput)
        self.session.addOutput(vOutput)

        do {
            try device.lockForConfiguration()
            device.activeFormat = selectedFormat
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
            if device.automaticallyAdjustsVideoHDREnabled {
                device.automaticallyAdjustsVideoHDREnabled = false
            }
            if device.isVideoHDREnabled {
                device.isVideoHDREnabled = false
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            self.emitLog("FrontRoundCamera format lock failed: \(error.localizedDescription)")
            self.session.removeOutput(vOutput)
            self.session.removeInput(vInput)
            self.session.commitConfiguration()
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        let pixelFormats = vOutput.availableVideoPixelFormatTypes
        let pixelFormat: OSType
        let nativePixelFormat = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
        if isRoundVideoNV12Format(device.activeFormat), pixelFormats.contains(nativePixelFormat) {
            pixelFormat = nativePixelFormat
        } else if pixelFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } else if pixelFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } else {
            self.session.removeOutput(vOutput)
            self.session.removeInput(vInput)
            self.session.commitConfiguration()
            self.initFailedError = .videoRecorderInitializationError
            return
        }
        vOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]

        if self.configuration.audio,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let aInput = try? AVCaptureDeviceInput(device: audioDevice),
           self.session.canAddInput(aInput) {
            let aOutput = AVCaptureAudioDataOutput()
            aOutput.setSampleBufferDelegate(self, queue: self.mediaQueue)
            if self.session.canAddOutput(aOutput) {
                self.session.addInput(aInput)
                self.session.addOutput(aOutput)
                self.audioInput = aInput
                self.audioOutput = aOutput
                let _ = self.audioOutputIdentity.modify { _ in ObjectIdentifier(aOutput) }
            }
        }

        if let connection = vOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }

        self.applyFrameRate(targetFps, device: device, input: vInput)
        self.session.commitConfiguration()

        self.frontDevice = device
        self.videoInput = vInput
        self.videoOutput = vOutput
        self.isConfigured = true
        self.initFailedError = nil

        self.updateZoomLimits(for: device)
        self.applyZoomScale(self.initialZoom)
        self.logEffectsAndFormat(device: device, targetFps: targetFps)

        DispatchQueue.main.async { [weak self] in
            self?.previewView?.updateOrientation()
        }
    }

    private func applyFrameRate(_ fps: Double, device: AVCaptureDevice, input: AVCaptureDeviceInput) {
        guard let duration = roundVideoFrameDuration(fps, format: device.activeFormat) else {
            return
        }
        do {
            try device.lockForConfiguration()
            if #available(iOS 18.0, *), device.activeFormat.isAutoVideoFrameRateSupported, device.isAutoVideoFrameRateEnabled {
                device.isAutoVideoFrameRateEnabled = false
            }
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            self.emitLog("FrontRoundCamera frameRate lock failed: \(error.localizedDescription)")
        }
        input.videoMinFrameDurationOverride = duration
        let actualMin = device.activeVideoMinFrameDuration.seconds
        let actualFps = actualMin > 0.0 ? 1.0 / actualMin : 0.0
        self.emitLog("FrontRoundCamera applyFrameRate: requested=\(fps) effective=\(1.0 / duration.seconds) actualDeviceFps=\(actualFps)")
    }

    private func logEffectsAndFormat(device: AVCaptureDevice, targetFps: Double) {
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let maxFps = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
        let actualMin = device.activeVideoMinFrameDuration.seconds
        let effectiveFps = actualMin > 0.0 ? 1.0 / actualMin : 0.0
        let centerStage = AVCaptureDevice.isCenterStageEnabled
        let portrait = AVCaptureDevice.isPortraitEffectEnabled
        var studioLight = false
        if #available(iOS 16.0, *) {
            studioLight = AVCaptureDevice.isStudioLightEnabled
        }
        var reactions = false
        if #available(iOS 17.0, *) {
            reactions = AVCaptureDevice.reactionEffectsEnabled
        }
        self.emitLog("FrontRoundCamera state: device=\(device.deviceType.rawValue) dims=\(dims.width)x\(dims.height) targetFps=\(targetFps) maxFormatFps=\(maxFps) effectiveFps=\(effectiveFps) hdr=\(device.isVideoHDREnabled) centerStage=\(centerStage) portrait=\(portrait) studioLight=\(studioLight) reactions=\(reactions)")
    }

    private func updateZoomLimits(for device: AVCaptureDevice) {
        let hwMax = max(1.0, device.maxAvailableVideoZoomFactor)
        let upscaleRaw = device.activeFormat.videoZoomFactorUpscaleThreshold
        let upscaleMax = upscaleRaw > 1.0 ? upscaleRaw : hwMax
        let maxZoomMode = (UserDefaults.standard.object(forKey: "io.roundVideoMaxZoomMode") as? NSNumber)?.intValue ?? 1
        var effectiveMax = maxZoomMode == 0 ? min(hwMax, upscaleMax) : hwMax
        effectiveMax = max(2.0, effectiveMax)
        self.currentMaxZoom = effectiveMax

        let roundedMax = Float((effectiveMax * 10.0).rounded() / 10.0)
        let levels: [Float] = roundedMax > 2.2 ? [1.0, 2.0, roundedMax] : [1.0, max(2.0, roundedMax)]
        self.emitLog("FrontRoundCamera updateZoomLimits: hwMax=\(hwMax) upscaleMax=\(upscaleMax) mode=\(maxZoomMode) effectiveMax=\(effectiveMax) levels=\(levels)")
        self.zoomLevels = levels
    }

    private func applyDigitalZoom(_ zoom: CGFloat) {
        let scale = Float(max(1.0, zoom))
        let _ = self.digitalZoomValue.swap(scale)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.previewView?.setDigitalZoom(CGFloat(scale), for: self.session)
        }
    }

    private func tearDownSession() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        self.session.beginConfiguration()
        for output in self.session.outputs {
            self.session.removeOutput(output)
        }
        for input in self.session.inputs {
            self.session.removeInput(input)
        }
        self.session.commitConfiguration()
        self.videoOutput = nil
        self.audioOutput = nil
        let _ = self.audioOutputIdentity.modify { _ in nil }
        self.videoInput = nil
        self.audioInput = nil
        self.frontDevice = nil
        self.isConfigured = false
    }
}

extension FrontRoundCamera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(self.mediaQueue))
        self.recorder?.noteDroppedVideoSampleBuffer(sampleBuffer, position: .front)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(self.mediaQueue))
        let outputIdentity = ObjectIdentifier(output)
        if self.audioOutputIdentity.with({ $0 }) == outputIdentity {
            self.recorder?.appendAudioSampleBuffer(sampleBuffer)
            return
        }

        let now = CACurrentMediaTime()
        if self.deliveredFpsWindowStart == 0.0 {
            self.deliveredFpsWindowStart = now
        }
        self.deliveredFrameCount += 1
        let elapsed = now - self.deliveredFpsWindowStart
        if elapsed >= 1.5 {
            let deliveredFps = Double(self.deliveredFrameCount) / elapsed
            self.emitLog(String(format: "FrontRoundCamera captureOutput: deliveredFps=%.2f frames=%d elapsed=%.2fs", deliveredFps, self.deliveredFrameCount, elapsed))
            self.deliveredFrameCount = 0
            self.deliveredFpsWindowStart = now
        }

        let digitalZoom = self.digitalZoomValue.with { $0 }
        self.recorder?.appendVideoSampleBuffer(
            sampleBuffer,
            position: .front,
            orientation: self.recordingOrientation,
            digitalZoom: digitalZoom
        )
        self.mainVideoOutput?.push(sampleBuffer, mirror: true)
    }
}
