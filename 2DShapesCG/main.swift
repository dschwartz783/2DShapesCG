//
//  main.swift
//  2DShapesCG
//
//  Created by David Schwartz on 5/26/17.
//  Copyright © 2017 DDS Programming. All rights reserved.
//

import Cocoa

let args = ProcessInfo.processInfo.arguments

guard args.count == 2 || args.count == 3 else {
    FileHandle.standardError.write("usage: \(args[0]) <points> [animate]\n".data(using: .utf8)!)
    exit(1)
}

guard let points = Int(args[1]) else {
    FileHandle.standardError.write("Points must be an integer\n".data(using: .utf8)!)
    exit(1)
}

let shouldAnimate: Bool!

if args.count >= 3 {
    shouldAnimate = Bool(args[2])
    guard shouldAnimate != nil else {
        FileHandle.standardError.write("Animate should either be true or false\n".data(using: .utf8)!)
        exit(1)
    }
} else {
    shouldAnimate = false
}

let displaySize = CGDisplayBounds(CGMainDisplayID())
let displayMeasure = CGDisplayScreenSize(CGMainDisplayID())

// some pretty fade effect

var reservation: CGDisplayFadeReservationToken = 0
CGAcquireDisplayFadeReservation(2, &reservation)
CGDisplayFade(reservation, 2, 0, 1, 0, 0, 0, 0)

usleep(UInt32(Double(USEC_PER_SEC) * 1.75))

CGDisplayCapture(CGMainDisplayID())

let drawingContext: CGContext! = CGDisplayGetDrawingContext(CGMainDisplayID())

if drawingContext == nil {
    
    FileHandle.standardError.write("Could not get drawing context\n".data(using: .utf8)!)
    
    exit(1)
}

drawingContext.setAllowsAntialiasing(true)
drawingContext.setLineWidth(displayMeasure.width / displaySize.width * 2)

let smallerDimension = (displaySize.height < displaySize.width) ? displaySize.height : displaySize.width

/**
 * rotInc determines the increment at which the shape will rotate. Too fast, and it looks like lines, too slow and it looks like a single circle
 * This value seems to produce the best result
 */

let rotInc = (2 * Float80.pi / Float80(points) / (Float80.pi * 100))

var centerX = displaySize.midX
var centerY = displaySize.midY

var shouldPause = false

let drawThread = DispatchQueue(label: "DrawThread")
let calcThread = DispatchQueue(label: "CalcThread",
                               attributes: .concurrent)

DispatchQueue.global().async {
    
    var hasRun = false
    
    while shouldAnimate ? true : !hasRun {
        
        // allows the loop to run only once if shouldAnimate is false
        
        hasRun = true
        
        let currentStrokeColor = NSColor(deviceRed: CGFloat(arc4random()) / CGFloat(UInt32.max),
                                         green: CGFloat(arc4random()) / CGFloat(UInt32.max),
                                         blue: CGFloat(arc4random()) / CGFloat(UInt32.max),
                                         alpha: 1).cgColor
        
        drawingContext.setStrokeColor(currentStrokeColor)
        
        for rotation in stride(
            from: 0,
            to: shouldAnimate! ? 2 * Float80.pi / Float80(points) - rotInc : rotInc,
            by: rotInc) {
                
                var lineSegments = [CGPoint]()
                
                for theta1 in stride(
                    from: 0,
                    to: 2 * Float80.pi,
                    by: 2 * Float80.pi / Float80(points)) {
                        
                        calcThread.async {
                            
                            for theta2 in stride(
                                from: theta1,
                                to: 2 * Float80.pi,
                                by: 2 * Float80.pi / Float80(points)) {
                                    
                                    let smallerDimensionCenter = Double(smallerDimension) / 2
                                    
                                    let theta1Rotated = Double(theta1 + rotation)
                                    let theta2Rotated = Double(theta2 + rotation)
                                    
                                    let centerXDouble = Double(centerX)
                                    let centerYDouble = Double(centerY)
                                    
                                    let point1 = CGPoint(
                                        x: centerXDouble + sin(theta1Rotated) * smallerDimensionCenter,
                                        y: centerYDouble + cos(theta1Rotated) * smallerDimensionCenter)
                                    let point2 = CGPoint(
                                        x: centerXDouble + sin(theta2Rotated) * smallerDimensionCenter,
                                        y: centerYDouble + cos(theta2Rotated) * smallerDimensionCenter)
                                    
                                    drawThread.async {
                                        lineSegments += [
                                            point1,
                                            point2
                                        ]
                                    }
                            }
                        }
                }
                
                calcThread.sync(flags: .barrier) {
                    drawThread.sync(flags: .barrier) {
                        drawingContext.strokeLineSegments(between: lineSegments)
                    }
                }
        }
        
        while shouldPause {
            usleep(useconds_t(USEC_PER_SEC / 4))
        }
        
    }
}

let playPauseImageLocation = CGRect(
    x: 20,
    y: 20,
    width: 100,
    height: 100)

func getImage(_ name: String) -> CGImage? {
    
    guard let imageData = Bundle.main.object(forInfoDictionaryKey: name) else {
        return nil
    }
    
    guard let imageDataAsData = imageData as? Data else {
        return nil
    }
    
    guard let srcImage = NSImage(data: imageDataAsData) else {
        return nil
    }
    
    guard let tiffRep = srcImage.tiffRepresentation else {
        return nil
    }
    
    guard let cgImageSrc = CGImageSourceCreateWithData(tiffRep as CFData, nil) else {
        return nil
    }
    
    guard let image = CGImageSourceCreateImageAtIndex(cgImageSrc, 0, nil) else {
        return nil
    }
    
    return image
}

func togglePlayPause() {
    drawThread.async {
        
        shouldPause = !shouldPause
        
        if let image = getImage(shouldPause ? "play" : "pause") {
            drawingContext.draw(image, in: playPauseImageLocation)
        }
    }
}

if let image = getImage("pause") {
    drawThread.async {
        drawingContext.draw(image, in: playPauseImageLocation)
    }
}

// tracking logic, for rotation pausing

guard let keyDownTracker = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: { (proxy, type, event, data) -> Unmanaged<CGEvent>? in
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 1: // S: Save
            guard (try? FileManager.default.createDirectory(
                atPath: NSHomeDirectory() + "/Desktop/2DShapesCGPictures",
                withIntermediateDirectories: true,
                attributes: nil)) != nil else {
                    break
            }
            
            guard let cgImage = CGDisplayCreateImage(
                CGMainDisplayID(),
                rect:CGRect(
                    x: centerX > centerY ? centerX - centerY : centerY - centerX,
                    y: 0,
                    width: centerX > centerY ? displaySize.height : displaySize.width,
                    height: centerX > centerY ? displaySize.height : displaySize.width
            )) else {
                break
            }
            
            if let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/2DShapesCGPictures/\( Date(timeIntervalSinceNow: TimeInterval(TimeZone.current.secondsFromGMT())) ).png",
                    isDirectory: false) as CFURL,
                kUTTypePNG, 1, nil) {
                
                CGImageDestinationAddImage(destination, cgImage, nil)
                CGImageDestinationFinalize(destination)
            }
            
        case 35, 49: // P: Play/Pause, Space: Play/Pause
            togglePlayPause()
            
        case 12: // Q: Quit
            exit(0)
            
        default:
            break
        }
        
        return nil
},
    userInfo: nil) else {
        FileHandle.standardError.write("Could not create keyboard tap".data(using: .utf8)!)
        exit(1)
}

guard let mouseClickTracker = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue),
    callback: { (proxy, type, event, data) -> Unmanaged<CGEvent>? in
        
        var cursorLocation = event.location
        
        cursorLocation.y = displaySize.height - cursorLocation.y
        
        if playPauseImageLocation.contains(cursorLocation) {
            togglePlayPause()
        }
        
        return nil
},
    userInfo: nil) else {
        FileHandle.standardError.write("Could not create mouse tap".data(using: .utf8)!)
        exit(1)
}

RunLoop.main.add(keyDownTracker, forMode: .defaultRunLoopMode)
RunLoop.main.add(mouseClickTracker, forMode: .defaultRunLoopMode)

RunLoop.main.run()
