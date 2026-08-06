struct UserCommandGate {
    private(set) var isScratchpadOpenRequested = false

    mutating func beginScratchpadOpenRequest() -> Bool {
        guard !isScratchpadOpenRequested else { return false }
        isScratchpadOpenRequested = true
        return true
    }

    mutating func finishScratchpadOpenRequest() {
        isScratchpadOpenRequested = false
    }

    func canStartScreenshot(scratchpadIsBusy: Bool) -> Bool {
        !isScratchpadOpenRequested && !scratchpadIsBusy
    }
}
