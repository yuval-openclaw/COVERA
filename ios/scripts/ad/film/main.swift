import AppKit
import ImageIO
import UniformTypeIdentifiers

// The Clausa ad: 29.6 s, 1080×1920, 30 fps, with motion blur (four exposures
// per frame across half a frame, like a 180° shutter).
//
//   film <shots dir>                    raw BGRA frames on stdout, for ffmpeg
//   film <shots dir> preview <out dir> 1.2,7.5,13.9   stills of chosen moments

let exposures = 4

/// The narrated cut stretches each scene to the length of its line of
/// narration (CLAUSA_NARRATED=1). Each knot is (output time, film time): the
/// film's own clock runs piecewise-linearly between them, so every animation in
/// a scene slows or quickens together and the heartbeat scene keeps its tempo.
let narrated = ProcessInfo.processInfo.environment["CLAUSA_NARRATED"] == "1"
let knots: [(out: Double, film: Double)] = narrated
    ? [(0, 0), (3.9, 2.4), (5.3, 3.6), (6.8, 4.8), (9.2, 7.2), (11.6, 9.6), (15.6, 12.0),
       (21.4, 16.8), (26.0, 19.2), (31.0, 21.6), (33.6, 24.0), (35.6, 26.4), (40.5, 29.6)]
    : [(0, 0), (29.6, 29.6)]
let total = knots.last!.out

func filmTime(_ t: Double) -> Double {
    for (a, b) in zip(knots, knots.dropFirst()) where t <= b.out {
        let p = (t - a.out) / (b.out - a.out)
        return a.film + (b.film - a.film) * max(0, min(1, p))
    }
    return knots.last!.film
}
let args = CommandLine.arguments
setupCanvas()
loadScreens(args[1])

func render(_ t: Double) {
    background(t)
    act1(t)
    act2(t)
    act3(t)
    act4(t)
}

let count = W * H * 4
var acc = [UInt32](repeating: 0, count: count)
var frame = [UInt8](repeating: 0, count: count)
let pixels = ctx.data!.bindMemory(to: UInt8.self, capacity: count)

func exposed(_ t: Double) {
    for i in 0..<count { acc[i] = 0 }
    for e in 0..<exposures {
        let at = max(0, t + (Double(e) + 0.5) / Double(exposures) * 0.5 / FPS - 0.25 / FPS)
        render(filmTime(at))
        acc.withUnsafeMutableBufferPointer { a in
            for i in 0..<count { a[i] &+= UInt32(pixels[i]) }
        }
    }
    frame.withUnsafeMutableBufferPointer { f in
        for i in 0..<count { f[i] = UInt8((acc[i] + UInt32(exposures / 2)) / UInt32(exposures)) }
    }
}

if args.count > 4, args[2] == "preview" {
    for stamp in args[4].split(separator: ",") {
        exposed(Double(stamp)!)
        let out = CGContext(data: &frame, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let url = URL(fileURLWithPath: "\(args[3])/t\(stamp).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, out.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
} else {
    let stdout = FileHandle.standardOutput
    for n in 0..<Int(total * FPS) {
        exposed(Double(n) / FPS)
        frame.withUnsafeBufferPointer { stdout.write(Data(buffer: $0)) }
        if n % 90 == 0 { FileHandle.standardError.write("\(n / 30)s\n".data(using: .utf8)!) }
    }
}
