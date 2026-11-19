import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct MusicLayer: View {
    @ObservedObject var music: NowPlaying
    let expanded: Bool
    let homeMode: Bool
    let visible: Bool
    let notchHeight: CGFloat
    var closedBottomRadius: CGFloat = 10
    let contentAnimation: Animation

    private var contentTop: CGFloat { notchHeight + 4 }
    private var contentHeight: CGFloat { Layout.openHeight - contentTop - Layout.contentInset }

    private var artSize: CGFloat { expanded ? Layout.musicArtwork : Layout.compactArtwork }
    private var compactInset: CGFloat { (notchHeight - Layout.compactArtwork) / 2 }
    private var artX: CGFloat { expanded ? Layout.contentInset : compactInset }
    private var artY: CGFloat {
        expanded ? Layout.openHeight - Layout.contentInset - Layout.musicArtwork : (notchHeight - Layout.compactArtwork) / 2
    }
    private var visSize: CGSize {
        if expanded { return Layout.musicVisualizer }
        if homeMode { return CGSize(width: 26, height: 16) }
        return CGSize(width: Layout.compactArtwork, height: 14)
    }
    private var visX: CGFloat {
        if expanded { return Layout.contentInset + 4 }
        if homeMode { return Layout.contentInset + 2 }
        return compactInset
    }
    private var visY: CGFloat {
        expanded ? artY + (Layout.musicArtwork - visSize.height) / 2 : (notchHeight - visSize.height) / 2
    }

    private var middleOffset: CGFloat {
        let left = Layout.contentInset + Layout.musicArtwork
        let right = Layout.contentInset + 4 + Layout.musicVisualizer.width
        return (left - right) / 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtworkView(image: music.artwork, id: music.artworkId, size: artSize,
                        cornerRadius: expanded ? Layout.elementRadius : max(3, closedBottomRadius - compactInset))
                .shadow(color: .black.opacity(expanded ? 0.4 : 0), radius: 8, y: 3)
                .scaleEffect(homeMode ? 0.5 : 1)
                .opacity(homeMode ? 0 : 1)
                .offset(x: artX, y: artY)

            ZStack(alignment: .topTrailing) {
                MusicVisualizer(spectrum: music.spectrum, playing: music.isPlaying, color: music.accent)
                    .frame(width: visSize.width, height: visSize.height)
                    .offset(x: -visX, y: visY)
                Color.clear
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            MusicControls(music: music)
                .frame(width: Layout.musicControlsWidth, height: Layout.musicArtwork)
                .offset(x: middleOffset, y: Layout.openHeight - Layout.contentInset - Layout.musicArtwork)
                .scaleEffect(expanded ? 1 : 0.7, anchor: .top)
                .blur(radius: expanded ? 0 : 6)
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
                .animation(contentAnimation, value: expanded)
        }
        .opacity(visible ? 1 : 0)
        .animation(visible ? .easeOut(duration: 0.25).delay(0.1) : .easeOut(duration: 0.1), value: visible)
    }
}

struct MusicControls: View {
    @ObservedObject var music: NowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(music.title.isEmpty ? String(localized: "Unbekannter Titel") : music.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !music.artist.isEmpty {
                    Text(music.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            }

            ProgressRow(music: music)
                .padding(.top, 3)

            HStack(spacing: 26) {
                ControlButton(symbol: "backward.fill", size: 14) { music.send(.previous) }
                ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 20) { music.send(.toggle) }
                ControlButton(symbol: "forward.fill", size: 14) { music.send(.next) }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct ProgressRow: View {
    @ObservedObject var music: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = max(music.duration, 0.001)
            let scrubbing = music.scrubPosition != nil
            let pos = music.scrubPosition ?? music.position(at: ctx.date)
            HStack(spacing: 6) {
                Text(Self.fmt(pos)).monospacedDigit()
                GeometryReader { g in
                    let barH: CGFloat = scrubbing || music.timelineHover ? 7 : 4
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(music.accent)
                            .frame(width: g.size.width * CGFloat(min(1, max(0, pos / dur))))
                    }
                    .frame(height: barH)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let f = min(1, max(0, v.location.x / g.size.width))
                                music.scrubPosition = Double(f) * music.duration
                            }
                            .onEnded { v in
                                let f = min(1, max(0, v.location.x / g.size.width))
                                music.seek(to: Double(f) * music.duration)
                            }
                    )
                    .onHover { music.timelineHover = $0 }
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: barH)
                }
                .frame(height: 14)
                Text(Self.fmt(music.duration)).monospacedDigit()
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(scrubbing ? 0.85 : 0.5))
            .animation(scrubbing ? nil : .linear(duration: 0.5), value: pos)
        }
    }

    static func fmt(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { action() })
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let id: String?
    let size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.7)),
                                            removal: .opacity))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: id)
    }
}

struct MusicVisualizer: View {
    @ObservedObject var spectrum: AudioSpectrum
    let playing: Bool
    let color: Color

    var body: some View {
        VisualizerBars(levels: spectrum.levels, amount: playing ? 1 : 0)
            .fill(color)
            .drawingGroup()
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playing)
            .animation(.easeInOut(duration: 0.4), value: color)
    }
}

struct VisualizerBars: Shape {
    var levels: [Float]
    var amount: CGFloat

    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let n = max(levels.count, 1)
        let bw = max(2.2, rect.width * 0.095)
        let spacing = n > 1 ? (rect.width - CGFloat(n) * bw) / CGFloat(n - 1) : 0
        var p = Path()
        for i in 0..<n {
            let level = CGFloat(i < levels.count ? levels[i] : 0)
            let full = (0.12 + 0.88 * level) * rect.height
            let h = max(bw, bw + (full - bw) * amount)
            let x = rect.minX + CGFloat(i) * (bw + spacing)
            let bar = CGRect(x: x, y: rect.midY - h / 2, width: bw, height: h)
            p.addRoundedRect(in: bar, cornerSize: CGSize(width: bw / 2, height: bw / 2))
        }
        return p
    }
}
