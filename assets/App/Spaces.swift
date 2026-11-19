import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreAudio
import AudioToolbox
import Accelerate
import EventKit
import IOKit.ps
import os

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

@_silgen_name("CGSAddWindowsToSpaces") private func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSRemoveWindowsFromSpaces") private func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSCopySpacesForWindows") private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?

enum SpaceInfo {
    private static func entry(for displayID: CGDirectDisplayID) -> [String: Any]? {
        guard let arr = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]],
              !arr.isEmpty else { return nil }
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        }
        return arr.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(uuid ?? "") == .orderedSame }
            ?? (arr.count == 1 ? arr[0] : nil)
    }

    static func spaces(displayID: CGDirectDisplayID) -> [(id: UInt64, fullscreen: Bool)] {
        guard let list = entry(for: displayID)?["Spaces"] as? [[String: Any]] else { return [] }
        return list.compactMap { sp in
            guard let id = (sp["id64"] as? NSNumber)?.uint64Value ?? (sp["ManagedSpaceID"] as? NSNumber)?.uint64Value
            else { return nil }
            return (id, (sp["type"] as? Int) == 4)
        }
    }

    static func assign(window: Int, to wanted: [UInt64], allOnDisplay: [UInt64]) {
        let cid = CGSMainConnectionID()
        let w = [NSNumber(value: window)] as CFArray
        let current = Set((CGSCopySpacesForWindows(cid, 7, w)?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value))
        let add = wanted.filter { !current.contains($0) }
        let remove = allOnDisplay.filter { current.contains($0) && !wanted.contains($0) }
        if !add.isEmpty { CGSAddWindowsToSpaces(cid, w, add.map { NSNumber(value: $0) } as CFArray) }
        if !remove.isEmpty { CGSRemoveWindowsFromSpaces(cid, w, remove.map { NSNumber(value: $0) } as CFArray) }
    }

    static func isFullscreen(displayID: CGDirectDisplayID) -> Bool {
        guard let current = entry(for: displayID)?["Current Space"] as? [String: Any] else { return false }
        return (current["type"] as? Int) == 4
    }
}
