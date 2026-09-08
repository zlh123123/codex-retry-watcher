// Menu bar (status item) UI.

import AppKit
import ApplicationServices

private func symbolImage(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: "Codex 重试守护")
    image?.isTemplate = true      // follows light/dark menu bar automatically
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let watcher: Watcher
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let statusLine = NSMenuItem(title: "启动中…", action: nil, keyEquivalent: "")
    private let statsLine = NSMenuItem(title: "本次运行:0 次", action: nil, keyEquivalent: "")
    private let autoRetryItem = NSMenuItem(title: "自动重试", action: nil, keyEquivalent: "")
    private let dryRunItem = NSMenuItem(title: "试运行(只记录不点击)", action: nil, keyEquivalent: "")
    private let retryNowItem = NSMenuItem(title: "立即重试一次", action: nil, keyEquivalent: "r")
    private let permissionItem = NSMenuItem(title: "授权辅助功能…", action: nil, keyEquivalent: "")
    private let dumpItem = NSMenuItem(title: "导出无障碍树(诊断)", action: nil, keyEquivalent: "")
    private let logItem = NSMenuItem(title: "打开日志", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "退出", action: nil, keyEquivalent: "q")

    init(config: Watcher.Config) {
        watcher = Watcher(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = symbolImage("arrow.clockwise")
        statusItem.button?.imagePosition = .imageLeading
        buildMenu()
        statusItem.menu = menu

        watcher.onStatus = { [weak self] status in self?.render(status) }

        if !AXIsProcessTrusted() {
            // One prompt on first launch; after that the menu carries the hint.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }

        let limitText = watcher.config.maxConsecutive > 0 ? "\(watcher.config.maxConsecutive)" : "unlimited"
        logLine("menu bar app started — interval=\(watcher.config.interval)s cooldown=\(watcher.config.cooldown)s maxConsecutive=\(limitText)")
        watcher.start()
        render(watcher.status)
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    // MARK: menu

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        for item in [autoRetryItem, dryRunItem, retryNowItem, permissionItem, dumpItem, logItem, quitItem] {
            item.target = self
            item.isEnabled = true
        }
        autoRetryItem.action = #selector(toggleAutoRetry)
        dryRunItem.action = #selector(toggleDryRun)
        retryNowItem.action = #selector(retryNow)
        permissionItem.action = #selector(openAccessibilitySettings)
        dumpItem.action = #selector(exportDump)
        logItem.action = #selector(openLog)
        quitItem.action = #selector(quitApp)

        statusLine.isEnabled = false
        statsLine.isEnabled = false

        menu.addItem(statusLine)
        menu.addItem(statsLine)
        menu.addItem(.separator())
        menu.addItem(autoRetryItem)
        menu.addItem(dryRunItem)
        menu.addItem(retryNowItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(dumpItem)
        menu.addItem(logItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        render(watcher.status)
    }

    // MARK: rendering

    private func render(_ status: Watcher.Status) {
        let symbol: String
        let text: String

        if !status.permitted {
            symbol = "exclamationmark.triangle"
            text = "未授权辅助功能 — 无法读取按钮"
        } else if !status.codexRunning {
            symbol = "moon.zzz"
            text = "Codex 未运行"
        } else if status.gaveUp {
            symbol = "xmark.octagon"
            text = "已放弃 · 连续 \(watcher.config.maxConsecutive) 次未恢复"
        } else if !status.enabled {
            symbol = "pause.circle"
            text = "已暂停"
        } else if status.errorVisible {
            symbol = "arrow.triangle.2.circlepath"
            let limit = watcher.config.maxConsecutive
            text = limit > 0
                ? "检测到容量错误 · 重试 \(status.consecutive)/\(limit)"
                : "检测到容量错误 · 已重试 \(status.consecutive) 次"
        } else {
            symbol = "arrow.clockwise"
            text = "监控中"
        }

        statusItem.button?.image = symbolImage(symbol)
        // Show the running count next to the icon only while it matters.
        statusItem.button?.title = (status.errorVisible && status.consecutive > 0)
            ? " \(status.consecutive)" : ""

        statusLine.title = text

        var stats = status.dryRun ? "试运行 · " : ""
        stats += "本次运行 \(status.totalPresses) 次"
        if let last = status.lastPress {
            stats += " · 最近 \(timeOfDayFormatter.string(from: last))"
        }
        statsLine.title = stats

        autoRetryItem.state = status.enabled ? .on : .off
        dryRunItem.state = status.dryRun ? .on : .off
        permissionItem.isHidden = status.permitted
        retryNowItem.isEnabled = status.permitted && status.codexRunning
    }

    // MARK: actions

    @objc private func toggleAutoRetry() {
        watcher.setEnabled(!watcher.status.enabled)
    }

    @objc private func toggleDryRun() {
        watcher.setDryRun(!watcher.status.dryRun)
    }

    @objc private func retryNow() {
        logLine("manual retry requested from menu")
        watcher.retryNow()
    }

    @objc private func openAccessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func exportDump() {
        dumpItem.title = "导出中…"
        let config = watcher.config
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = accessibilityDump(all: false, config: config)
            let url = logDirectory.appendingPathComponent("ax-dump.txt")
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            try? result.text.write(to: url, atomically: true, encoding: .utf8)
            logLine("accessibility dump written to \(url.path) (ok=\(result.ok))")
            DispatchQueue.main.async {
                self?.dumpItem.title = "导出无障碍树(诊断)"
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logFileURL.path, contents: Data())
        }
        NSWorkspace.shared.open(logFileURL)
    }

    @objc private func quitApp() {
        watcher.stop()
        NSApp.terminate(nil)
    }
}
