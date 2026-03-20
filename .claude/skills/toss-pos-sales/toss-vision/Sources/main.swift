import AppKit
import Vision
import Foundation

// MARK: - Models

struct TextElement: Codable {
    let text: String
    let x: Int       // center x (screen coords)
    let y: Int       // center y (screen coords)
    let w: Int       // width
    let h: Int       // height
    let confidence: Float
}

struct FindResult: Codable {
    let text: String
    let x: Int
    let y: Int
    let found: Bool
}

struct TapResult: Codable {
    let text: String
    let x: Int
    let y: Int
    let tapped: Bool
}

// MARK: - Screen Capture

func captureRegion(_ region: CGRect?) -> CGImage? {
    if let region = region {
        return CGWindowListCreateImage(
            region,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        )
    } else {
        return CGWindowListCreateImage(
            CGRect.infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming]
        )
    }
}

func captureWindow(appName: String) -> (CGImage, CGRect)? {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []

    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String,
              ownerName == appName,
              let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"],
              let y = boundsDict["Y"],
              let w = boundsDict["Width"],
              let h = boundsDict["Height"],
              w > 100, h > 100 else { continue }

        let rect = CGRect(x: x, y: y, width: w, height: h)
        if let image = captureRegion(rect) {
            return (image, rect)
        }
    }
    return nil
}

// MARK: - OCR

func performOCR(image: CGImage, screenRect: CGRect) -> [TextElement] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])

    guard let results = request.results else { return [] }

    let imgW = CGFloat(image.width)
    let imgH = CGFloat(image.height)

    // screen pixels per image pixel
    let scaleX = screenRect.width / imgW
    let scaleY = screenRect.height / imgH

    var elements: [TextElement] = []

    for observation in results {
        guard let candidate = observation.topCandidates(1).first else { continue }

        let box = observation.boundingBox
        // Vision coordinates: origin bottom-left, normalized [0,1]
        // Convert to screen coordinates
        let pixelX = box.origin.x * imgW
        let pixelY = (1.0 - box.origin.y - box.height) * imgH
        let pixelW = box.width * imgW
        let pixelH = box.height * imgH

        let screenX = screenRect.origin.x + pixelX * scaleX
        let screenY = screenRect.origin.y + pixelY * scaleY
        let screenW = pixelW * scaleX
        let screenH = pixelH * scaleY

        let centerX = Int(screenX + screenW / 2)
        let centerY = Int(screenY + screenH / 2)

        elements.append(TextElement(
            text: candidate.string,
            x: centerX,
            y: centerY,
            w: Int(screenW),
            h: Int(screenH),
            confidence: candidate.confidence
        ))
    }

    return elements
}

// MARK: - Commands

func cmdOCR(appName: String, region: CGRect?) {
    let (image, rect): (CGImage, CGRect)

    if let region = region {
        guard let img = captureRegion(region) else {
            printError("Failed to capture region")
            return
        }
        image = img
        rect = region
    } else {
        guard let result = captureWindow(appName: appName) else {
            printError("Window not found: \(appName)")
            return
        }
        image = result.0
        rect = result.1
    }

    let elements = performOCR(image: image, screenRect: rect)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let json = try? encoder.encode(elements) {
        print(String(data: json, encoding: .utf8) ?? "[]")
    }
}

func cmdFind(appName: String, query: String, region: CGRect?) {
    let (image, rect): (CGImage, CGRect)

    if let region = region {
        guard let img = captureRegion(region) else {
            printJSON(FindResult(text: query, x: 0, y: 0, found: false))
            return
        }
        image = img
        rect = region
    } else {
        guard let result = captureWindow(appName: appName) else {
            printJSON(FindResult(text: query, x: 0, y: 0, found: false))
            return
        }
        image = result.0
        rect = result.1
    }

    let elements = performOCR(image: image, screenRect: rect)
    let queryLower = query.lowercased()

    // Exact match first, then contains
    let exact = elements.first { $0.text.lowercased() == queryLower }
    let partial = elements.first { $0.text.lowercased().contains(queryLower) }
    let match = exact ?? partial

    if let m = match {
        printJSON(FindResult(text: m.text, x: m.x, y: m.y, found: true))
    } else {
        printJSON(FindResult(text: query, x: 0, y: 0, found: false))
    }
}

func cmdTap(appName: String, query: String, region: CGRect?) {
    let (image, rect): (CGImage, CGRect)

    if let region = region {
        guard let img = captureRegion(region) else {
            printJSON(TapResult(text: query, x: 0, y: 0, tapped: false))
            return
        }
        image = img
        rect = region
    } else {
        guard let result = captureWindow(appName: appName) else {
            printJSON(TapResult(text: query, x: 0, y: 0, tapped: false))
            return
        }
        image = result.0
        rect = result.1
    }

    let elements = performOCR(image: image, screenRect: rect)
    let queryLower = query.lowercased()

    let exact = elements.first { $0.text.lowercased() == queryLower }
    let partial = elements.first { $0.text.lowercased().contains(queryLower) }
    let match = exact ?? partial

    if let m = match {
        // Execute cliclick
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cliclick")
        process.arguments = ["c:\(m.x),\(m.y)"]
        try? process.run()
        process.waitUntilExit()

        printJSON(TapResult(text: m.text, x: m.x, y: m.y, tapped: process.terminationStatus == 0))
    } else {
        printJSON(TapResult(text: query, x: 0, y: 0, tapped: false))
    }
}

func cmdList(appName: String, region: CGRect?) {
    let (image, rect): (CGImage, CGRect)

    if let region = region {
        guard let img = captureRegion(region) else {
            printError("Failed to capture")
            return
        }
        image = img
        rect = region
    } else {
        guard let result = captureWindow(appName: appName) else {
            printError("Window not found: \(appName)")
            return
        }
        image = result.0
        rect = result.1
    }

    let elements = performOCR(image: image, screenRect: rect)
        .sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }

    for el in elements {
        let conf = String(format: "%.0f%%", el.confidence * 100)
        print("  [\(el.x), \(el.y)]  \(el.text)  (\(conf))")
    }
    print("\n\(elements.count) elements found")
}

// MARK: - Helpers

func printJSON<T: Codable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    if let json = try? encoder.encode(value) {
        print(String(data: json, encoding: .utf8) ?? "{}")
    }
}

func printError(_ msg: String) {
    FileHandle.standardError.write(Data("Error: \(msg)\n".utf8))
}

func parseRegion(_ str: String) -> CGRect? {
    let parts = str.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4 else { return nil }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

func printUsage() {
    let usage = """
    toss-vision — Apple Vision OCR helper for screen automation

    Usage:
      toss-vision ocr  [--app NAME] [--region x,y,w,h]   Full OCR → JSON
      toss-vision list [--app NAME] [--region x,y,w,h]   OCR → human-readable list
      toss-vision find "text" [--app NAME] [--region x,y,w,h]  Find text → coordinates
      toss-vision tap  "text" [--app NAME] [--region x,y,w,h]  Find + click

    Options:
      --app NAME       Target app name (default: "Toss POS")
      --region x,y,w,h Screen region to capture

    Examples:
      toss-vision list
      toss-vision find "매출 리포트"
      toss-vision tap "받기"
      toss-vision ocr --region 135,25,1014,760
    """
    print(usage)
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.first == "help" || args.first == "--help" {
    printUsage()
    exit(0)
}

var appName = "Toss POS"
var region: CGRect? = nil
var command = args[0]
var query = ""

var i = 1
while i < args.count {
    switch args[i] {
    case "--app":
        i += 1
        if i < args.count { appName = args[i] }
    case "--region":
        i += 1
        if i < args.count { region = parseRegion(args[i]) }
    default:
        if query.isEmpty { query = args[i] }
    }
    i += 1
}

switch command {
case "ocr":
    cmdOCR(appName: appName, region: region)
case "list":
    cmdList(appName: appName, region: region)
case "find":
    guard !query.isEmpty else {
        printError("Usage: toss-vision find \"text\"")
        exit(1)
    }
    cmdFind(appName: appName, query: query, region: region)
case "tap":
    guard !query.isEmpty else {
        printError("Usage: toss-vision tap \"text\"")
        exit(1)
    }
    cmdTap(appName: appName, query: query, region: region)
default:
    printError("Unknown command: \(command)")
    printUsage()
    exit(1)
}
