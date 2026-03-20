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
    let all: [TextElement]?
}

struct TapResult: Codable {
    let text: String
    let x: Int
    let y: Int
    let tapped: Bool
}

struct WaitResult: Codable {
    let text: String
    let found: Bool
    let elapsed: Double
    let x: Int
    let y: Int
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

    let scaleX = screenRect.width / imgW
    let scaleY = screenRect.height / imgH

    var elements: [TextElement] = []

    for observation in results {
        guard let candidate = observation.topCandidates(1).first else { continue }

        let box = observation.boundingBox
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

// MARK: - Matching

func findMatch(elements: [TextElement], query: String, exact: Bool, nth: Int) -> TextElement? {
    let queryLower = query.lowercased()

    var matches: [TextElement]
    if exact {
        matches = elements.filter { $0.text.lowercased() == queryLower }
    } else {
        // Exact first, then contains, sorted by specificity
        let exactMatches = elements.filter { $0.text.lowercased() == queryLower }
        let containsMatches = elements.filter {
            $0.text.lowercased().contains(queryLower) &&
            $0.text.lowercased() != queryLower
        }
        matches = exactMatches + containsMatches
    }

    // Sort by position (top to bottom, left to right) for consistent nth selection
    matches.sort { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }

    guard nth > 0, nth <= matches.count else {
        return matches.first
    }
    return matches[nth - 1]
}

func getImageAndRect(appName: String, region: CGRect?) -> (CGImage, CGRect)? {
    if let region = region {
        guard let img = captureRegion(region) else { return nil }
        return (img, region)
    } else {
        return captureWindow(appName: appName)
    }
}

// MARK: - Commands

func cmdOCR(appName: String, region: CGRect?) {
    guard let (image, rect) = getImageAndRect(appName: appName, region: region) else {
        printError("Failed to capture")
        return
    }
    let elements = performOCR(image: image, screenRect: rect)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let json = try? encoder.encode(elements) {
        print(String(data: json, encoding: .utf8) ?? "[]")
    }
}

func cmdFind(appName: String, query: String, region: CGRect?, exact: Bool, nth: Int, showAll: Bool) {
    guard let (image, rect) = getImageAndRect(appName: appName, region: region) else {
        printJSON(FindResult(text: query, x: 0, y: 0, found: false, all: nil))
        return
    }

    let elements = performOCR(image: image, screenRect: rect)
    let match = findMatch(elements: elements, query: query, exact: exact, nth: nth)

    if let m = match {
        let allMatches: [TextElement]? = showAll ? elements.filter {
            $0.text.lowercased().contains(query.lowercased())
        } : nil
        printJSON(FindResult(text: m.text, x: m.x, y: m.y, found: true, all: allMatches))
    } else {
        printJSON(FindResult(text: query, x: 0, y: 0, found: false, all: nil))
    }
}

func cmdTap(appName: String, query: String, region: CGRect?, exact: Bool, nth: Int, retry: Int) {
    for attempt in 1...max(1, retry) {
        guard let (image, rect) = getImageAndRect(appName: appName, region: region) else {
            if attempt < retry {
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }
            printJSON(TapResult(text: query, x: 0, y: 0, tapped: false))
            return
        }

        let elements = performOCR(image: image, screenRect: rect)
        let match = findMatch(elements: elements, query: query, exact: exact, nth: nth)

        if let m = match {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cliclick")
            process.arguments = ["c:\(m.x),\(m.y)"]
            try? process.run()
            process.waitUntilExit()
            printJSON(TapResult(text: m.text, x: m.x, y: m.y, tapped: process.terminationStatus == 0))
            return
        }

        if attempt < retry {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    printJSON(TapResult(text: query, x: 0, y: 0, tapped: false))
}

func cmdWait(appName: String, query: String, region: CGRect?, exact: Bool, timeout: Double) {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if let (image, rect) = getImageAndRect(appName: appName, region: region) {
            let elements = performOCR(image: image, screenRect: rect)
            let match = findMatch(elements: elements, query: query, exact: exact, nth: 1)
            if let m = match {
                let elapsed = Date().timeIntervalSince(start)
                printJSON(WaitResult(text: m.text, found: true, elapsed: elapsed, x: m.x, y: m.y))
                return
            }
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
    printJSON(WaitResult(text: query, found: false, elapsed: timeout, x: 0, y: 0))
}

func cmdList(appName: String, region: CGRect?) {
    guard let (image, rect) = getImageAndRect(appName: appName, region: region) else {
        printError("Window not found: \(appName)")
        return
    }

    let elements = performOCR(image: image, screenRect: rect)
        .sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }

    for el in elements {
        let conf = String(format: "%.0f%%", el.confidence * 100)
        print("  [\(el.x), \(el.y)]  \(el.text)  (\(conf))")
    }
    print("\n\(elements.count) elements found")
}

func cmdHas(appName: String, query: String, region: CGRect?, exact: Bool) {
    guard let (image, rect) = getImageAndRect(appName: appName, region: region) else {
        print("false")
        exit(1)
    }
    let elements = performOCR(image: image, screenRect: rect)
    let match = findMatch(elements: elements, query: query, exact: exact, nth: 1)
    if match != nil {
        print("true")
        exit(0)
    } else {
        print("false")
        exit(1)
    }
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
      toss-vision ocr   [options]                Full OCR → JSON
      toss-vision list  [options]                OCR → human-readable list
      toss-vision find  "text" [options]         Find text → coordinates
      toss-vision tap   "text" [options]         Find + click
      toss-vision wait  "text" [options]         Wait until text appears
      toss-vision has   "text" [options]         Check if text exists (exit 0/1)

    Options:
      --app NAME         Target app name (default: "Toss POS")
      --region x,y,w,h   Screen region to capture
      --exact            Exact match only (no partial/contains matching)
      --nth N            Select Nth match (default: 1st, sorted top→bottom)
      --retry N          Retry N times with 1s delay (tap only, default: 1)
      --timeout N        Wait timeout in seconds (wait only, default: 30)
      --all              Show all matches (find only)

    Examples:
      toss-vision list
      toss-vision find "매출 리포트"
      toss-vision tap "받기" --exact --retry 3
      toss-vision tap ">" --exact --nth 2
      toss-vision wait "파일을 만들고 있어요" --timeout 10
      toss-vision has "비밀번호 확인" && echo "PIN screen!"
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
var exact = false
var nth = 1
var retry = 1
var timeout = 30.0
var showAll = false

var i = 1
while i < args.count {
    switch args[i] {
    case "--app":
        i += 1
        if i < args.count { appName = args[i] }
    case "--region":
        i += 1
        if i < args.count { region = parseRegion(args[i]) }
    case "--exact":
        exact = true
    case "--nth":
        i += 1
        if i < args.count { nth = Int(args[i]) ?? 1 }
    case "--retry":
        i += 1
        if i < args.count { retry = Int(args[i]) ?? 1 }
    case "--timeout":
        i += 1
        if i < args.count { timeout = Double(args[i]) ?? 30.0 }
    case "--all":
        showAll = true
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
    cmdFind(appName: appName, query: query, region: region, exact: exact, nth: nth, showAll: showAll)
case "tap":
    guard !query.isEmpty else {
        printError("Usage: toss-vision tap \"text\"")
        exit(1)
    }
    cmdTap(appName: appName, query: query, region: region, exact: exact, nth: nth, retry: retry)
case "wait":
    guard !query.isEmpty else {
        printError("Usage: toss-vision wait \"text\"")
        exit(1)
    }
    cmdWait(appName: appName, query: query, region: region, exact: exact, timeout: timeout)
case "has":
    guard !query.isEmpty else {
        printError("Usage: toss-vision has \"text\"")
        exit(1)
    }
    cmdHas(appName: appName, query: query, region: region, exact: exact)
default:
    printError("Unknown command: \(command)")
    printUsage()
    exit(1)
}
