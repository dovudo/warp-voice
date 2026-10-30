import AppKit
import AVFoundation
import ApplicationServices
import UserNotifications

let trigger: CGKeyCode = 50
let marker: Int64 = 0x57415250
func diagnostic(_ message: String) {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WarpVoice", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let file = dir.appendingPathComponent("diagnostic.log")
    if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
    guard let handle = try? FileHandle(forWritingTo: file) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
}
final class VoiceApp: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var tap: CFMachPort?
    var key = HoldKey()
    var timer: Timer?
    var recorder: AVAudioRecorder?
    var audioURL: URL?
    var originalPID: pid_t = 0
    var originalFocus: AXUIElement?
    var busy = false
    var started = false
    var updateItem: NSMenuItem!
    var updateVersion: String?
    var updateInProgress = false
    var updateCheckInProgress = false
    var updateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostic("started")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "🎙"
        let menu = NSMenu()
        menu.addItem(withTitle: "Удерживайте ё / ` для диктовки", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Проверить разрешения", action: #selector(permissions), keyEquivalent: "")
        updateItem = menu.addItem(withTitle: "Проверить обновления…", action: #selector(updateMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        permissions()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.checkUpdates(manual: false) }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in self?.checkUpdates(manual: false) }
    }
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }
    func updateCommand(_ arguments: [String], completion: @escaping (Int32, Data, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let script = Bundle.main.url(forResource: "updater", withExtension: "py") else {
                DispatchQueue.main.async { completion(1, Data(), "Компонент обновления не найден.") }; return
            }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path] + arguments
            let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
            do {
                try process.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let error = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let message = String(data: error, encoding: .utf8) ?? "Ошибка обновления."
                DispatchQueue.main.async { completion(process.terminationStatus, data, message) }
            } catch { DispatchQueue.main.async { completion(1, Data(), "Не удалось запустить проверку обновления.") } }
        }
    }
    func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let box = NSAlert(); box.messageText = title; box.informativeText = message; box.addButton(withTitle: "OK"); box.runModal()
    }
    @objc func updateMenu() {
        if let version = updateVersion { offerUpdate(version) } else { checkUpdates(manual: true) }
    }
    func checkUpdates(manual: Bool) {
        guard !updateCheckInProgress && !updateInProgress else { return }
        updateCheckInProgress = true; updateItem.title = "Проверка обновлений…"
        updateCommand(["check", currentVersion]) { code, data, error in
            self.updateCheckInProgress = false
            guard code == 0, let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.updateItem.title = "Проверить обновления…"
                if manual { self.alert("Не удалось проверить обновления", error) }
                return
            }
            if result["available"] as? Bool == true, let version = result["version"] as? String {
                self.updateVersion = version; self.updateItem.title = "Установить обновление \(version)…"
                if manual { self.offerUpdate(version) }
                else { self.notice("Доступна новая версия Warp Voice", "Откройте меню 🎙, чтобы установить версию \(version).") }
            } else {
                self.updateVersion = nil; self.updateItem.title = "Проверить обновления…"
                if manual { self.alert("Обновлений нет", "Установлена актуальная версия \(self.currentVersion).") }
            }
        }
    }
    func offerUpdate(_ version: String) {
        guard !busy && !started && !updateInProgress else { alert("Дождитесь завершения диктовки", "После обработки можно установить обновление."); return }
        NSApp.activate(ignoringOtherApps: true)
        let box = NSAlert(); box.messageText = "Установить Warp Voice \(version)?"
        box.informativeText = "Приложение скачает релиз с GitHub, проверит его и перезапустится. macOS может запросить разрешения повторно."
        box.addButton(withTitle: "Установить"); box.addButton(withTitle: "Позже")
        guard box.runModal() == .alertFirstButtonReturn else { return }
        updateInProgress = true; updateItem.title = "Загрузка обновления…"; updateItem.isEnabled = false
        updateCommand(["install", Bundle.main.bundleURL.path, currentVersion, version]) { code, _, error in
            self.updateInProgress = false; self.updateItem.isEnabled = true
            guard code == 0 else { self.updateItem.title = "Установить обновление \(version)…"; self.alert("Обновление не установлено", error); return }
            NSApp.terminate(nil)
        }
    }
    @objc func permissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        diagnostic("permissions accessibility=\(trusted) microphone=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                if !granted { self?.notice("Нет доступа к микрофону", "Разрешите микрофон для Warp Voice в настройках macOS.") }
            }
        }
        if trusted { installTap() }
        else {
            notice("Нужен доступ к управлению", "Разрешите Warp Voice в Универсальном доступе, затем выберите «Проверить разрешения» в меню.")
        }
    }
    func installTap() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ref in
            let app = Unmanaged<VoiceApp>.fromOpaque(ref!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return app.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { diagnostic("event tap failed"); notice("Не удалось включить клавишу", "Проверьте разрешения Универсального доступа и Мониторинга ввода."); return }
        diagnostic("event tap installed")
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func synthesize(_ down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: trigger, keyDown: down) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == marker { return true }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if code != trigger {
            if type == .keyDown, key.otherKey() == .typeKey { timer?.invalidate(); synthesize(true) }
            return true
        }
        if type == .keyDown {
            let modified = !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            let action = key.down(modified: modified)
            if action == .pass { return true }
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.30, repeats: false) { [weak self] _ in
                    guard let self else { return }; self.timer = nil
                    if self.key.threshold() == .startRecording { self.startRecording() }
                }
            }
            return false
        }
        timer?.invalidate(); timer = nil
        switch key.up() {
        case .typeKey: synthesize(true); synthesize(false); return false
        case .stopRecording: stopRecording(); return false
        default: return true
        }
    }
    func focused() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func startRecording() {
        diagnostic("recording requested busy=\(busy) microphone=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        guard !busy && !updateInProgress else { notice("Обработка ещё идёт", "Дождитесь завершения текущей операции."); return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { notice("Микрофон недоступен", "Разрешите доступ к микрофону в настройках macOS."); return }
        originalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        originalFocus = focused()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("warpvoice-\(UUID().uuidString).wav")
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else { throw NSError(domain: "Audio", code: 1) }
            audioURL = url; recorder = rec; started = true; status.button?.title = "🔴"
            diagnostic("recording started focus=\(originalFocus != nil) target=\(originalPID != 0)")
        } catch { diagnostic("recording failed \(error.localizedDescription)"); notice("Не удалось записать звук", "Проверьте микрофон и его разрешения.") }
    }
    func stopRecording() {
        guard started, let url = audioURL else { return }
        recorder?.stop(); recorder = nil; started = false; audioURL = nil; busy = true
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? -1
        diagnostic("recording stopped bytes=\(size)")
        status.button?.title = "⏳"
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: url) }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            guard let script = Bundle.main.url(forResource: "transcribe", withExtension: "py") else {
                DispatchQueue.main.async { self.finish(nil, "Не найден компонент распознавания.") }; return
            }
            process.arguments = [script.path, url.path]
            let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let error = String(data: errorData, encoding: .utf8) ?? "Ошибка распознавания."
                diagnostic("transcriber exit=\(process.terminationStatus) textCharacters=\(text?.count ?? 0) error=\(process.terminationStatus == 0 ? "none" : error.trimmingCharacters(in: .whitespacesAndNewlines))")
                DispatchQueue.main.async { self.finish(process.terminationStatus == 0 ? text : nil, error) }
            } catch { DispatchQueue.main.async { self.finish(nil, "Не удалось запустить распознавание.") } }
        }
    }
    func finish(_ text: String?, _ error: String) {
        busy = false; status.button?.title = "🎙"
        guard let text, !text.isEmpty else { notice("Диктовка не удалась", error); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        let sameApp = originalPID != 0 && NSWorkspace.shared.frontmostApplication?.processIdentifier == originalPID
        let current = focused()
        let sameFocus = originalFocus != nil && current != nil && CFEqual(originalFocus, current)
        guard AXIsProcessTrusted(), shouldPaste(sameApp: sameApp, initialFocusKnown: originalFocus != nil, sameFocus: sameFocus) else {
            diagnostic("paste skipped: focus changed or inaccessible; transcript copied")
            notice("Текст в буфере обмена", "Поле ввода изменилось или недоступно. Вставьте текст вручную."); return
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            notice("Текст в буфере обмена", "Не удалось вставить текст автоматически."); return
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        diagnostic("paste shortcut posted; transcript copied")
    }
    func notice(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
let app = NSApplication.shared
let delegate = VoiceApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
