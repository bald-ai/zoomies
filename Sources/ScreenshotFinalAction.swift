/// The five ways a screenshot workflow can finish.
/// Shared by the workflow controller, the editor window, and the canvas so a
/// final-action command means the same thing end to end.
enum ScreenshotFinalAction {
    case saveOnly
    case copyAndSave
    case copyAndDelete
    case deleteOnly
    case closeOnly
}
