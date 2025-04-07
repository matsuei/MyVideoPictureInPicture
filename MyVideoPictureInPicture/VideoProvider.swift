//
//  VideoProvider.swift
//  MyVideoPictureInPicture
//
//  Created by Kenta Matsue on 2025/04/07.
//

import UIKit
import AVKit
import AVFoundation

class VideoProvider: NSObject {

    private var timer: Timer!
    var bufferDisplayLayer = AVSampleBufferDisplayLayer()

    var imaga: UIImageView?

    func start() {
        let timerBlock: ((Timer) -> Void) = { [weak self] timer in
            guard let self = self else { return }
            if (self.bufferDisplayLayer.status == .failed) {
                self.bufferDisplayLayer.flush()
            }

            guard let buffer = self.imaga?.makeSampleBuffer() else { return }
            self.bufferDisplayLayer.enqueue(buffer)
        }

        timer = Timer(timeInterval: 0.3, repeats: true, block: timerBlock)
        RunLoop.main.add(timer, forMode: .default)
    }

    func stop() {
        if timer != nil {
            timer.invalidate()
            timer = nil
        }
    }

    func isRunning() -> Bool {
        return timer != nil
    }
}


extension UIView {
    func makeSampleBuffer() -> CMSampleBuffer? {
        let scale = UIScreen.main.scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        var pixelBuffer: CVPixelBuffer?
        var status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32ARGB,
                                         [
                                             kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                                             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                                             kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                                         ] as CFDictionary,
                                         &pixelBuffer)
        if status != kCVReturnSuccess {
            assertionFailure("Failed to create CVPixelBuffer: \(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer!, [])
        }

        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer!),
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)

        var formatDescription: CMFormatDescription?
        status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                              imageBuffer: pixelBuffer!,
                                                              formatDescriptionOut: &formatDescription)
        if status != kCVReturnSuccess {
            assertionFailure("Failed to create CMFormatDescription: \(status)")
            return nil
        }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60)
        let timingInfo = CMSampleTimingInfo(duration: .init(seconds: 1, preferredTimescale: 60),
                                            presentationTimeStamp: now,
                                            decodeTimeStamp: now)
        do {
            return try CMSampleBuffer(imageBuffer: pixelBuffer!, formatDescription: formatDescription!,
                                      sampleTiming: timingInfo)
        } catch {
            assertionFailure("Failed to create CVSampleBuffer: \(error)")
            return nil
        }
    }
}
