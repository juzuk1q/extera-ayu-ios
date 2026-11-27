import Foundation
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import SwiftSignalKit
import DeviceModel
import Camera
import os.log

private let cameraCaptureLog = OSLog(subsystem: "org.telegram.CameraNeo", category: "Capture")

private enum CaptureInitializationStatus {
    case pending
    case ready
    case failed(CameraRecordingError)
}

final class CameraNeo: NSObject, CameraProtocol {
    private let configuration: Camera.Configuration
    private let useMultiCam: Bool
    private let roundVideoMode: NeoCameraImpl.RoundVideoMode
    private let initialZoom: CGFloat
    private let log: ((String) -> Void)?
    private let previewView: CameraPreviewView?
    private let secondaryPreviewView: CameraPreviewView?

    private let sessionQueue = DispatchQueue(label: "Camera.Session", qos: .userInitiated)
    private let mediaQueue = DispatchQueue(label: "Camera.Media", qos: .userInitiated)
    private let sessionQueueKey = DispatchSpecificKey<Void>()
    private let mediaQueueKey = DispatchSpecificKey<Void>()

    private let session: AVCaptureSession
    private var wantsRunning = false
    private var isConfigured = false
    private var isInvalidated = false

    private var backDevice: AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?
    private var singleVideoInput: AVCaptureDeviceInput?
    private var backVideoInput: AVCaptureDeviceInput?
    private var frontVideoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var primaryVideoOutput: AVCaptureVideoDataOutput?
    private var secondaryVideoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var stabilizationObservers: [NSKeyValueObservation] = []
    private let secondaryVideoOutputIdentity = Atomic<ObjectIdentifier?>(value: nil)
    private let audioOutputIdentity = Atomic<ObjectIdentifier?>(value: nil)

    private var singleFramesEnabled = true
    private var deliveredFrameCount: Int = 0
    private var deliveredFpsWindowStart: CFTimeInterval = 0.0
    private var singleMediaPosition: Camera.Position
    private var recordingOrientation: AVCaptureVideoOrientation = .portrait
    private let frontDigitalZoom = Atomic<Float>(value: 1.0)
    private let backDigitalZoom = Atomic<Float>(value: 1.0)
    private var backWideCapture: (device: AVCaptureDevice, format: AVCaptureDevice.Format)?
    private var backUltraWideCapture: (device: AVCaptureDevice, format: AVCaptureDevice.Format)?

    private var frameProcessor: RoundVideoFrameProcessor?
    private var recorder: VideoRecorder?
    private let recordingActive = Atomic<Bool>(value: false)
    private let recordingStopRequested = Atomic<Bool>(value: false)
    private let recordingDuration = Atomic<Double>(value: 0.0)
    private let singleCameraSwitchGeneration = Atomic<Int>(value: 0)
    private let recordingCompletionPipe = ValuePipe<VideoCaptureResult>()
    private let captureInitializationStatus = Atomic<CaptureInitializationStatus>(value: .pending)

    private var mainVideoOutput: CameraVideoOutput?
    private var additionalVideoOutput: CameraVideoOutput?

    private let positionValue: Atomic<Camera.Position>
    private let positionPromise: ValuePromise<Camera.Position>
    private let zoomStatePromise = ValuePromise<CameraZoomState>(ignoreRepeated: true)
    private var zoomLevels: [Float] = [1.0, 2.0]
    private var currentZoom: CGFloat = 1.0
    private var currentMaxZoom: CGFloat = 2.0
    private let flashModePromise = ValuePromise<Camera.FlashMode>(.off)
    private let hasTorchPromise = ValuePromise<Bool>(false)
    private let isFlashActivePromise = ValuePromise<Bool>(false)
    private let transitionImagePromise = ValuePromise<UIImage?>(nil)
    private let modeChangePromise = ValuePromise<Camera.ModeChange>(.none)

    let metrics: Camera.Metrics

    init(
        configuration: Camera.Configuration,
        previewView: CameraPreviewView?,
        secondaryPreviewView: CameraPreviewView?,
        useMultiCam: Bool,
        roundVideoMode: NeoCameraImpl.RoundVideoMode,
        initialZoom: CGFloat,
        log: ((String) -> Void)?
    ) {
        self.configuration = configuration
        self.previewView = previewView
        self.secondaryPreviewView = secondaryPreviewView
        self.useMultiCam = useMultiCam
        self.roundVideoMode = roundVideoMode
        self.initialZoom = initialZoom
        self.log = log
        self.singleMediaPosition = configuration.position
        self.positionValue = Atomic<Camera.Position>(value: configuration.position)
        self.positionPromise = ValuePromise<Camera.Position>(configuration.position)
        self.metrics = Camera.Metrics(model: DeviceModel.current)

        if useMultiCam, #available(iOS 13.0, *) {
            self.session = AVCaptureMultiCamSession()
        } else {
            self.session = AVCaptureSession()
        }

        super.init()

        self.log?("CameraNeo.init: config.position=\(configuration.position.rawValue) useMultiCam=\(useMultiCam)")
        self.session.usesApplicationAudioSession = true
        self.session.automaticallyConfiguresApplicationAudioSession = false

        self.sessionQueue.setSpecific(key: self.sessionQueueKey, value: ())
        self.mediaQueue.setSpecific(key: self.mediaQueueKey, value: ())
        self.previewView?.setSession(self.session, automaticallyConnect: !useMultiCam)
        if useMultiCam {
            self.secondaryPreviewView?.setSession(self.session, automaticallyConnect: false)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: self.session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: self.session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.sessionDidStartRunning(_:)),
            name: .AVCaptureSessionDidStartRunning,
            object: self.session
        )

        self.sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let cleanUpSession = {
            self.primaryVideoOutput?.setSampleBufferDelegate(nil, queue: nil)
            self.secondaryVideoOutput?.setSampleBufferDelegate(nil, queue: nil)
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
                    self?.secondaryPreviewView?.invalidate(for: session)
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
        let currentPosition = self.positionValue.with { $0 }
        self.setPosition(currentPosition == .front ? .back : .front)
    }

    func setPosition(_ position: Camera.Position) {
        let previousPosition = self.positionValue.swap(position)
        guard previousPosition != position else {
            return
        }

        let switchGeneration = self.useMultiCam ? 0 : self.singleCameraSwitchGeneration.modify { $0 + 1 }

        self.modeChangePromise.set(.position)
        self.positionPromise.set(position)
        self.mediaQueue.async { [weak self] in
            guard let self else {
                return
            }
            if !self.useMultiCam {
                self.recorder?.beginSingleCameraSwitch(
                    generation: switchGeneration,
                    from: previousPosition,
                    to: position
                )
            }
            self.recorder?.beginPositionChange(to: position)
            if !self.useMultiCam {
                self.singleFramesEnabled = false
            }
        }

        self.sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.isInvalidated else {
                return
            }
            if previousPosition == .back, position == .front, let backDevice = self.backDevice {
                self.withLockedDevice(backDevice) { device in
                    if device.isTorchModeSupported(.off) {
                        device.torchMode = .off
                    }
                }
            }
            if self.useMultiCam {
                if let activeDevice = self.activeDevice {
                    self.updateZoomLimits(for: activeDevice)
                    self.applyZoomScale(1.0)
                }
                self.updateActiveDeviceState()
            } else {
                self.switchSingleCamera(to: position, generation: switchGeneration)
            }
            self.sessionQueue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.modeChangePromise.set(.none)
            }
        }
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
        guard self.isConfigured, !self.isInvalidated, zoomScale.isFinite, let currentDevice = self.activeDevice else {
            return
        }
        let position = self.positionValue.with { $0 }
        let scale = min(self.currentMaxZoom, max(CGFloat(self.zoomLevels.first ?? 1.0), zoomScale))
        if position == .back, !self.useMultiCam, let ultraWide = self.backUltraWideCapture {
            let isUltraWide = currentDevice === ultraWide.device
            if scale < 1.0, !isUltraWide {
                self.switchBackLens(to: ultraWide, zoomFactor: 2.0 * scale)
            } else if scale >= 1.0, isUltraWide, let wide = self.backWideCapture {
                self.switchBackLens(to: wide, zoomFactor: self.neutralZoomFactor(for: wide.device) * scale)
            }
        }
        guard let device = self.activeDevice else {
            return
        }
        let baseFactor = device === self.backUltraWideCapture?.device ? 2.0 : self.neutralZoomFactor(for: device)
        let requested = scale * baseFactor
        self.withLockedDevice(device) { device in
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = self.clampedZoom(requested, device: device)
        }
        let hardwareZoom = device.videoZoomFactor
        let digitalZoom = max(1.0, requested / hardwareZoom)
        self.applyDigitalZoom(digitalZoom, position: position)
        self.currentZoom = hardwareZoom * digitalZoom / baseFactor
        self.zoomStatePromise.set(CameraZoomState(levels: self.zoomLevels, maxZoom: self.currentMaxZoom, currentZoom: self.currentZoom))
    }

    func startRecording(captureMode: CameraCaptureMode) -> Signal<CameraRecordingData, CameraRecordingError> {
        return self.startRecording()
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

    func startRecording() -> Signal<CameraRecordingData, CameraRecordingError> {
        guard self.configuration.isRoundVideo else {
            return .complete()
        }
        if case let .failed(error) = self.captureInitializationStatus.with({ $0 }) {
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
        let orientation: AVCaptureVideoOrientation
        if cameraRecordsRoundVideoInPreviewOrientation {
            orientation = self.previewView?.captureOrientation ?? .portrait
        } else {
            orientation = .portrait
        }
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
                    if case let .failed(error) = self.captureInitializationStatus.with({ $0 }) {
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
                    let recPos = self.positionValue.with { $0 }
                    self.log?("startRecording: positionValue=\(recPos.rawValue) singleMediaPosition=\(self.singleMediaPosition.rawValue) activeDevicePos=\(self.activeDevice?.position.rawValue ?? -1)")
                    let recorder = VideoRecorder(
                        mediaQueue: self.mediaQueue,
                        processor: processor,
                        url: outputUrl,
                        hasAudio: self.configuration.audio,
                        initialPosition: recPos,
                        mode: self.roundVideoMode,
                        usesMultiCam: self.useMultiCam,
                        log: self.log,
                        durationUpdated: { [weak self] duration in
                            guard let self else {
                                return
                            }
                            let _ = self.recordingDuration.modify { _ in duration }
                        },
                        transitionImageUpdated: { [weak self] image in
                            self?.transitionImagePromise.set(image)
                        },
                        runtimeFailure: { error in
                            let wasActive = subscriberActive.swap(false)
                            if wasActive {
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
            guard let device = self?.activeDevice else {
                return
            }
            self?.withLockedDevice(device) { device in
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
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
        }
    }

    func setFps(_ fps: Double) {
        self.sessionQueue.async { [weak self] in
            guard let self, !self.isInvalidated else {
                return
            }
            self.session.beginConfiguration()
            if self.useMultiCam {
                if let backDevice = self.backDevice, let backVideoInput = self.backVideoInput {
                    self.configureFrameRate(fps, device: backDevice, input: backVideoInput)
                }
                if let frontDevice = self.frontDevice, let frontVideoInput = self.frontVideoInput {
                    self.configureFrameRate(fps, device: frontDevice, input: frontVideoInput)
                }
            } else if let activeDevice = self.activeDevice, let singleVideoInput = self.singleVideoInput {
                self.configureFrameRate(fps, device: activeDevice, input: singleVideoInput)
            }
            self.session.commitConfiguration()
            self.configureVideoStabilization()
        }
    }

    func setFlashMode(_ flashMode: Camera.FlashMode) {
        self.flashModePromise.set(flashMode)
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
        self.sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice else {
                return
            }
            self.withLockedDevice(device) { device in
                device.ramp(toVideoZoomFactor: self.clampedZoom(zoomLevel, device: device), withRate: Float(rate))
            }
        }
    }

    func setTorchActive(_ active: Bool) {
        self.sessionQueue.async { [weak self] in
            guard let self, let device = self.activeDevice else {
                return
            }
            var effectiveActive = false
            self.withLockedDevice(device) { device in
                let mode: AVCaptureDevice.TorchMode = active ? .on : .off
                if device.isTorchModeSupported(mode) {
                    device.torchMode = mode
                    effectiveActive = active
                }
            }
            self.isFlashActivePromise.set(effectiveActive)
        }
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
        self.mediaQueue.async { [weak self] in
            self?.additionalVideoOutput = output
        }
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

    private var activeDevice: AVCaptureDevice? {
        if self.positionValue.with({ $0 }) == .front {
            return self.frontDevice
        } else {
            return self.backDevice
        }
    }

    private func configureSession() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        guard !self.isConfigured, !self.isInvalidated else {
            return
        }

        self.session.beginConfiguration()
        self.session.sessionPreset = .inputPriority
        var videoConfigured: Bool
        if self.useMultiCam {
            videoConfigured = self.configureMultiCamVideo()
        } else {
            videoConfigured = self.configureSingleCameraVideo(position: self.positionValue.with { $0 }, addOutput: true)
        }
        let audioConfigured = !self.configuration.audio || self.configureAudio()
        self.session.commitConfiguration()
        self.configureVideoStabilization()
        if videoConfigured && !self.useMultiCam, let activeDevice = self.activeDevice, let singleVideoInput = self.singleVideoInput {
            self.configureFrameRate(roundVideoCaptureFrameRate, device: activeDevice, input: singleVideoInput, updateInputOverride: false)
        }
        if videoConfigured && self.useMultiCam {
            videoConfigured = self.configureSupportedMultiCamCosts()
        }
        self.logCaptureState(reason: "configured")

        self.isConfigured = videoConfigured && audioConfigured
        let initializationStatus: CaptureInitializationStatus
        if !videoConfigured {
            initializationStatus = .failed(.videoRecorderInitializationError)
        } else if !audioConfigured {
            initializationStatus = .failed(.audioInitializationError)
        } else {
            initializationStatus = .ready
        }
        let _ = self.captureInitializationStatus.modify { _ in initializationStatus }
        self.log?("configureSession: videoConfigured=\(videoConfigured) posValue=\(self.positionValue.with { $0 }.rawValue) activeDevicePos=\(self.activeDevice?.position.rawValue ?? -1) singleMediaPos=\(self.singleMediaPosition.rawValue) initStatus=\(String(describing: initializationStatus))")
        if !self.isConfigured {
            self.tearDownSession()
            if case let .failed(error) = initializationStatus {
                self.mediaQueue.async { [weak self] in
                    self?.recorder?.failInitialization(error)
                }
            }
        }
        if let activeDevice = self.activeDevice {
            self.updateZoomLimits(for: activeDevice)
            self.applyZoomScale(self.initialZoom)
        }
        self.updateActiveDeviceState()
        DispatchQueue.main.async { [weak self] in
            self?.previewView?.updateOrientation()
            self?.secondaryPreviewView?.updateOrientation()
        }
    }

    private func configureSingleCameraVideo(position: Camera.Position, addOutput: Bool) -> Bool {
        guard var device = self.makeVideoDevice(position: position) else {
            self.log?("configureSingleCameraVideo: no device for pos=\(position.rawValue)")
            return false
        }
        if !self.configureCaptureFormat(device: device) {
            self.log?("configureSingleCameraVideo: configureCaptureFormat failed for \(device.deviceType.rawValue) pos=\(position.rawValue), trying wideAngle fallback")
            if let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), self.configureCaptureFormat(device: fallback) {
                device = fallback
            } else {
                self.log?("configureSingleCameraVideo: wideAngle fallback also failed for pos=\(position.rawValue)")
                return false
            }
        }
        self.log?("configureSingleCameraVideo: requestedPos=\(position.rawValue) selected=\(device.deviceType.rawValue) devicePos=\(device.position.rawValue)")

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: device)
        } catch {
            return false
        }
        guard self.session.canAddInput(videoInput) else {
            return false
        }
        self.session.addInput(videoInput)
        self.configureFrameRate(roundVideoCaptureFrameRate, device: device, input: videoInput)

        if addOutput {
            guard let output = self.makeVideoOutput(), self.session.canAddOutput(output) else {
                self.session.removeInput(videoInput)
                return false
            }
            self.session.addOutput(output)
            self.primaryVideoOutput = output
        }

        self.singleVideoInput = videoInput
        if position == .front {
            self.frontDevice = device
        } else {
            self.backDevice = device
            self.backWideCapture = (device, device.activeFormat)
            if #available(iOS 13.0, *),
               let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
               let format = roundVideoCaptureFormat(for: ultraWide, requiresMultiCam: false, mode: self.roundVideoMode) {
                self.backUltraWideCapture = (ultraWide, format)
            }
        }
        return true
    }

    private func configureMultiCamVideo() -> Bool {
        guard #available(iOS 13.0, *),
              let multiCamSession = self.session as? AVCaptureMultiCamSession,
              let backDevice = self.makeVideoDevice(position: .back),
              let frontDevice = self.makeVideoDevice(position: .front) else {
            return false
        }
        guard self.configureCaptureFormat(device: backDevice), self.configureCaptureFormat(device: frontDevice) else {
            return false
        }

        guard let backInput = try? AVCaptureDeviceInput(device: backDevice),
              let frontInput = try? AVCaptureDeviceInput(device: frontDevice),
              multiCamSession.canAddInput(backInput),
              multiCamSession.canAddInput(frontInput),
              let backOutput = self.makeVideoOutput(),
              let frontOutput = self.makeVideoOutput(),
              multiCamSession.canAddOutput(backOutput),
              multiCamSession.canAddOutput(frontOutput) else {
            return false
        }

        multiCamSession.addInputWithNoConnections(backInput)
        multiCamSession.addInputWithNoConnections(frontInput)
        self.configureFrameRate(roundVideoCaptureFrameRate, device: backDevice, input: backInput)
        self.configureFrameRate(roundVideoCaptureFrameRate, device: frontDevice, input: frontInput)
        multiCamSession.addOutputWithNoConnections(backOutput)
        multiCamSession.addOutputWithNoConnections(frontOutput)

        guard self.connectVideo(
            input: backInput,
            output: backOutput,
            previewView: self.previewView,
            mirrored: false
        ), self.connectVideo(
            input: frontInput,
            output: frontOutput,
            previewView: self.secondaryPreviewView,
            mirrored: true
        ) else {
            return false
        }

        self.backDevice = backDevice
        self.frontDevice = frontDevice
        self.backVideoInput = backInput
        self.frontVideoInput = frontInput
        self.primaryVideoOutput = backOutput
        self.secondaryVideoOutput = frontOutput
        let _ = self.secondaryVideoOutputIdentity.modify { _ in ObjectIdentifier(frontOutput) }
        return true
    }

    @available(iOS 13.0, *)
    private func connectVideo(
        input: AVCaptureDeviceInput,
        output: AVCaptureVideoDataOutput,
        previewView: CameraPreviewView?,
        mirrored: Bool
    ) -> Bool {
        let videoPorts = input.ports.filter { $0.mediaType == .video }
        guard !videoPorts.isEmpty else {
            return false
        }

        let outputConnection = AVCaptureConnection(inputPorts: videoPorts, output: output)
        outputConnection.automaticallyAdjustsVideoMirroring = false
        if outputConnection.isVideoMirroringSupported {
            outputConnection.isVideoMirrored = false
        }
        guard self.session.canAddConnection(outputConnection) else {
            return false
        }
        self.session.addConnection(outputConnection)

        if let previewView, let port = videoPorts.first {
            let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewView.videoPreviewLayer)
            previewConnection.automaticallyAdjustsVideoMirroring = false
            if previewConnection.isVideoMirroringSupported {
                previewConnection.isVideoMirrored = mirrored
            }
            guard self.session.canAddConnection(previewConnection) else {
                return false
            }
            self.session.addConnection(previewConnection)
        }
        return true
    }

    private func configureAudio() -> Bool {
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: audioDevice) else {
            return false
        }
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: self.mediaQueue)

        if self.useMultiCam, #available(iOS 13.0, *), let multiCamSession = self.session as? AVCaptureMultiCamSession {
            guard multiCamSession.canAddInput(input), multiCamSession.canAddOutput(output) else {
                return false
            }
            multiCamSession.addInputWithNoConnections(input)
            multiCamSession.addOutputWithNoConnections(output)
            let audioPorts = input.ports.filter { $0.mediaType == .audio }
            guard !audioPorts.isEmpty else {
                return false
            }
            let connection = AVCaptureConnection(inputPorts: audioPorts, output: output)
            guard multiCamSession.canAddConnection(connection) else {
                return false
            }
            multiCamSession.addConnection(connection)
        } else {
            guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                return false
            }
            self.session.addInput(input)
            self.session.addOutput(output)
        }

        self.audioInput = input
        self.audioOutput = output
        let _ = self.audioOutputIdentity.modify { _ in ObjectIdentifier(output) }
        return true
    }

    private func makeVideoOutput() -> AVCaptureVideoDataOutput? {
        let output = AVCaptureVideoDataOutput()
        let formats = output.availableVideoPixelFormatTypes
        let pixelFormat: OSType
        if formats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        } else if formats.contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        } else {
            return nil
        }
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: self.mediaQueue)
        return output
    }

    private func makeVideoDevice(position: Camera.Position) -> AVCaptureDevice? {
        if #available(iOS 13.0, *), position == .back && !self.useMultiCam {
            if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
                return device
            } else if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
                return device
            }
        }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func configureCaptureFormat(device: AVCaptureDevice) -> Bool {
        guard let selectedFormat = roundVideoCaptureFormat(for: device, requiresMultiCam: self.useMultiCam, mode: self.roundVideoMode) else {
            return false
        }
        return self.applyCaptureFormat(selectedFormat, device: device)
    }

    private func applyCaptureFormat(_ format: AVCaptureDevice.Format, device: AVCaptureDevice, zoomFactor: CGFloat? = nil) -> Bool {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.activeFormat = format
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = roundVideoCaptureFrameRate <= 30.0
            }
            if roundVideoCaptureFrameRate > 30.0 || device.position == .front {
                if device.automaticallyAdjustsVideoHDREnabled {
                    device.automaticallyAdjustsVideoHDREnabled = false
                }
                if device.isVideoHDREnabled {
                    device.isVideoHDREnabled = false
                }
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.position == .back {
                device.videoZoomFactor = self.clampedZoom(zoomFactor ?? self.neutralZoomFactor(for: device), device: device)
            }
            return true
        } catch {
            return false
        }
    }

    private func configureSupportedMultiCamCosts() -> Bool {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        guard #available(iOS 13.0, *), let session = self.session as? AVCaptureMultiCamSession,
              let backDevice = self.backDevice, let frontDevice = self.frontDevice,
              let backInput = self.backVideoInput, let frontInput = self.frontVideoInput else {
            return false
        }

        let initialProfile: RoundVideoCaptureProfile = self.roundVideoMode == .vga ? .vga : .high
        for maximumProfile in RoundVideoCaptureProfile.allCases where maximumProfile.rawValue >= initialProfile.rawValue {
            if maximumProfile != initialProfile {
                guard let backFormat = roundVideoCaptureFormat(for: backDevice, requiresMultiCam: true, mode: self.roundVideoMode, maximumProfile: maximumProfile),
                      let frontFormat = roundVideoCaptureFormat(for: frontDevice, requiresMultiCam: true, mode: self.roundVideoMode, maximumProfile: maximumProfile) else {
                    continue
                }
                session.beginConfiguration()
                let backConfigured = self.applyCaptureFormat(backFormat, device: backDevice)
                let frontConfigured = self.applyCaptureFormat(frontFormat, device: frontDevice)
                self.configureFrameRate(roundVideoCaptureFrameRate, device: backDevice, input: backInput)
                self.configureFrameRate(roundVideoCaptureFrameRate, device: frontDevice, input: frontInput)
                session.commitConfiguration()
                guard backConfigured && frontConfigured else {
                    return false
                }
                self.configureVideoStabilization()
            }
            self.logCaptureState(reason: "MultiCam budget")
            if roundVideoCaptureCostsAreSupported(hardwareCost: session.hardwareCost, systemPressureCost: session.systemPressureCost) {
                return true
            }
        }
        return false
    }

    private func configureFrameRate(_ fps: Double, device: AVCaptureDevice, input: AVCaptureDeviceInput, updateInputOverride: Bool = true) {
        guard let duration = roundVideoFrameDuration(fps, format: device.activeFormat) else {
            return
        }
        self.withLockedDevice(device) { device in
            if #available(iOS 18.0, *), device.activeFormat.isAutoVideoFrameRateSupported, device.isAutoVideoFrameRateEnabled {
                device.isAutoVideoFrameRateEnabled = false
            }
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        if updateInputOverride {
            input.videoMinFrameDurationOverride = duration
        }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let ranges = device.activeFormat.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: ",")
        let fpsMsg = "configureFrameRate: pos=\(device.position.rawValue) dims=\(dims.width)x\(dims.height) targetFps=\(fps) effectiveFps=\(1.0 / duration.seconds) ranges=[\(ranges)]"
        os_log("%{public}@", log: cameraCaptureLog, type: .info, fpsMsg)
        self.log?(fpsMsg)
    }

    private func configureVideoStabilization() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        self.stabilizationObservers.removeAll()
        for (output, device) in [
            (self.primaryVideoOutput, self.useMultiCam ? self.backDevice : self.activeDevice),
            (self.secondaryVideoOutput, self.frontDevice)
        ] {
            guard let connection = output?.connection(with: .video), let device else {
                continue
            }
            let supportsStandard = device.position == .back && connection.isVideoStabilizationSupported && device.activeFormat.isVideoStabilizationModeSupported(.standard)
            connection.preferredVideoStabilizationMode = supportsStandard ? .standard : .off
            self.stabilizationObservers.append(connection.observe(\.activeVideoStabilizationMode, options: [.new]) { [weak self, weak connection] _, _ in
                self?.sessionQueue.async { [weak self, weak connection] in
                    guard let self, let connection,
                          connection === self.primaryVideoOutput?.connection(with: .video) || connection === self.secondaryVideoOutput?.connection(with: .video) else {
                        return
                    }
                    self.logCaptureState(reason: "stabilization changed")
                }
            })
        }
    }

    private func logCaptureState(reason: String) {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        for (output, device, preview) in [
            (self.primaryVideoOutput, self.useMultiCam ? self.backDevice : self.activeDevice, self.previewView),
            (self.secondaryVideoOutput, self.frontDevice, self.secondaryPreviewView)
        ] {
            guard let connection = output?.connection(with: .video), let device else {
                continue
            }
            let format = device.activeFormat
            let maxFormatFps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0.0
            let minDuration = device.activeVideoMinFrameDuration.seconds
            let effectiveFps = minDuration > 0.0 ? (1.0 / minDuration) : 0.0
            let previewMode = preview?.videoPreviewLayer.connection?.activeVideoStabilizationMode.rawValue ?? -1
            let centerStage = AVCaptureDevice.isCenterStageEnabled
            let portrait = AVCaptureDevice.isPortraitEffectEnabled
            let message = "\(reason): mode=\(self.roundVideoMode.rawValue), position=\(device.position.rawValue), format=\(format), maxFormatFps=\(maxFormatFps), effectiveFps=\(effectiveFps), frameDuration=\(minDuration), standardSupported=\(format.isVideoStabilizationModeSupported(.standard)), requested=\(connection.preferredVideoStabilizationMode.rawValue), active=\(connection.activeVideoStabilizationMode.rawValue), previewActive=\(previewMode), zoom=\(device.videoZoomFactor), upscaleThreshold=\(format.videoZoomFactorUpscaleThreshold), hdr=\(device.isVideoHDREnabled), centerStage=\(centerStage), portrait=\(portrait)"
            os_log("%{public}@", log: cameraCaptureLog, type: .info, message)
            self.log?(message)
        }
        if #available(iOS 13.0, *), let session = self.session as? AVCaptureMultiCamSession {
            let message = "\(reason): hardwareCost=\(session.hardwareCost), systemPressureCost=\(session.systemPressureCost)"
            os_log("%{public}@", log: cameraCaptureLog, type: .info, message)
            self.log?(message)
        }
    }

    private func switchSingleCamera(to position: Camera.Position, generation: Int) {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        self.applyDigitalZoom(1.0, position: position)
        self.session.beginConfiguration()
        if let singleVideoInput = self.singleVideoInput {
            self.session.removeInput(singleVideoInput)
        }
        self.singleVideoInput = nil
        let configured = self.configureSingleCameraVideo(position: position, addOutput: false)
        self.session.commitConfiguration()
        self.configureVideoStabilization()
        if configured, let activeDevice = self.activeDevice, let singleVideoInput = self.singleVideoInput {
            self.configureFrameRate(roundVideoCaptureFrameRate, device: activeDevice, input: singleVideoInput, updateInputOverride: false)
        }
        self.logCaptureState(reason: "camera switched")

        if !configured {
            let error = CameraRecordingError.videoRecorderInitializationError
            let _ = self.captureInitializationStatus.modify { _ in .failed(error) }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.tearDownSession()
            self.mediaQueue.async { [weak self] in
                self?.recorder?.noteSingleCameraSwitchCommitted(generation: generation)
                self?.singleFramesEnabled = false
                self?.recorder?.failInitialization(error)
            }
            self.updateActiveDeviceState()
            return
        }

        self.mediaQueue.async { [weak self] in
            self?.recorder?.noteSingleCameraSwitchCommitted(generation: generation)
            self?.singleMediaPosition = position
            self?.singleFramesEnabled = true
        }
        if let activeDevice = self.activeDevice {
            self.updateZoomLimits(for: activeDevice)
            self.applyZoomScale(1.0)
        }
        self.updateActiveDeviceState()
        // The new input gives the preview a new connection, which starts in portrait (not the body's orientation on
        // iPhone Duo's inner screen).
        DispatchQueue.main.async { [weak self] in
            self?.previewView?.updateOrientation()
        }
    }

    private func updateActiveDeviceState() {
        guard let device = self.activeDevice else {
            self.hasTorchPromise.set(false)
            self.isFlashActivePromise.set(false)
            return
        }
        self.hasTorchPromise.set(device.hasTorch && device.isTorchAvailable)
        self.isFlashActivePromise.set(device.torchMode == .on)
    }

    private func switchBackLens(to capture: (device: AVCaptureDevice, format: AVCaptureDevice.Format), zoomFactor: CGFloat) {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        guard let existing = self.singleVideoInput, let newInput = try? AVCaptureDeviceInput(device: capture.device) else {
            return
        }
        self.session.beginConfiguration()
        self.session.removeInput(existing)
        if self.session.canAddInput(newInput) {
            self.session.addInput(newInput)
            if self.applyCaptureFormat(capture.format, device: capture.device, zoomFactor: zoomFactor) {
                self.configureFrameRate(roundVideoCaptureFrameRate, device: capture.device, input: newInput)
                self.singleVideoInput = newInput
                self.backDevice = capture.device
            } else {
                self.session.removeInput(newInput)
            }
        }
        if self.singleVideoInput === existing, self.session.canAddInput(existing) {
            self.session.addInput(existing)
            self.configureFrameRate(roundVideoCaptureFrameRate, device: existing.device, input: existing)
        }
        self.session.commitConfiguration()
        self.configureVideoStabilization()
        self.updateActiveDeviceState()
        self.logCaptureState(reason: "rear lens selection: requested=\(capture.device.deviceType.rawValue) active=\(self.backDevice?.deviceType.rawValue ?? "none")")
        DispatchQueue.main.async { [weak self] in
            self?.previewView?.updateOrientation()
        }
    }

    private func applyDigitalZoom(_ zoom: CGFloat, position: Camera.Position) {
        let clamped = Float(max(1.0, zoom))
        if position == .front {
            let _ = self.frontDigitalZoom.swap(clamped)
        } else {
            let _ = self.backDigitalZoom.swap(clamped)
        }
        let scale = CGFloat(clamped)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.useMultiCam, let secondary = self.secondaryPreviewView, position == .front {
                secondary.setDigitalZoom(scale, for: self.session)
            } else if position == self.positionValue.with({ $0 }) {
                self.previewView?.setDigitalZoom(scale, for: self.session)
            }
        }
    }

    private func neutralZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 13.0, *) {
            let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors
            if let indexOfWideAngle = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
               indexOfWideAngle > 0, switchFactors.indices.contains(indexOfWideAngle - 1) {
                let zoomFactor = switchFactors[indexOfWideAngle - 1]
                return CGFloat(zoomFactor.doubleValue)
            }
        }
        return 1.0
    }

    private func clampedZoom(_ value: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let minimum = max(1.0, device.minAvailableVideoZoomFactor)
        let maximum = max(minimum, device.maxAvailableVideoZoomFactor)
        return min(maximum, max(minimum, value))
    }

    private func updateZoomLimits(for device: AVCaptureDevice) {
        let neutral = self.neutralZoomFactor(for: device)
        let baseFactor = max(1.0, neutral)
        let hwMax = max(1.0, device.maxAvailableVideoZoomFactor / baseFactor)
        let upscaleRaw = device.activeFormat.videoZoomFactorUpscaleThreshold
        let upscaleMax = upscaleRaw > 1.0 ? max(1.0, upscaleRaw / baseFactor) : hwMax
        let maxZoomMode = (UserDefaults.standard.object(forKey: "io.roundVideoMaxZoomMode") as? NSNumber)?.intValue ?? 1
        var effectiveMax = maxZoomMode == 0 ? min(hwMax, upscaleMax) : hwMax
        if device.position == .front {
            effectiveMax = max(2.0, effectiveMax)
        }
        self.currentMaxZoom = effectiveMax

        var levels: [Float] = []
        if device.position == .front {
            levels.append(1.0)
            let roundedMax = Float((effectiveMax * 10.0).rounded() / 10.0)
            if roundedMax > 2.2 {
                levels.append(2.0)
                levels.append(roundedMax)
            } else {
                levels.append(max(2.0, roundedMax))
            }
        } else {
            if self.backUltraWideCapture != nil {
                levels.append(0.5)
            } else if neutral > 1.0 {
                let minimum = device.minAvailableVideoZoomFactor / neutral
                if minimum < 1.0 {
                    levels.append(Float(minimum))
                }
            }
            levels.append(1.0)
            if #available(iOS 13.0, *) {
                if let wideIndex = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) {
                    for idx in (wideIndex + 1) ..< device.constituentDevices.count {
                        let factorIndex = idx - 1
                        if factorIndex >= 0 && factorIndex < device.virtualDeviceSwitchOverVideoZoomFactors.count {
                            let switchZoom = CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors[factorIndex].doubleValue) / max(1.0, neutral)
                            let rounded = Float((switchZoom * 10.0).rounded() / 10.0)
                            if rounded > 1.1 && rounded <= Float(effectiveMax) + 0.1 && !levels.contains(where: { abs($0 - rounded) < 0.15 }) {
                                levels.append(rounded)
                            }
                        }
                    }
                }
            }
            if !levels.contains(where: { $0 > 1.1 }) && effectiveMax >= 1.95 {
                levels.append(2.0)
            }
        }
        let zoomInfoMsg = "updateZoomLimits: pos=\(device.position.rawValue) hwMax=\(hwMax) upscaleMax=\(upscaleMax) mode=\(maxZoomMode) effectiveMax=\(effectiveMax) levels=\(levels)"
        os_log("%{public}@", log: cameraCaptureLog, type: .info, zoomInfoMsg)
        self.log?(zoomInfoMsg)
        self.zoomLevels = levels
    }

    private func withLockedDevice(_ device: AVCaptureDevice, _ update: (AVCaptureDevice) -> Void) {
        do {
            try device.lockForConfiguration()
            update(device)
            device.unlockForConfiguration()
        } catch {
            let errMsg = "lockForConfiguration failed: pos=\(device.position.rawValue) err=\(error.localizedDescription)"
            os_log("%{public}@", log: cameraCaptureLog, type: .error, errMsg)
            self.log?(errMsg)
        }
    }

    private func tearDownSession() {
        dispatchPrecondition(condition: .onQueue(self.sessionQueue))
        self.stabilizationObservers.removeAll()
        self.primaryVideoOutput?.setSampleBufferDelegate(nil, queue: nil)
        self.secondaryVideoOutput?.setSampleBufferDelegate(nil, queue: nil)
        self.audioOutput?.setSampleBufferDelegate(nil, queue: nil)

        self.session.beginConfiguration()
        for output in self.session.outputs {
            self.session.removeOutput(output)
        }
        for input in self.session.inputs {
            self.session.removeInput(input)
        }
        self.session.commitConfiguration()

        self.primaryVideoOutput = nil
        self.secondaryVideoOutput = nil
        self.audioOutput = nil
        let _ = self.secondaryVideoOutputIdentity.modify { _ in nil }
        let _ = self.audioOutputIdentity.modify { _ in nil }
        self.singleVideoInput = nil
        self.backVideoInput = nil
        self.frontVideoInput = nil
        self.audioInput = nil
        self.backDevice = nil
        self.frontDevice = nil
        self.backWideCapture = nil
        self.backUltraWideCapture = nil
        self.isConfigured = false
    }

    @objc private func sessionDidStartRunning(_ notification: Notification) {
        self.sessionQueue.async { [weak self] in
            self?.logCaptureState(reason: "started")
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError,
              AVError(_nsError: errorValue).code == .mediaServicesWereReset else {
            return
        }
        self.sessionQueue.async { [weak self] in
            guard let self, !self.isInvalidated else {
                return
            }
            let shouldRestart = self.wantsRunning
            let _ = self.captureInitializationStatus.modify { _ in .pending }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.tearDownSession()
            if shouldRestart {
                self.configureSession()
                if self.isConfigured {
                    self.session.startRunning()
                }
            }
        }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        self.sessionQueue.async { [weak self] in
            guard let self, self.wantsRunning, self.isConfigured, !self.isInvalidated, !self.session.isRunning else {
                return
            }
            self.session.startRunning()
        }
    }
}

extension CameraNeo: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(self.mediaQueue))
        let position: Camera.Position
        if self.useMultiCam {
            position = self.secondaryVideoOutputIdentity.with({ $0 }) == ObjectIdentifier(output) ? .front : .back
        } else {
            position = self.singleMediaPosition
        }
        self.recorder?.noteDroppedVideoSampleBuffer(sampleBuffer, position: position)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(self.mediaQueue))

        let outputIdentity = ObjectIdentifier(output)
        if self.audioOutputIdentity.with({ $0 }) == outputIdentity {
            self.recorder?.appendAudioSampleBuffer(sampleBuffer)
            return
        }

        let position: Camera.Position
        if self.useMultiCam {
            if self.secondaryVideoOutputIdentity.with({ $0 }) == outputIdentity {
                position = .front
            } else {
                position = .back
            }
        } else {
            position = self.singleMediaPosition
        }

        if !self.useMultiCam {
            if !self.singleFramesEnabled {
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
                let fpsMsg = String(format: "CameraNeo captureOutput: pos=%d deliveredFps=%.2f frames=%d elapsed=%.2fs", position.rawValue, deliveredFps, self.deliveredFrameCount, elapsed)
                os_log("%{public}@", log: cameraCaptureLog, type: .info, fpsMsg)
                self.log?(fpsMsg)
                self.deliveredFrameCount = 0
                self.deliveredFpsWindowStart = now
            }
        }

        let digitalZoom = position == .front ? self.frontDigitalZoom.with { $0 } : self.backDigitalZoom.with { $0 }
        self.recorder?.appendVideoSampleBuffer(
            sampleBuffer,
            position: position,
            orientation: self.recordingOrientation,
            digitalZoom: digitalZoom
        )

        if self.useMultiCam {
            if position == .front {
                self.additionalVideoOutput?.push(sampleBuffer, mirror: true)
            } else {
                self.mainVideoOutput?.push(sampleBuffer, mirror: false)
            }
        } else {
            self.mainVideoOutput?.push(sampleBuffer, mirror: position == .front)
        }
    }

}
