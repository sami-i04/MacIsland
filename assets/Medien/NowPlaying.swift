import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class NowPlaying: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    private var elapsed: Double = 0
    private var elapsedAt = Date()
    private var rate: Double = 0
    private var stdinPipe: Pipe?

    enum Command: String { case toggle, next, previous = "prev" }

    @Published var scrubPosition: Double?
    @Published var timelineHover = false

    func seek(to seconds: Double) {
        elapsed = seconds
        elapsedAt = Date()
        scrubPosition = nil
        write("seek \(seconds)")
    }

    func position(at date: Date) -> Double {
        let p = elapsed + (isPlaying ? date.timeIntervalSince(elapsedAt) * max(rate, 1) : 0)
        return duration > 0 ? min(p, duration) : p
    }

    func send(_ cmd: Command) {
        if cmd == .toggle {
            elapsed = position(at: Date()); elapsedAt = Date()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPlaying.toggle() }
        }
        write(cmd.rawValue)
    }

    private func write(_ line: String) {
        guard let h = stdinPipe?.fileHandleForWriting, let data = (line + "\n").data(using: .utf8) else { return }
        try? h.write(contentsOf: data)
    }
    @Published private(set) var accent = Color.white
    @Published private(set) var showCompact = false
    let spectrum = AudioSpectrum()

    private let hideDelay: TimeInterval = 3
    private var process: Process?
    private var buffer = Data()
    private var hideWork: DispatchWorkItem?
    private var stopping = false

    private static let perlScript = """
    use DynaLoader;
    my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
    my $s = DynaLoader::dl_find_symbol($l, "macisland_stream") or die DynaLoader::dl_error();
    DynaLoader::dl_install_xsub("main::stream", $s);
    stream();
    """

    func start() {
        guard let dylib = Bundle.main.url(forResource: "macisland_media", withExtension: "dylib") else {
            log.error("macisland_media.dylib fehlt im Bundle")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlScript, dylib.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        let input = Pipe()
        p.standardInput = input
        stdinPipe = input
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let self, !self.stopping, self.process?.isRunning != true else { return }
                log.info("MediaHelper beendet – starte neu")
                self.start()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            log.error("MediaHelper konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func ensureRunning() {
        guard !stopping else { return }
        if process?.isRunning != true {
            log.info("MediaHelper läuft nicht – starte neu")
            process = nil
            start()
        }
    }

    func stop() {
        stopping = true
        spectrum.stop()
        process?.terminate()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 10) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer = Data(buffer[buffer.index(after: nl)...])
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(obj) }
        }
    }

    private func handle(_ d: [String: Any]) {
        let playing = (d["playing"] as? NSNumber)?.boolValue ?? false
        let newTitle = d["title"] as? String ?? ""
        let newArtist = d["artist"] as? String ?? ""
        if title != newTitle { title = newTitle }
        let newDuration = (d["duration"] as? NSNumber)?.doubleValue ?? 0
        if duration != newDuration { duration = newDuration }
        if scrubPosition == nil, let e = (d["elapsed"] as? NSNumber)?.doubleValue {
            elapsed = e
            if let ts = (d["timestamp"] as? NSNumber)?.doubleValue { elapsedAt = Date(timeIntervalSince1970: ts) }
            else { elapsedAt = Date() }
        }
        rate = (d["rate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
        if artist != newArtist { artist = newArtist }

        let newId = d["artworkId"] as? String
        if let b64 = d["artwork"] as? String, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                artwork = img
                artworkId = newId
                accent = Color(nsColor: Self.accentColor(of: img))
            }
        } else if newId == nil, artworkId != nil {
            artwork = nil
            artworkId = nil
            accent = .white
        }

        if isPlaying != playing {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isPlaying = playing }
        }
        if playing { spectrum.start() } else { spectrum.stop() }
        let hasMedia = !newTitle.isEmpty
        if playing && hasMedia {
            hideWork?.cancel(); hideWork = nil
            if !showCompact {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { showCompact = true }
            }
        } else if showCompact, hideWork == nil {
            let w = DispatchWorkItem { [weak self] in
                self?.hideWork = nil
                if self?.isPlaying == false {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { self?.showCompact = false }
                }
            }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: w)
        }
    }

    static func accentColor(of image: NSImage) -> NSColor {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        let n = 8
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let pr = Double(px[i]) / 255, pg = Double(px[i + 1]) / 255, pb = Double(px[i + 2]) / 255
            let sat = max(pr, pg, pb) - min(pr, pg, pb)
            let w = 0.15 + sat * sat * 4
            r += pr * w; g += pg * w; b += pb * w; wsum += w
        }
        let c = NSColor(srgbRed: r / wsum, green: g / wsum, blue: b / wsum, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.92, alpha: 1) }
        return NSColor(hue: h, saturation: min(1, s * 1.25), brightness: max(v, 0.82), alpha: 1)
    }
}
