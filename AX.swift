// Accessibility-tree access for the Codex Desktop window.

import Foundation
import ApplicationServices
import AppKit

let targetBundleID = "com.openai.codex"

// MARK: - attribute access

func axCopy(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    return value
}

func axString(_ el: AXUIElement, _ attr: String) -> String? {
    axCopy(el, attr) as? String
}

func axElements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    (axCopy(el, attr) as? [AXUIElement]) ?? []
}

// MARK: - tree walking

struct AXNode {
    let el: AXUIElement
    let role: String
    let text: String
    let depth: Int
}

struct WalkLimits {
    var maxDepth = 80
    var maxNodes = 120_000
    var budget: TimeInterval = 2.0
}

/// Depth-first walk under node, depth and wall-clock budgets.
/// `visit` returns true to stop the walk early.
@discardableResult
func axWalk(_ root: AXUIElement, limits: WalkLimits = WalkLimits(), visit: (AXNode) -> Bool) -> Int {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    var visited = 0
    let deadline = Date().addingTimeInterval(limits.budget)

    while let (el, depth) = stack.popLast() {
        if visited >= limits.maxNodes || Date() > deadline { break }
        visited += 1

        let role = axString(el, "AXRole") ?? ""
        var parts: [String] = []
        for attr in ["AXTitle", "AXDescription", "AXValue", "AXHelp"] {
            if let s = axString(el, attr), !s.isEmpty { parts.append(s) }
        }
        if visit(AXNode(el: el, role: role, text: parts.joined(separator: " | "), depth: depth)) { break }

        if depth < limits.maxDepth {
            for child in axElements(el, "AXChildren").reversed() { stack.append((child, depth + 1)) }
        }
    }
    return visited
}

// MARK: - target app

func codexAppElement() -> (element: AXUIElement, pid: pid_t)? {
    guard let running = NSRunningApplication
        .runningApplications(withBundleIdentifier: targetBundleID).first else { return nil }
    let el = AXUIElementCreateApplication(running.processIdentifier)
    // Chromium/Electron builds its web accessibility tree only for a client
    // that explicitly asks for it.
    AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    return (el, running.processIdentifier)
}

// MARK: - matching

func isButtonRole(_ role: String) -> Bool {
    role == "AXButton" || role == "AXMenuButton" || role == "AXPopUpButton" || role == "AXLink"
}

/// Matches whole-ish labels, so "Retry turn" counts but a "retrying…" status
/// string does not get mistaken for the button.
func textMatchesLabel(_ text: String, labels: [String]) -> Bool {
    let t = text.lowercased()
    return labels.contains { l in
        t == l || t.hasPrefix(l + " ") || t.hasPrefix(l + "\n") || t.contains("| \(l)")
    }
}

func textContainsAny(_ text: String, needles: [String]) -> Bool {
    guard !needles.isEmpty else { return false }
    let t = text.lowercased()
    return needles.contains { t.contains($0.lowercased()) }
}

// MARK: - dump

struct DumpResult {
    let text: String
    let ok: Bool
}

/// Builds a readable snapshot of the Codex window's accessibility tree.
/// Returns text instead of printing so the menu bar app can run it too — which
/// matters because TCC attributes a terminal-launched binary to the terminal,
/// not to this app, so a dump run from a shell can report "no permission"
/// while the real app has it.
func accessibilityDump(all: Bool, config: Watcher.Config) -> DumpResult {
    var out: [String] = []
    func emit(_ line: String) { out.append(line) }

    emit("codex-retry-watcher accessibility dump — \(Date())")
    emit("trusted (this process): \(AXIsProcessTrusted())")

    guard let (app, pid) = codexAppElement() else {
        emit("Codex Desktop (\(targetBundleID)) is not running")
        return DumpResult(text: out.joined(separator: "\n"), ok: false)
    }
    emit("attached to pid \(pid)")
    if !AXIsProcessTrusted() {
        emit("WARNING: this process has no accessibility permission — the tree will look empty.")
        emit("If you ran this from a terminal, that is expected: grant/verify via the app itself.")
    }
    // Give Chromium a moment to build the tree after the opt-in above.
    Thread.sleep(forTimeInterval: 1.5)

    let windows = axElements(app, "AXWindows")
    emit("windows: \(windows.count)")
    if windows.isEmpty {
        emit("no windows exposed — either no permission, or Electron has not published its web tree")
        return DumpResult(text: out.joined(separator: "\n"), ok: false)
    }

    var sawRetryButton = false
    for (index, window) in windows.enumerated() {
        emit("")
        emit("=== window \(index): \(axString(window, "AXTitle") ?? "(untitled)") ===")
        var shown = 0
        let visited = axWalk(window, limits: WalkLimits(maxDepth: 80, maxNodes: 120_000, budget: 6.0)) { node in
            if isButtonRole(node.role), textMatchesLabel(node.text, labels: config.buttonLabels) {
                sawRetryButton = true
            }
            let interesting = all
                || (isButtonRole(node.role) && !node.text.isEmpty)
                || textContainsAny(node.text, needles: config.triggers)
                || node.text.lowercased().contains("retry")
            if interesting {
                let pad = String(repeating: " ", count: min(node.depth, 40))
                emit("\(pad)\(node.role) :: \(node.text.replacingOccurrences(of: "\n", with: "⏎"))")
                shown += 1
            }
            return false
        }
        emit("(walked \(visited) nodes, printed \(shown))")
    }

    emit("")
    emit(sawRetryButton
         ? "RESULT: found a Retry-style button — the watcher can press it."
         : "RESULT: no Retry-style button visible right now (normal unless an error is on screen).")
    return DumpResult(text: out.joined(separator: "\n"), ok: true)
}
