import Foundation
import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import DeviceModel
import Camera

var roundVideoCaptureFrameRate: Double {
    guard UserDefaults.standard.object(forKey: "io.roundVideo60Fps") as? Bool ?? true else {
        return 30.0
    }
    if !UIDevice.current.isBatteryMonitoringEnabled {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }
    let level = UIDevice.current.batteryLevel
    if level >= 0.0 && level < 0.20 {
        return 30.0
    }
    return 60.0
}

enum RoundVideoCaptureProfile: Int, CaseIterable {
    // Budget tiers: rear uses 16:9, front uses 4:3 to retain its field of view.
    case high
    case medium
    case vga

    init?(width: Int32, height: Int32, position: AVCaptureDevice.Position) {
        switch (position, width, height) {
        case (.back, 1920, 1080),
             (.front, 1920, 1440), (.front, 1920, 1080), (.front, 1440, 1080),
             (.front, 2316, 1736), (.front, 2576, 1932), (.front, 3840, 2160):
            self = .high
        case (.back, 1280, 720),
             (.front, 1280, 960), (.front, 1280, 720), (.front, 960, 720):
            self = .medium
        case (_, 640, 480):
            self = .vga
        default:
            return nil
        }
    }
}

private struct RoundVideoCaptureFormatCandidate {
    let profile: RoundVideoCaptureProfile?
    let width: Int32
    let height: Int32
    let isNV12: Bool
    let frameRateRanges: [ClosedRange<Double>]
    let supportsMultiCam: Bool
    let supportsStandardStabilization: Bool

    func supportsFrameRate(_ fps: Double) -> Bool {
        return self.frameRateRanges.contains(where: { $0.lowerBound <= fps && $0.upperBound >= fps - 0.5 })
    }
}

private func selectRoundVideoCaptureFormat(
    _ candidates: [RoundVideoCaptureFormatCandidate],
    requiresMultiCam: Bool,
    preferStabilization: Bool,
    preferMediumProfile: Bool,
    maximumProfile: RoundVideoCaptureProfile = .high
) -> Int? {
    let targetFps = roundVideoCaptureFrameRate
    var eligible = candidates.indices.filter { index in
        let candidate = candidates[index]
        guard let profile = candidate.profile, profile.rawValue >= maximumProfile.rawValue else {
            return false
        }
        return candidate.isNV12
            && (!requiresMultiCam || candidate.supportsMultiCam)
            && candidate.supportsFrameRate(targetFps)
    }
    if eligible.isEmpty && targetFps > 30.0 && maximumProfile != .vga {
        eligible = candidates.indices.filter { index in
            let candidate = candidates[index]
            return candidate.isNV12
                && (!requiresMultiCam || candidate.supportsMultiCam)
                && min(candidate.width, candidate.height) >= 720
                && candidate.supportsFrameRate(targetFps)
        }
    }
    if eligible.isEmpty && targetFps > 30.0 {
        let bestFallbackFps = candidates.compactMap { candidate -> Double? in
            guard candidate.isNV12, (!requiresMultiCam || candidate.supportsMultiCam),
                  candidate.profile.map({ $0.rawValue >= maximumProfile.rawValue }) ?? (min(candidate.width, candidate.height) >= 720),
                  candidate.supportsFrameRate(30.0) else {
                return nil
            }
            return candidate.frameRateRanges.map(\.upperBound).max()
        }.max() ?? 30.0
        eligible = candidates.indices.filter { index in
            let candidate = candidates[index]
            let hasProfile = candidate.profile.map { $0.rawValue >= maximumProfile.rawValue } ?? false
            return hasProfile
                && candidate.isNV12
                && (!requiresMultiCam || candidate.supportsMultiCam)
                && candidate.supportsFrameRate(bestFallbackFps)
        }
        if eligible.isEmpty {
            eligible = candidates.indices.filter { index in
                let candidate = candidates[index]
                guard let profile = candidate.profile, profile.rawValue >= maximumProfile.rawValue else {
                    return false
                }
                return candidate.isNV12
                    && (!requiresMultiCam || candidate.supportsMultiCam)
                    && candidate.supportsFrameRate(30.0)
            }
        }
    }
    return eligible.min { lhsIndex, rhsIndex in
        let lhs = candidates[lhsIndex]
        let rhs = candidates[rhsIndex]
        if preferStabilization, lhs.supportsStandardStabilization != rhs.supportsStandardStabilization {
            return lhs.supportsStandardStabilization
        }
        if let lhsProfile = lhs.profile, let rhsProfile = rhs.profile, lhsProfile != rhsProfile {
            if preferMediumProfile {
                if lhsProfile == .medium {
                    return true
                }
                if rhsProfile == .medium {
                    return false
                }
            }
            return lhsProfile.rawValue < rhsProfile.rawValue
        }
        let lhsMinDim = min(lhs.width, lhs.height)
        let rhsMinDim = min(rhs.width, rhs.height)
        if lhsMinDim != rhsMinDim {
            return abs(lhsMinDim - 1080) < abs(rhsMinDim - 1080)
        }
        let lhsMaximumFps = lhs.frameRateRanges.map(\.upperBound).max() ?? 0.0
        let rhsMaximumFps = rhs.frameRateRanges.map(\.upperBound).max() ?? 0.0
        if lhsMaximumFps != rhsMaximumFps {
            return lhsMaximumFps > rhsMaximumFps
        }
        return lhsIndex < rhsIndex
    }
}

func roundVideoCaptureCostsAreSupported(hardwareCost: Float, systemPressureCost: Float) -> Bool {
    return hardwareCost.isFinite && systemPressureCost.isFinite
        && hardwareCost <= 1.0 && systemPressureCost <= 1.0
}

func roundVideoCaptureFormat(
    for device: AVCaptureDevice,
    requiresMultiCam: Bool,
    mode: NeoCameraImpl.RoundVideoMode,
    maximumProfile: RoundVideoCaptureProfile = .high
) -> AVCaptureDevice.Format? {
    let formats = device.formats
    let candidates = formats.map { format -> RoundVideoCaptureFormatCandidate in
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let supportsMultiCam: Bool
        if #available(iOS 13.0, *) {
            supportsMultiCam = format.isMultiCamSupported
        } else {
            supportsMultiCam = false
        }
        return RoundVideoCaptureFormatCandidate(
            profile: RoundVideoCaptureProfile(width: dimensions.width, height: dimensions.height, position: device.position),
            width: dimensions.width,
            height: dimensions.height,
            isNV12: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            frameRateRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate ... $0.maxFrameRate },
            supportsMultiCam: supportsMultiCam,
            supportsStandardStabilization: format.isVideoStabilizationModeSupported(.standard)
        )
    }
    guard let index = selectRoundVideoCaptureFormat(
        candidates,
        requiresMultiCam: requiresMultiCam,
        preferStabilization: mode != .vga && device.position == .back,
        preferMediumProfile: device.position == .front,
        maximumProfile: mode == .vga ? .vga : maximumProfile
    ) else {
        return nil
    }
    return formats[index]
}

private func supportsDualCameraCapture(forRoundVideo: Bool, mode: NeoCameraImpl.RoundVideoMode) -> Bool {
    guard #available(iOS 13.0, *), AVCaptureMultiCamSession.isMultiCamSupported, !DeviceModel.current.isIpad else {
        return false
    }
    if forRoundVideo && (DeviceModel.current == .iPhoneXR || roundVideoCaptureFrameRate > 30.0) {
        return false
    }
    let positions: [AVCaptureDevice.Position] = [.back, .front]
    return positions.allSatisfy { position in
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return false
        }
        return roundVideoCaptureFormat(for: device, requiresMultiCam: true, mode: mode) != nil
    }
}

public final class NeoCameraImpl: CameraImpl {
    public enum RoundVideoMode: String {
        case vga
        case hdBilinear
        case hdLanczos
    }

    public static let shared = NeoCameraImpl()

    private let roundVideoMode: RoundVideoMode
    private let log: ((String) -> Void)?

    public init(roundVideoMode: RoundVideoMode = .hdBilinear, log: ((String) -> Void)? = nil) {
        self.roundVideoMode = roundVideoMode
        self.log = log
        RoundVideoDecorationProvider.shared.warmUp()
    }

    public var isIpad: Bool {
        return DeviceModel.current.isIpad
    }

    public func isDualCameraSupported(forRoundVideo: Bool) -> Bool {
        return supportsDualCameraCapture(forRoundVideo: forRoundVideo, mode: self.roundVideoMode)
    }

    public func makeCamera(
        configuration: Camera.Configuration,
        previewView: CameraSimplePreviewView?,
        secondaryPreviewView: CameraSimplePreviewView?
    ) -> CameraProtocol {
        let cameraPreviewView: CameraPreviewView?
        if let previewView {
            guard let previewView = previewView as? CameraPreviewView else {
                preconditionFailure()
            }
            cameraPreviewView = previewView
        } else {
            cameraPreviewView = nil
        }

        let cameraSecondaryPreviewView: CameraPreviewView?
        if let secondaryPreviewView {
            guard let secondaryPreviewView = secondaryPreviewView as? CameraPreviewView else {
                preconditionFailure()
            }
            cameraSecondaryPreviewView = secondaryPreviewView
        } else {
            cameraSecondaryPreviewView = nil
        }

        return CameraNeo(
            configuration: configuration,
            previewView: cameraPreviewView,
            secondaryPreviewView: cameraSecondaryPreviewView,
            useMultiCam: configuration.isDualEnabled && self.isDualCameraSupported(forRoundVideo: configuration.isRoundVideo),
            roundVideoMode: self.roundVideoMode,
            log: self.log
        )
    }

    public func makeCameraSimplePreviewView(frame: CGRect, main: Bool, roundVideo: Bool) -> CameraSimplePreviewView {
        return CameraPreviewView(frame: frame, main: main, roundVideo: roundVideo)
    }
}
