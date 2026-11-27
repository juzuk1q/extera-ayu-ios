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
    private var currentMaxZoom: CGFloat = 2.0

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
    private let zoomStatePromise = ValuePromise<CameraZoomState>(CameraZoomState(levels: [1.0, 2.0], maxZoom: 2.0))
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
        log: ((String) -> Void)?
    ) {
        self.configuration = configuration
        self.previewView = previewView
        self.roundVideoMode = roundVideoMode
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
            guard let self, !self.isInvalidated, let device = self.frontDevice else {
                return
            }
            let minHw = max(1.0, device.minAvailableVideoZoomFactor)
            let maxHw = max(minHw, device.maxAvailableVideoZoomFactor)
            let cappedRequested = min(self.currentMaxZoom, max(1.0, zoomScale))
            let clampedHw = min(maxHw, max(minHw, cappedRequested))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedHw
                device.unlockForConfiguration()
            } catch {
                self.emitLog("FrontRoundCamera lockForConfiguration(zoom) failed: \(error.localizedDescription)")
            }
            let digital = (cappedRequested > clampedHw + 0.01 && clampedHw > 0.0) ? (cappedRequested / clampedHw) : 1.0
            self.emitLog("FrontRoundCamera setZoomScale: req=\(zoomScale) capped=\(cappedRequested) hw=\(clampedHw) hwMax=\(maxHw) digital=\(digital)")
            self.applyDigitalZoom(digital)
        }
    }

    func setZoomLevel(_ zoomLevel: CGFloat) {
        self.setZoomScale(1.0 + zoomLevel)
    }

    func setZoomDelta(_ zoomDelta: CGFloat) {
        self.sessionQueue.async { [weak self] in
            guard let self, let device = self.frontDevice else {
                return
            }
            let currentTotal = device.videoZoomFactor * CGFloat(self.digitalZoomValue.with { $0 })
            let nextTotal = max(1.0, min(self.currentMaxZoom, currentTotal * zoomDelta))
            self.setZoomScale(nextTotal)
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
            self.applyFrameRate(fps, device: device, input: input)
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

    private func selectFrontFormat(for device: AVCaptureDevice, targetFps: Double) -> AVCaptureDevice.Format? {
        for (idx, format) in device.formats.enumerated() {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let ranges = format.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: ",")
            let multiCam = format.isMultiCamSupported
            let centerStage = format.isCenterStageSupported
            self.emitLog("FrontFormat[\(idx)]: \(dims.width)x\(dims.height) sub=\(subtype) ranges=[\(ranges)] multiCam=\(multiCam) hdr=\(format.isVideoHDRSupported) centerStage=\(centerStage)")
        }

        let nv12Formats = device.formats.filter { format in
            let sub = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return sub == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || sub == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }

        let candidatesSupportingTarget = nv12Formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard min(dims.width, dims.height) >= 720 else { return false }
            return format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= targetFps && $0.maxFrameRate >= targetFps - 0.5 })
        }

        let pool: [AVCaptureDevice.Format]
        if !candidatesSupportingTarget.isEmpty {
            pool = candidatesSupportingTarget
        } else {
            pool = nv12Formats.filter { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return min(dims.width, dims.height) >= 720 && !format.videoSupportedFrameRateRanges.isEmpty
            }
        }

        // Prefer exact 1920x1080, then 1920x1440/1440x1080/1280x960/1280x720, then highest max fps, then 420f/closest to 1080p
        return pool.max { lhs, rhs in
            let lDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let lMaxFps = lhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
            let rMaxFps = rhs.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
            if lMaxFps != rMaxFps {
                return lMaxFps < rMaxFps
            }
            let l1080 = (lDims.width == 1920 && lDims.height == 1080)
            let r1080 = (rDims.width == 1920 && rDims.height == 1080)
            if l1080 != r1080 {
                return !l1080
            }
            let lArea = Int64(lDims.width) * Int64(lDims.height)
            let rArea = Int64(rDims.width) * Int64(rDims.height)
            if lArea != rArea {
                return abs(lArea - 1920 * 1080) > abs(rArea - 1920 * 1080)
            }
            return CMFormatDescriptionGetMediaSubType(lhs.formatDescription) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                && CMFormatDescriptionGetMediaSubType(rhs.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
    }

    private func configureSession() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        guard !self.isConfigured, !self.isInvalidated else {
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera], mediaType: .video, position: .front).devices.first else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        let targetFps = roundVideoCaptureFrameRate
        guard let selectedFormat = self.selectFrontFormat(for: device, targetFps: targetFps) else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        guard let vInput = try? AVCaptureDeviceInput(device: device) else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }

        let vOutput = AVCaptureVideoDataOutput()
        let pixelFormats = vOutput.availableVideoPixelFormatTypes
        let pixelFormat: OSType
        if pixelFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } else if pixelFormats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } else {
            self.initFailedError = .videoRecorderInitializationError
            return
        }
        vOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
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
        }

        if let connection = vOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }

        self.session.commitConfiguration()

        // Apply frame durations strictly AFTER commitConfiguration() so sessionPreset/connections cannot overwrite them
        self.applyFrameRate(targetFps, device: device, input: vInput)

        self.frontDevice = device
        self.videoInput = vInput
        self.videoOutput = vOutput
        self.isConfigured = true
        self.initFailedError = nil

        self.updateZoomState(for: device)
        self.logEffectsAndFormat(device: device, targetFps: targetFps)

        DispatchQueue.main.async { [weak self] in
            self?.previewView?.updateOrientation()
        }
    }

    private func applyFrameRate(_ fps: Double, device: AVCaptureDevice, input: AVCaptureDeviceInput) {
        let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.minFrameRate <= fps && $0.maxFrameRate >= fps - 0.5 })
            ?? device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })
        guard let range else {
            return
        }
        let target = min(fps, range.maxFrameRate)
        let effective = min(range.maxFrameRate, max(range.minFrameRate, target))
        let duration = CMTime(seconds: 1.0 / effective, preferredTimescale: 60_000)
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
        self.emitLog("FrontRoundCamera applyFrameRate: requested=\(fps) range=\(range.minFrameRate)-\(range.maxFrameRate) effective=\(effective) actualDeviceFps=\(actualFps)")
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
        self.emitLog("FrontRoundCamera state: dims=\(dims.width)x\(dims.height) targetFps=\(targetFps) maxFormatFps=\(maxFps) effectiveFps=\(effectiveFps) hdr=\(device.isVideoHDREnabled) centerStage=\(centerStage) portrait=\(portrait) studioLight=\(studioLight) reactions=\(reactions)")
    }

    private func updateZoomState(for device: AVCaptureDevice) {
        let hwMax = max(1.0, device.maxAvailableVideoZoomFactor)
        let upscaleRaw = device.activeFormat.videoZoomFactorUpscaleThreshold
        let upscaleMax = upscaleRaw > 1.0 ? upscaleRaw : hwMax
        let maxZoomMode = (UserDefaults.standard.object(forKey: "io.roundVideoMaxZoomMode") as? NSNumber)?.intValue ?? 1
        var effectiveMax = maxZoomMode == 0 ? min(hwMax, upscaleMax) : hwMax
        effectiveMax = max(2.0, effectiveMax)
        self.currentMaxZoom = effectiveMax

        let roundedMax = Float((effectiveMax * 10.0).rounded() / 10.0)
        let levels: [Float] = roundedMax > 2.2 ? [1.0, 2.0, roundedMax] : [1.0, max(2.0, roundedMax)]
        self.emitLog("FrontRoundCamera updateZoomState: hwMax=\(hwMax) upscaleMax=\(upscaleMax) mode=\(maxZoomMode) effectiveMax=\(effectiveMax) levels=\(levels)")
        self.zoomStatePromise.set(CameraZoomState(levels: levels, maxZoom: effectiveMax))
    }

    private func applyDigitalZoom(_ zoom: CGFloat) {
        let scale = Float(max(1.0, zoom))
        let _ = self.digitalZoomValue.swap(scale)
        DispatchQueue.main.async { [weak self] in
            self?.previewView?.setDigitalZoom(CGFloat(scale))
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
