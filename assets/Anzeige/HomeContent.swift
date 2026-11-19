import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct HomeContent: View {
    @ObservedObject var apps: AppSlots
    @ObservedObject var note: QuickNote
    @ObservedObject var shelf: ShelfStore
    let state: IslandState

    var body: some View {
        GeometryReader { g in
            let spacing: CGFloat = 12
            let w = g.size.width - spacing
            HStack(spacing: spacing) {
                AppSlotsView(apps: apps).frame(width: w * 0.6)
                ZStack {
                    if shelf.items.isEmpty {
                        QuickNoteView(note: note)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        ShelfView(shelf: shelf, state: state)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: shelf.items.isEmpty)
                .frame(width: w * 0.4)
            }
        }
    }
}

struct AppSlotsView: View {
    @ObservedObject var apps: AppSlots
    private let icon: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<AppSlots.count, id: \.self) { i in
                slot(i).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Layout.elementRadius, style: .continuous)
            .fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        let hover = apps.hovered == i
        ZStack {
            if let url = apps.apps[i] {
                Image(nsImage: IconCache.icon(url.path))
                    .resizable()
                    .frame(width: icon, height: icon)
                    .help(url.deletingPathExtension().lastPathComponent)
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(hover ? 0.45 : 0.25))
                    .frame(width: icon - 6, height: icon - 6)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(hover ? 0.7 : 0.4))
                    .help("App im Finder auswählen")
            }
        }
        .frame(width: icon, height: icon)
        .scaleEffect(hover ? 1.08 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: hover)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { apps.hovered = i } else if apps.hovered == i { apps.hovered = nil }
        }
        .highPriorityGesture(TapGesture().onEnded { apps.open(i) })
        .contextMenu {
            Button("App ändern…") { apps.choose(i) }
            if apps.apps[i] != nil { Button("Entfernen") { apps.set(i, nil) } }
        }
    }
}

struct QuickNoteView: View {
    @ObservedObject var note: QuickNote

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Layout.elementRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
            TextEditor(text: $note.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
            if note.text.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "note.text")
                    Text("Quick Note")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
        }
    }
}

struct OpenContent: View {
    @ObservedObject var state: IslandState

    var body: some View {
        HStack(spacing: 12) {
            ShelfView(shelf: state.shelf, state: state)
            AirDropView(shelf: state.shelf, state: state)
                .frame(width: 120)
        }
    }
}
