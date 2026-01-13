//
//  ScreenCapture.swift
//  MonitorWatch
//
//  Captures screenshot of the current screen using CGWindowListCreateImage (macOS 13+)
//

import Cocoa
import ScreenCaptureKit

class ScreenCapture {
    
    /// Capture the current screen
    func capture() async -> NSImage? {
        // Use CGWindowListCreateImage for broader macOS support
        // This doesn't require the newer ScreenCaptureKit APIs
        
        guard let screenFrame = NSScreen.main?.frame else {
            return nil
        }
        
        // Capture at half resolution for efficiency
        let captureRect = CGRect(
            x: screenFrame.origin.x,
            y: screenFrame.origin.y,
            width: screenFrame.width,
            height: screenFrame.height
        )
        
        // Create the screenshot
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            print("ScreenCapture: Failed to create image")
            return nil
        }
        
        // Scale down to half resolution for efficiency
        let scaledWidth = cgImage.width / 2
        let scaledHeight = cgImage.height / 2
        
        guard let context = CGContext(
            data: nil,
            width: scaledWidth,
            height: scaledHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            // Return original size if scaling fails
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        
        if let scaledImage = context.makeImage() {
            return NSImage(cgImage: scaledImage, size: NSSize(width: scaledWidth, height: scaledHeight))
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
