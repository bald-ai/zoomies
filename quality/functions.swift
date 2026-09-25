import Foundation
import SwiftParser
import SwiftSyntax

// Swift's own parser supplies exact declaration/body boundaries. Nested
// declarations and closures receive their own rows, not their parent's decisions.
final class Decisions: SyntaxVisitor {
    var complexity = 1
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: SwitchCaseLabelSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind { complexity += 1; return .visitChildren }
    override func visit(_ node: ConditionElementListSyntax) -> SyntaxVisitorContinueKind {
        complexity += max(0, node.count - 1); return .visitChildren
    }
    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if ["&&", "||", "??"].contains(node.operator.text) { complexity += 1 }
        return .visitChildren
    }
}
final class Functions: SyntaxVisitor {
    let converter: SourceLocationConverter
    let path: String
    var rows: [[String: Any]] = []
    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    func record(_ node: some SyntaxProtocol, body: some SyntaxProtocol, name: String, kind: String) {
        let decisions = Decisions()
        decisions.walk(body)
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        let bodyStart = converter.location(for: body.positionAfterSkippingLeadingTrivia)
        rows.append(["file": path, "name": name, "kind": kind, "start_line": start.line,
                     "start_column": start.column, "end_line": end.line, "end_column": end.column,
                     "body_start_line": bodyStart.line, "complexity": decisions.complexity])
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { record(node, body: body, name: node.name.text, kind: "function") }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { record(node, body: body, name: "init", kind: "initializer") }
        return .visitChildren
    }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { record(node, body: body, name: "deinit", kind: "deinitializer") }
        return .visitChildren
    }
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { record(node, body: body, name: node.accessorSpecifier.text, kind: "accessor") }
        return .visitChildren
    }
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        if case .getter(let body) = node.accessors { record(node, body: body, name: "implicit getter", kind: "getter") }
        return .visitChildren
    }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        record(node, body: node.statements, name: "closure", kind: "closure")
        return .visitChildren
    }
}
var rows: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let tree = Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8))
    let visitor = Functions(path: path, tree: tree)
    visitor.walk(tree)
    rows += visitor.rows
}
let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
