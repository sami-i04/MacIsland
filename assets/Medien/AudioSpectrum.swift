import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

final class AudioSpectrum: ObservableObject {
    static let bandCount = 5
    @Published private(set) var levels = [Float](repeating: 0, count: bandCount)

    private let bandEdges: [Float] = [40, 150, 400, 1_000, 2_500, 8_000]
    private let displayOrder = [3, 1, 0, 2, 4]

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "local.macisland.audio", qos: .userInteractive)
    private(set) var running = false

    private let fftSize = 1024
    private let hop = 512
    private lazy var fftSetup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2))!
    private lazy var window: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return w
    }()
    private var ring = [Float]()
    private var sinceLast = 0
    private var sampleRate: Float = 48_000
    private var smoothed = [Float](repeating: 0, count: bandCount)
    private var peakDb = [Float](repeating: -30, count: bandCount)
    private var lastPublish: CFTimeInterval = 0

    func start() {
        wanted = true
        installDeviceListener()
        guard !running else { return }
        running = true
        do {
            try setupTap()
            log.info("Audio-Tap gestartet")
        } catch {
            log.error("Audio-Tap fehlgeschlagen: \(String(describing: error))")
            teardown()
        }
    }

    func restart() {
        guard wanted else { return }
        if running { running = false; teardown() }
        start()
    }

    private var wanted = false
    private var deviceListener: AudioObjectPropertyListenerBlock?

    func stop() {
        wanted = false
        guard running else { return }
        running = false
        teardown()
        levels = [Float](repeating: 0, count: Self.bandCount)
    }

    private func installDeviceListener() {
        guard deviceListener == nil else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.restart() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    private struct TapError: Error { let step: String; let status: OSStatus }

    private func setupTap() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.name = "MacIsland Visualizer"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw TapError(step: "CreateProcessTap", status: st) }

        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        st = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt)
        guard st == noErr else { throw TapError(step: "TapFormat", status: st) }
        let channels = Int(max(1, fmt.mChannelsPerFrame))
        let interleaved = fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let rate = Float(fmt.mSampleRate > 0 ? fmt.mSampleRate : 48_000)
        queue.sync { sampleRate = rate }

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacIsland-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        st = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard st == noErr else { throw TapError(step: "CreateAggregateDevice", status: st) }

        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input, channels: channels, interleaved: interleaved)
        }
        guard st == noErr else { throw TapError(step: "CreateIOProc", status: st) }
        st = AudioDeviceStart(aggregateID, procID)
        guard st == noErr else { throw TapError(step: "DeviceStart", status: st) }
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let p = procID {
                AudioDeviceStop(aggregateID, p)
                AudioDeviceDestroyIOProcID(aggregateID, p)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.async { [weak self] in
            guard let self else { return }
            self.ring.removeAll(keepingCapacity: true)
            self.smoothed = [Float](repeating: 0, count: Self.bandCount)
        }
    }

    private static func defaultOutputUID() throws -> String {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        guard st == noErr else { throw TapError(step: "DefaultOutput", status: st) }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        st = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &uid)
        guard st == noErr, let u = uid?.takeRetainedValue() else { throw TapError(step: "DeviceUID", status: st) }
        return u as String
    }

    private func consume(_ input: UnsafePointer<AudioBufferList>, channels: Int, interleaved: Bool) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = list.first, let raw = first.mData else { return }
        let floats = raw.assumingMemoryBound(to: Float.self)
        if interleaved {
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += floats[f * channels + c] }
                ring.append(sum / Float(channels))
            }
        } else {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            if list.count > 1, let second = list[1].mData?.assumingMemoryBound(to: Float.self) {
                for f in 0..<frames { ring.append((floats[f] + second[f]) * 0.5) }
            } else {
                ring.append(contentsOf: UnsafeBufferPointer(start: floats, count: frames))
            }
        }
        sinceLast += 1
        if ring.count > fftSize * 2 { ring.removeFirst(ring.count - fftSize * 2) }
        while ring.count >= fftSize {
            analyze(Array(ring[(ring.count - fftSize)...]))
            ring.removeFirst(min(hop, ring.count))
            if ring.count < fftSize { break }
        }
    }

    private func analyze(_ samples: [Float]) {
        let n = fftSize
        var x = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &x, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                x.withUnsafeBufferPointer { xp in
                    xp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }

        let binHz = sampleRate / Float(n)
        var raw = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = max(1, Int(bandEdges[b] / binHz))
            let hi = min(n / 2 - 1, max(lo + 1, Int(bandEdges[b + 1] / binHz)))
            var sum: Float = 0
            for k in lo..<hi { sum += mags[k] }
            let avg = sum / Float(hi - lo) / Float(n * n)
            let db = 10 * log10f(avg + 1e-12)

            peakDb[b] = max(db, peakDb[b] - 0.08)
            peakDb[b] = max(peakDb[b], -45)
            let floorDb = peakDb[b] - 38
            var v = (db - floorDb) / (peakDb[b] - floorDb)
            v = min(1, max(0, v))
            raw[b] = powf(v, 1.6)
        }

        for b in 0..<Self.bandCount {
            let k: Float = raw[b] > smoothed[b] ? 0.65 : 0.22
            smoothed[b] += (raw[b] - smoothed[b]) * k
        }
        let out = displayOrder.map { smoothed[$0] }
        let now = CACurrentMediaTime()
        guard now - lastPublish >= 1.0 / 60.0 else { return }
        lastPublish = now
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.levels = out
        }
    }
}
