#if os(macOS)
import CoreGraphics
import Foundation

public final class GlobalShortcutEngine: @unchecked Sendable {
    public var onKeyDown: (@MainActor (ShortcutAction) -> Void)?
    public var onKeyUp: (@MainActor (ShortcutAction) -> Void)?

    private let store: ShortcutStore
    private let lock = NSLock()
    private var shortcuts: [ShortcutAction: KeyShortcut] = [:]
    private var activeActions: [UInt16: ShortcutAction] = [:]
    private var tapThread: Thread?
    private var tapPort: CFMachPort?
    private var runLoop: CFRunLoop?
    private let timerQueue = DispatchQueue(label: "io.blue.voiceiq.global-shortcuts.timer")
    private var healthTimer: DispatchSourceTimer?
    private var observer: NSObjectProtocol?
    private var startResult: Bool?

    public init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
        reloadShortcuts()
        observer = NotificationCenter.default.addObserver(
            forName: .voiceIQShortcutDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadShortcuts()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        lock.lock()
        if tapThread != nil {
            let running = startResult == true
            lock.unlock()
            return running
        }
        startResult = nil
        let thread = Thread { [weak self] in self?.threadMain() }
        thread.name = "io.blue.voiceiq.global-shortcuts"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        lock.unlock()
        thread.start()

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock()
            let result = startResult
            lock.unlock()
            if let result {
                if result { startHealthTimer() }
                return result
            }
            usleep(10_000)
        }
        return false
    }

    public func stop() {
        healthTimer?.cancel()
        healthTimer = nil
        lock.lock()
        let runLoop = runLoop
        let tapPort = tapPort
        self.runLoop = nil
        self.tapPort = nil
        tapThread = nil
        activeActions.removeAll()
        startResult = nil
        lock.unlock()
        if let runLoop { CFRunLoopStop(runLoop) }
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: false) }
    }

    private func reloadShortcuts() {
        let loaded = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map {
            ($0, store.shortcut(for: $0))
        })
        lock.lock()
        shortcuts = loaded
        lock.unlock()
    }

    private func threadMain() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<GlobalShortcutEngine>.fromOpaque(userInfo).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            lock.lock()
            startResult = false
            tapThread = nil
            lock.unlock()
            Log.hotkey.error("GlobalShortcutEngine: tap creation failed, Accessibility not granted")
            return
        }

        lock.lock()
        tapPort = tap
        runLoop = CFRunLoopGetCurrent()
        startResult = true
        lock.unlock()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.hotkey.info("GlobalShortcutEngine: tap running")
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = tapPort
            lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.hotkey.warning("GlobalShortcutEngine: disabled tap re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != SyntheticEventTag.magic else {
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if ShortcutCapture.isActive {
            // The Settings window is recording a shortcut. Nothing matches and
            // a held action is released, so its key-up never fires an action.
            lock.lock()
            activeActions.removeAll()
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                lock.lock()
                let isActive = activeActions[keyCode] != nil
                lock.unlock()
                return isActive ? nil : Unmanaged.passUnretained(event)
            }
            lock.lock()
            let match = ShortcutAction.allCases.first {
                shortcuts[$0]?.matches(rawFlags: event.flags.rawValue, keyCode: keyCode) == true
            }
            if let match { activeActions[keyCode] = match }
            lock.unlock()
            guard let match else { return Unmanaged.passUnretained(event) }
            Task { @MainActor [weak self] in self?.onKeyDown?(match) }
            return nil
        }

        lock.lock()
        let match = activeActions.removeValue(forKey: keyCode)
        lock.unlock()
        guard let match else { return Unmanaged.passUnretained(event) }
        Task { @MainActor [weak self] in self?.onKeyUp?(match) }
        return nil
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let tap = self.tapPort
            self.lock.unlock()
            if let tap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                Log.hotkey.warning("GlobalShortcutEngine: health poll re-enabled tap")
            }
        }
        timer.resume()
        healthTimer = timer
    }
}
#endif
