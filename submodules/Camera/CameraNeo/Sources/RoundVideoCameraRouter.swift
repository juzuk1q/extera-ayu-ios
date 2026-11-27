import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import DeviceModel
import Camera

public final class RoundVideoCameraRouter: CameraImpl {
    private let backEngine: NeoCameraImpl
    private let frontEngine: FrontRoundCameraImpl
    private let log: ((String) -> Void)?

    public init(roundVideoMode: NeoCameraImpl.RoundVideoMode = .hdBilinear, log: ((String) -> Void)? = nil) {
        self.log = log
        self.backEngine = NeoCameraImpl(roundVideoMode: roundVideoMode, log: log)
        self.frontEngine = FrontRoundCameraImpl(roundVideoMode: roundVideoMode, log: log)
    }

    public var isIpad: Bool {
        return DeviceModel.current.isIpad
    }

    public func isDualCameraSupported(forRoundVideo: Bool) -> Bool {
        return false
    }

    public func makeCameraSimplePreviewView(frame: CGRect, main: Bool, roundVideo: Bool) -> CameraSimplePreviewView {
        return CameraPreviewView(frame: frame, main: main, roundVideo: roundVideo)
    }

    public func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?
    ) -> CameraProtocol {
        return RoundVideoRoutedCamera(
            configuration: configuration,
            previewView: previewView,
            secondaryPreviewView: secondaryPreviewView,
            backEngine: self.backEngine,
            frontEngine: self.frontEngine,
            log: self.log
        )
    }
}

private final class RoundVideoRoutedCamera: CameraProtocol {
    private let backEngine: NeoCameraImpl
    private let frontEngine: FrontRoundCameraImpl
    private let previewView: CameraSimplePreviewView?
    private let secondaryPreviewView: CameraSimplePreviewView?
    private let log: ((String) -> Void)?

    private var baseConfiguration: Camera.Configuration
    private var currentPosition: Camera.Position
    private var currentEngine: CameraProtocol
    private var mainVideoOutput: CameraVideoOutput?
    private var currentFlashMode: Camera.FlashMode = .off
    private var isCapturing = false
    private let isRecordingActive = Atomic<Bool>(value: false)
    private let holdsCenterStageSuppression: Bool

    private let positionPromise: ValuePromise<Camera.Position>
    private let flashModePromise = ValuePromise<Camera.FlashMode>(.off)
    private let hasTorchPromise = Promise<Bool>()
    private let isFlashActivePromise = Promise<Bool>()
    private let zoomStatePromise = Promise<CameraZoomState>()
    private let transitionImagePromise = Promise<UIImage?>()
    private let modeChangePromise = Promise<Camera.ModeChange>()
    private let detectedCodesPromise = Promise<[CameraCode]>()
    private let audioLevelPromise = Promise<Float>()

    var metrics: Camera.Metrics {
        return self.currentEngine.metrics
    }

    init(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?,
        backEngine: NeoCameraImpl,
        frontEngine: FrontRoundCameraImpl,
        log: ((String) -> Void)?
    ) {
        self.baseConfiguration = configuration
        self.currentPosition = configuration.position
        self.previewView = previewView
        self.secondaryPreviewView = secondaryPreviewView
        self.backEngine = backEngine
        self.frontEngine = frontEngine
        self.log = log
        self.holdsCenterStageSuppression = configuration.isRoundVideo
        self.positionPromise = ValuePromise<Camera.Position>(configuration.position)

        if self.holdsCenterStageSuppression {
            RoundVideoCenterStageSuppression.acquire()
        }

        let engine: CameraImpl = configuration.position == .front ? frontEngine : backEngine
        self.currentEngine = engine.makeCamera(
            configuration: configuration,
            previewView: previewView,
            secondaryPreviewView: secondaryPreviewView
        )
        self.log?("RoundVideoCameraRouter.init: initialPosition=\(configuration.position.rawValue) engine=\(configuration.position == .front ? "FrontRound" : "NeoBack")")
        self.bindSignals(from: self.currentEngine)
    }

    deinit {
        if self.holdsCenterStageSuppression {
            RoundVideoCenterStageSuppression.release()
        }
    }

    private func bindSignals(from engine: CameraProtocol) {
        self.hasTorchPromise.set(engine.hasTorch)
        self.isFlashActivePromise.set(engine.isFlashActive)
        self.zoomStatePromise.set(engine.zoomState)
        self.transitionImagePromise.set(engine.transitionImage)
        self.modeChangePromise.set(engine.modeChange)
        self.detectedCodesPromise.set(engine.detectedCodes)
        self.audioLevelPromise.set(engine.audioLevel)
    }

    func startCapture() {
        self.isCapturing = true
        self.currentEngine.startCapture()
    }

    func stopCapture(invalidate: Bool) {
        self.isCapturing = false
        if invalidate {
            let _ = self.isRecordingActive.modify { _ in false }
        }
        self.currentEngine.stopCapture(invalidate: invalidate)
    }

    var position: Signal<Camera.Position, NoError> {
        return self.positionPromise.get()
    }

    func togglePosition() {
        self.setPosition(self.currentPosition == .front ? .back : .front)
    }

    func setPosition(_ position: Camera.Position) {
        guard position != self.currentPosition else {
            return
        }
        guard !self.isRecordingActive.with({ $0 }) else {
            self.log?("RoundVideoCameraRouter: flip ignored during active recording to protect file integrity")
            return
        }

        self.log?("RoundVideoCameraRouter: switching \(self.currentPosition.rawValue) -> \(position.rawValue)")
        self.currentEngine.stopCapture(invalidate: true)

        if let preview = self.previewView as? CameraPreviewView {
            if Thread.isMainThread {
                preview.setDigitalZoom(1.0)
            } else {
                DispatchQueue.main.async {
                    preview.setDigitalZoom(1.0)
                }
            }
        }

        self.currentPosition = position
        let nextConfig = Camera.Configuration(
            preset: self.baseConfiguration.preset,
            position: position,
            isDualEnabled: false,
            audio: self.baseConfiguration.audio,
            photo: self.baseConfiguration.photo,
            metadata: self.baseConfiguration.metadata,
            preferWide: self.baseConfiguration.preferWide,
            preferLowerFramerate: self.baseConfiguration.preferLowerFramerate,
            reportAudioLevel: self.baseConfiguration.reportAudioLevel,
            isRoundVideo: self.baseConfiguration.isRoundVideo,
            captureMode: self.baseConfiguration.captureMode
        )
        let impl: CameraImpl = position == .front ? self.frontEngine : self.backEngine
        let nextEngine = impl.makeCamera(
            configuration: nextConfig,
            previewView: self.previewView,
            secondaryPreviewView: self.secondaryPreviewView
        )
        if let mainVideoOutput = self.mainVideoOutput {
            nextEngine.setMainVideoOutput(mainVideoOutput)
        }
        nextEngine.setFlashMode(self.currentFlashMode)
        self.currentEngine = nextEngine
        self.bindSignals(from: nextEngine)
        self.positionPromise.set(position)

        if self.isCapturing {
            nextEngine.startCapture()
        }
    }

    func setDualCameraEnabled(_ enabled: Bool) {
    }

    func setCaptureMode(_ mode: CameraCaptureMode) -> Signal<Void, NoError> {
        return self.currentEngine.setCaptureMode(mode)
    }

    func takePhoto() -> Signal<PhotoCaptureResult, NoError> {
        return self.currentEngine.takePhoto()
    }

    private func wrapRecordingSignal(_ signal: Signal<CameraRecordingData, CameraRecordingError>) -> Signal<CameraRecordingData, CameraRecordingError> {
        let _ = self.isRecordingActive.modify { _ in true }
        return Signal { [weak self] subscriber in
            let disposable = signal.start(next: { next in
                subscriber.putNext(next)
            }, error: { [weak self] error in
                let _ = self?.isRecordingActive.modify { _ in false }
                subscriber.putError(error)
            }, completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
            }
        }
    }

    func startRecording() -> Signal<CameraRecordingData, CameraRecordingError> {
        return self.wrapRecordingSignal(self.currentEngine.startRecording())
    }

    func startRecording(captureMode: CameraCaptureMode) -> Signal<CameraRecordingData, CameraRecordingError> {
        return self.wrapRecordingSignal(self.currentEngine.startRecording(captureMode: captureMode))
    }

    func stopRecording() -> Signal<VideoCaptureResult, NoError> {
        return self.currentEngine.stopRecording()
        |> afterCompleted { [weak self] in
            let _ = self?.isRecordingActive.modify { _ in false }
        }
    }

    func focus(at point: CGPoint, autoFocus: Bool) {
        self.currentEngine.focus(at: point, autoFocus: autoFocus)
    }

    func setFps(_ fps: Double) {
        self.currentEngine.setFps(fps)
    }

    func setFlashMode(_ flashMode: Camera.FlashMode) {
        self.currentFlashMode = flashMode
        self.flashModePromise.set(flashMode)
        self.currentEngine.setFlashMode(flashMode)
    }

    func setZoomLevel(_ zoomLevel: CGFloat) {
        self.currentEngine.setZoomLevel(zoomLevel)
    }

    func setZoomDelta(_ zoomDelta: CGFloat) {
        self.currentEngine.setZoomDelta(zoomDelta)
    }

    func setZoomScale(_ zoomScale: CGFloat) {
        self.currentEngine.setZoomScale(zoomScale)
    }

    func beginExposureTargetBiasChange() {
        self.currentEngine.beginExposureTargetBiasChange()
    }

    func setExposureTargetBias(_ bias: CGFloat) {
        self.currentEngine.setExposureTargetBias(bias)
    }

    func endExposureTargetBiasChange() {
        self.currentEngine.endExposureTargetBiasChange()
    }

    func rampZoom(_ zoomLevel: CGFloat, rate: CGFloat) {
        self.currentEngine.rampZoom(zoomLevel, rate: rate)
    }

    func setTorchActive(_ active: Bool) {
        self.currentEngine.setTorchActive(active)
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
        self.mainVideoOutput = output
        self.currentEngine.setMainVideoOutput(output)
    }

    func setAdditionalVideoOutput(_ output: CameraVideoOutput?) {
        self.currentEngine.setAdditionalVideoOutput(output)
    }

    func attachSimplePreviewView(_ view: CameraSimplePreviewView) {
        self.currentEngine.attachSimplePreviewView(view)
    }

    var detectedCodes: Signal<[CameraCode], NoError> {
        return self.detectedCodesPromise.get()
    }

    var audioLevel: Signal<Float, NoError> {
        return self.audioLevelPromise.get()
    }

    var transitionImage: Signal<UIImage?, NoError> {
        return self.transitionImagePromise.get()
    }

    var modeChange: Signal<Camera.ModeChange, NoError> {
        return self.modeChangePromise.get()
    }
}
