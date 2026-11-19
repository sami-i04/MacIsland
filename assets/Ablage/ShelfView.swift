import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

struct ShelfView: View {
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var state: IslandState
    private var isDragging: Bool { state.isDragging }
    private var targeted: Bool { state.shelfTargeted }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Layout.elementRadius)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .contentShape(Rectangle())
                .onTapGesture {
                    shelf.deselectAll()
                    state.focusShelf()
                }
                .foregroundStyle(targeted ? Color.orange : Color.white.opacity(0.18))
                .background(RoundedRectangle(cornerRadius: Layout.elementRadius).fill(Color.white.opacity(targeted ? 0.08 : 0.04)))

            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 18))
                    Text("Dateien hier ablegen").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.55))
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items, id: \.self) { url in
                                ShelfItemView(url: url, state: state) { shelf.remove(url) }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { state.shelfTargeted }, set: { state.shelfTargeted = $0 })) { providers in
            loadFileURLs(providers) { shelf.add($0) }
            return true
        }
    }
}

struct ShelfItemView: View {
    let url: URL
    @ObservedObject var state: IslandState
    let onRemove: () -> Void
    private var hover: Bool { state.hoveredItem == url }
    private var selected: Bool { state.shelf.selection.contains(url) }

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: IconCache.icon(url.path))
                .resizable()
                .frame(width: 30, height: 30)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.45) : Color.white.opacity(hover ? 0.1 : 0)))
        .animation(.easeOut(duration: 0.12), value: selected)
        .overlay(FileDragSource(url: url, shelf: state.shelf, onRemove: onRemove,
                                onFocus: { state.focusShelf() }))
        .overlay(alignment: .topTrailing) {
            if hover {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, .gray)
                    .contentShape(Circle())
                    .highPriorityGesture(TapGesture().onEnded { onRemove() })
            }
        }
        .onHover { inside in
            if inside { state.hoveredItem = url } else if state.hoveredItem == url { state.hoveredItem = nil }
        }
        .help(url.path)
    }
}

struct FileDragSource: NSViewRepresentable {
    let url: URL
    let shelf: ShelfStore
    let onRemove: () -> Void
    let onFocus: () -> Void

    func makeNSView(context: Context) -> FileDragNSView { FileDragNSView() }
    func updateNSView(_ v: FileDragNSView, context: Context) {
        v.url = url
        v.shelf = shelf
        v.onRemove = onRemove
        v.onFocus = onFocus
    }
}

final class FileDragNSView: NSView, NSDraggingSource {
    var url: URL!
    weak var shelf: ShelfStore?
    var onRemove: () -> Void = {}
    var onFocus: () -> Void = {}
    private var mouseDownEvent: NSEvent?
    private var droppedOutside = false
    private var dragged: [URL] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        shelf?.click(url, toggle: event.modifierFlags.contains(.command))
        onFocus()
        if event.clickCount == 2 {
            NSWorkspace.shared.open(url)
            mouseDownEvent = nil
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
        mouseDownEvent = nil

        dragged = shelf?.dragItems(for: url) ?? [url]
        let p = convert(down.locationInWindow, from: nil)
        let items: [NSDraggingItem] = dragged.enumerated().map { i, u in
            let item = NSDraggingItem(pasteboardWriter: u as NSURL)
            let o = CGFloat(min(i, 4)) * 4
            item.setDraggingFrame(NSRect(x: p.x - 24 + o, y: p.y - 24 - o, width: 48, height: 48),
                                  contents: IconCache.icon(u.path))
            return item
        }
        droppedOutside = false
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return [.move, .generic]
        default: return [.copy, .generic]
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        if let win = window, win.frame.contains(screenPoint), !win.ignoresMouseEvents { return }
        if dragged.count > 1, let shelf {
            dragged.forEach { shelf.remove($0) }
        } else {
            onRemove()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(ClosureMenuItem(String(localized: "Öffnen")) { [url] in NSWorkspace.shared.open(url!) })
        m.addItem(ClosureMenuItem(String(localized: "Im Finder zeigen")) { [url] in NSWorkspace.shared.activateFileViewerSelecting([url!]) })
        m.addItem(ClosureMenuItem(String(localized: "Per AirDrop senden")) { [url] in AirDrop.send([url!]) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(String(localized: "Aus Ablage entfernen")) { [weak self] in self?.onRemove() })
        return m
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}
