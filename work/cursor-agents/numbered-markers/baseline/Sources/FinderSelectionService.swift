import Foundation

/// Fetches the currently selected item in Finder via AppleScript.
///
/// Note: this requires the user to allow the app to control Finder
/// in System Settings > Privacy & Security > Automation.
enum FinderSelectionService {
    enum Selection: Equatable {
        case none
        case multiple(count: Int)
        case single(url: URL)
    }

    /// Returns Finder selection state (none / multiple / single file URL).
    static func selection(scriptRunner: (String) throws -> String = runAppleScriptReturningString) throws -> Selection {
        // Finder can report no selection when it is not frontmost, especially for
        // Desktop icons. Try once passively, then bring Finder forward and retry.
        let scriptNoBringToFront = """
        tell application "Finder"
            try
                set s to (get selection)
                set n to (count of s)
                if n is 0 then return "NONE"
                if n is not 1 then return "MULTI:" & n
                set theItem to item 1 of s
                return "ONE:" & POSIX path of (theItem as alias)
            on error
                return "NONE"
            end try
        end tell
        """

        let scriptBringToFront = """
        tell application "Finder"
            set visible to true
            set frontmost to true
            activate
            delay 0.15
            try
                set s to (get selection)
                set n to (count of s)
                if n is 0 then return "NONE"
                if n is not 1 then return "MULTI:" & n
                set theItem to item 1 of s
                return "ONE:" & POSIX path of (theItem as alias)
            on error
                return "NONE"
            end try
        end tell
        """

        let raw1 = try scriptRunner(scriptNoBringToFront)
        let parsed1 = FinderSelectionParser.parseSelectionResult(raw1)
        switch parsed1 {
        case .none:
            break
        case .multiple, .single:
            return parsed1
        }

        let raw2 = try scriptRunner(scriptBringToFront)
        let parsed2 = FinderSelectionParser.parseSelectionResult(raw2)
        switch parsed2 {
        case .none:
            return .none
        case .multiple, .single:
            return parsed2
        }
    }

    private static func runAppleScriptReturningString(_ source: String) throws -> String {
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw NSError(domain: "FinderSelectionService",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript."])
        }

        let result = appleScript.executeAndReturnError(&errorDict)

        if let errorDict = errorDict {
            let message = (errorDict[NSAppleScript.errorMessage] as? String)
                ?? (errorDict["NSAppleScriptErrorMessage"] as? String)
                ?? "Unknown AppleScript error."
            throw NSError(domain: "FinderSelectionService",
                          code: -2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }

        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

}

enum FinderSelectionLookupError: Error, Equatable {
    case timeout

    var asNSError: NSError {
        NSError(
            domain: "FinderSelectionService",
            code: -3,
            userInfo: [
                NSLocalizedDescriptionKey: "Finder didn’t respond in time. Select an image file and try the shortcut again."
            ]
        )
    }
}

/// Looks up the current Finder selection off the main UI thread, with a short
/// deadline and single-flight gating so a hung AppleScript cannot freeze the app
/// or stack duplicate lookups.
final class FinderSelectionLookupCoordinator {
    static let defaultTimeout: TimeInterval = 3

    typealias SelectionRunner = () throws -> FinderSelectionService.Selection
    typealias Completion = (Result<FinderSelectionService.Selection, Error>) -> Void

    /// True while an AppleScript worker is still alive, including after the
    /// user-facing timeout has already been delivered.
    private(set) var isLookupInProgress = false
    var timeout: TimeInterval
    var executeOffMain: (@escaping () -> Void) -> Void
    var scheduleTimeout: (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void
    var deliverOnMain: (@escaping () -> Void) -> Void

    private var lookupGeneration: UInt64 = 0
    private var didDeliverCurrentLookup = false

    init(
        timeout: TimeInterval = FinderSelectionLookupCoordinator.defaultTimeout,
        executeOffMain: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        },
        scheduleTimeout: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        deliverOnMain: @escaping (@escaping () -> Void) -> Void = { work in
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async(execute: work)
            }
        }
    ) {
        self.timeout = timeout
        self.executeOffMain = executeOffMain
        self.scheduleTimeout = scheduleTimeout
        self.deliverOnMain = deliverOnMain
    }

    /// Starts a Finder selection lookup if one is not already pending.
    /// Duplicate requests while a lookup is in flight are ignored.
    func requestSelection(
        runSelection: @escaping SelectionRunner = { try FinderSelectionService.selection() },
        completion: @escaping Completion
    ) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.requestSelection(runSelection: runSelection, completion: completion)
            }
            return
        }

        guard !isLookupInProgress else { return }

        isLookupInProgress = true
        didDeliverCurrentLookup = false
        lookupGeneration += 1
        let generation = lookupGeneration

        executeOffMain { [weak self] in
            let result = Result { try runSelection() }
            self?.deliverOnMain {
                self?.finishWorker(generation: generation, result: result, completion: completion)
            }
        }

        scheduleTimeout(timeout) { [weak self] in
            self?.deliverTimeout(generation: generation, completion: completion)
        }
    }

    /// Delivers the retryable timeout once. The worker gate stays closed until
    /// that AppleScript actually returns, so a retry cannot start a second hung lookup.
    private func deliverTimeout(generation: UInt64, completion: Completion) {
        guard generation == lookupGeneration, !didDeliverCurrentLookup else { return }
        didDeliverCurrentLookup = true
        completion(.failure(FinderSelectionLookupError.timeout.asNSError))
    }

    private func finishWorker(generation: UInt64,
                              result: Result<FinderSelectionService.Selection, Error>,
                              completion: Completion) {
        guard generation == lookupGeneration else { return }
        isLookupInProgress = false
        guard !didDeliverCurrentLookup else { return }
        didDeliverCurrentLookup = true
        completion(result)
    }
}

enum FinderSelectionParser {
    static func parseSelectionResult(_ raw: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> FinderSelectionService.Selection {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "NONE" {
            return .none
        }

        if value.hasPrefix("MULTI:") {
            let num = value.dropFirst("MULTI:".count)
            let count = Int(num) ?? 2
            return .multiple(count: max(2, count))
        }

        if value.hasPrefix("ONE:") {
            let path = String(value.dropFirst("ONE:".count))
            if let url = urlFromPath(path, fileExists: fileExists) {
                return .single(url: url)
            }
            return .none
        }

        // Unexpected output; treat as none.
        return .none
    }

    private static func urlFromPath(_ path: String, fileExists: (String) -> Bool) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard fileExists(trimmed) else { return nil }
        return URL(fileURLWithPath: trimmed)
    }
}
