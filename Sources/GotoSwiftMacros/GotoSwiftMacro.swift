import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostics

struct GotoDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(message: String, id: String = "goto-error", severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GotoSwift", id: id)
        self.severity = severity
    }
}

struct LineInfo {
    let number: Int
    var statements: [CodeBlockItemSyntax]
}

struct BasicLine {
    let number: Int
    let rawCode: String
}

struct ForLoopRecord {
    let varName: String
    let forLine: Int
    let bodyLine: Int
    var nextLine: Int
    var exitLine: Int
}

// MARK: - GotoScopeMacro

public struct GotoScopeMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let closure = node.trailingClosure ?? node.arguments.first?.expression.as(ClosureExprSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: GotoDiagnostic(message: "#gotoScope requires a trailing closure or closure argument")
                )
            )
            return "()"
        }

        return expandGotoScope(closure: closure, macroNode: node, context: context)
    }

    private static func expandGotoScope(
        closure: ClosureExprSyntax,
        macroNode: some FreestandingMacroExpansionSyntax,
        context: some MacroExpansionContext
    ) -> ExprSyntax {
        var lines: [LineInfo] = []
        var currentLineNumber: Int? = nil
        var currentStatements: [CodeBlockItemSyntax] = []

        func flushCurrentLine() {
            if let lineNum = currentLineNumber {
                if let index = lines.firstIndex(where: { $0.number == lineNum }) {
                    if currentStatements.isEmpty {
                        // Empty line deletes the existing line
                        lines.remove(at: index)
                    } else {
                        // Re-defining a line overwrites the previous definition
                        lines[index].statements = currentStatements
                    }
                } else if !currentStatements.isEmpty {
                    lines.append(LineInfo(number: lineNum, statements: currentStatements))
                }
            } else if !currentStatements.isEmpty {
                // Statements before any line number become line 0
                lines.append(LineInfo(number: 0, statements: currentStatements))
            }
            currentStatements = []
        }

        for item in closure.statements {
            // Check if item is a line marker function call: line(10), L(10), _line(10)
            if let call = item.item.as(FunctionCallExprSyntax.self),
               let calledId = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
               ["line", "L", "_line"].contains(calledId),
               let firstArg = call.arguments.first?.expression.as(IntegerLiteralExprSyntax.self),
               let lineVal = Int(firstArg.literal.text) {
                flushCurrentLine()
                currentLineNumber = lineVal
                continue
            }

            // Check if item is a labeled statement, e.g. `_10: do { ... }` or `L10: ...`
            if let labeled = item.item.as(LabeledStmtSyntax.self),
               let lineVal = parseLineFromLabel(labeled.label.text) {
                flushCurrentLine()
                currentLineNumber = lineVal
                // If the labeled statement is a `do` block, unpack its statements
                if let doStmt = labeled.statement.as(DoStmtSyntax.self) {
                    currentStatements.append(contentsOf: doStmt.body.statements)
                } else {
                    currentStatements.append(CodeBlockItemSyntax(item: .stmt(labeled.statement)))
                }
                flushCurrentLine()
                currentLineNumber = nil
                continue
            }

            currentStatements.append(item)
        }
        flushCurrentLine()

        if lines.isEmpty {
            return "{ }() "
        }

        // Sort lines by line number ascending
        lines.sort { $0.number < $1.number }
        let definedLineNumbers = Set(lines.map { $0.number })
        let sortedLineNumbers = lines.map { $0.number }

        // 2. Validate jump targets and collect variable declarations for hoisting
        var hoistedDecls: [String] = []

        // Extract hoisted variables
        for line in lines {
            for item in line.statements {
                if let varDecl = item.item.as(VariableDeclSyntax.self) {
                    hoistedDecls.append(varDecl.trimmedDescription)
                }
            }
        }

        // Validate jump targets
        for line in lines {
            for item in line.statements {
                validateJumps(item: item, definedLines: definedLineNumbers, context: context)
            }
        }

        // 3. Generate Switch Cases
        var caseBlocks: [String] = []

        for (index, line) in lines.enumerated() {
            let nextLineNumber: Int? = (index + 1 < lines.count) ? lines[index + 1].number : nil
            var transformedStmts: [CodeBlockItemSyntax] = []

            for item in line.statements {
                if let varDecl = item.item.as(VariableDeclSyntax.self) {
                    // Turn `var x = expr` into `x = expr` inside the case
                    for binding in varDecl.bindings {
                        let name = binding.pattern.trimmedDescription
                        if let initVal = binding.initializer?.value {
                            let assignExpr: ExprSyntax = "\(raw: name) = \(initVal)"
                            transformedStmts.append(CodeBlockItemSyntax(item: .expr(assignExpr)))
                        }
                    }
                } else {
                    transformedStmts.append(item)
                }
            }

            let rewriter = StatementRewriter(nextLineNumber: nextLineNumber)
            let rewrittenList = rewriter.visit(CodeBlockItemListSyntax(transformedStmts))
            var rewrittenItems = rewrittenList.map { $0.trimmedDescription }

            // Fallthrough handling: if line does not explicitly end with goto/return/end
            let lastText = rewrittenList.last?.trimmedDescription ?? ""
            let endsWithExit = lastText.hasSuffix("continue _loop") ||
                               lastText.hasSuffix("break _loop") ||
                               lastText.contains("returnLine") ||
                               lastText.contains("_callStack.popLast()")

            if !endsWithExit {
                if let next = nextLineNumber {
                    rewrittenItems.append("_line = \(next)\ncontinue _loop")
                } else {
                    rewrittenItems.append("break _loop")
                }
            }

            let indentedBody = rewrittenItems
                .joined(separator: "\n")
                .components(separatedBy: .newlines)
                .map { "        \($0)" }
                .joined(separator: "\n")

            caseBlocks.append("""
                case \(line.number):
            \(indentedBody)
            """)
        }

        let firstLine = sortedLineNumbers.first ?? 0
        let hoistedSection = hoistedDecls.isEmpty ? "" : hoistedDecls.map { "    \($0)" }.joined(separator: "\n") + "\n"
        let allCases = caseBlocks.joined(separator: "\n")

        return """
        {
        \(raw: hoistedSection)    var _line: Int = \(raw: String(firstLine))
            var _callStack: [Int] = []
            _callStack.removeAll()
            _loop: while true {
                switch _line {
        \(raw: allCases)
                default:
                    break _loop
                }
            }
        }()
        """
    }

    private static func parseLineFromLabel(_ label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        if let direct = Int(trimmed) { return direct }
        if trimmed.hasPrefix("_"), let num = Int(trimmed.dropFirst()) { return num }
        if trimmed.hasPrefix("L"), let num = Int(trimmed.dropFirst()) { return num }
        if trimmed.hasPrefix("line_"), let num = Int(trimmed.dropFirst(5)) { return num }
        return nil
    }

    private static func validateJumps(
        item: CodeBlockItemSyntax,
        definedLines: Set<Int>,
        context: some MacroExpansionContext
    ) {
        let checker = JumpValidator(definedLines: definedLines, context: context)
        checker.walk(item)
    }

    private static func rewriteStatement(item: CodeBlockItemSyntax, nextLineNumber: Int?) -> String {
        let rewriter = StatementRewriter(nextLineNumber: nextLineNumber)
        let transformed = rewriter.rewrite(item)
        return transformed.trimmedDescription
    }
}

// MARK: - AST Visitors for Validation and Rewriting

private class JumpValidator: SyntaxVisitor {
    let definedLines: Set<Int>
    let context: any MacroExpansionContext

    init(definedLines: Set<Int>, context: any MacroExpansionContext) {
        self.definedLines = definedLines
        self.context = context
        super.init(viewMode: .all)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let id = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text {
            if ["goto", "gosub"].contains(id),
               let firstArg = node.arguments.first?.expression.as(IntegerLiteralExprSyntax.self),
               let target = Int(firstArg.literal.text) {
                if !definedLines.contains(target) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(firstArg),
                            message: GotoDiagnostic(message: "Target line number \(target) does not exist")
                        )
                    )
                }
            }
        }
        return .visitChildren
    }
}

private class StatementRewriter: SyntaxRewriter {
    let nextLineNumber: Int?

    init(nextLineNumber: Int?) {
        self.nextLineNumber = nextLineNumber
        super.init()
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        var newItems: [CodeBlockItemSyntax] = []
        for item in node {
            if let call = item.item.as(FunctionCallExprSyntax.self),
               let id = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text {
                if id == "goto", let arg = call.arguments.first?.expression {
                    let stmts: CodeBlockItemListSyntax = """
                    _line = \(arg)
                    continue _loop
                    """
                    newItems.append(contentsOf: stmts)
                    continue
                } else if id == "gosub", let arg = call.arguments.first?.expression {
                    let next = nextLineNumber ?? 0
                    let stmts: CodeBlockItemListSyntax = """
                    _callStack.append(\(raw: String(next)))
                    _line = \(arg)
                    continue _loop
                    """
                    newItems.append(contentsOf: stmts)
                    continue
                } else if id == "returnLine" {
                    let stmts: CodeBlockItemListSyntax = """
                    if let _ret = _callStack.popLast() {
                        _line = _ret
                        continue _loop
                    } else {
                        break _loop
                    }
                    """
                    newItems.append(contentsOf: stmts)
                    continue
                } else if id == "end" {
                    let stmts: CodeBlockItemListSyntax = """
                    break _loop
                    """
                    newItems.append(contentsOf: stmts)
                    continue
                }
            }

            // Recurse into children (like if conditions, loops, etc.)
            newItems.append(self.visit(item))
        }
        return CodeBlockItemListSyntax(newItems)
    }
}

// MARK: - BasicMacro

public struct BasicMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let firstArg = node.arguments.first?.expression.as(StringLiteralExprSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: GotoDiagnostic(message: "#basic requires a string literal argument")
                )
            )
            return "()"
        }

        // Extract string content
        var codeString = ""
        for segment in firstArg.segments {
            if let strSegment = segment.as(StringSegmentSyntax.self) {
                codeString += strSegment.content.text
            }
        }

        return expandBasic(source: codeString, macroNode: node, context: context)
    }

    private static func expandBasic(
        source: String,
        macroNode: some FreestandingMacroExpansionSyntax,
        context: some MacroExpansionContext
    ) -> ExprSyntax {
        var lines: [BasicLine] = []
        let rawLines = source.components(separatedBy: .newlines)

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                continue
            }

            // Parse leading line number
            let scanner = Scanner(string: trimmed)
            var lineNum: Int = 0
            if scanner.scanInt(&lineNum) {
                let rest = scanner.string[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)
                if let existingIndex = lines.firstIndex(where: { $0.number == lineNum }) {
                    if rest.isEmpty {
                        // Vintage BASIC: typing just the line number deletes the line!
                        lines.remove(at: existingIndex)
                    } else {
                        // Vintage BASIC: re-typing a line number overwrites the old line!
                        lines[existingIndex] = BasicLine(number: lineNum, rawCode: rest)
                    }
                } else if !rest.isEmpty {
                    lines.append(BasicLine(number: lineNum, rawCode: rest))
                }
            } else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(macroNode),
                        message: GotoDiagnostic(message: "BASIC line must start with a line number: '\(trimmed)'")
                    )
                )
            }
        }

        if lines.isEmpty {
            return "{ }()"
        }

        lines.sort { $0.number < $1.number }
        let definedLineNumbers = Set(lines.map { $0.number })
        let sortedLineNumbers = lines.map { $0.number }

        // Track variables
        var numVariables = Set<String>()
        var strVariables = Set<String>()

        // Pre-scan for FOR ... NEXT pairings
        var forLoopsByForLine: [Int: ForLoopRecord] = [:]
        var forLoopsByNextLine: [Int: ForLoopRecord] = [:]
        var forStack: [(varName: String, forLine: Int, bodyLine: Int)] = []

        for (index, bLine) in lines.enumerated() {
            let trimmed = bLine.rawCode.trimmingCharacters(in: .whitespaces)
            let nextLineNum: Int = (index + 1 < lines.count) ? lines[index + 1].number : 0
            if trimmed.uppercased().hasPrefix("FOR ") {
                let afterFor = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if let eqIdx = afterFor.firstIndex(of: "=") {
                    let v = String(afterFor[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                    let (swiftVar, _) = normalizeVarName(v)
                    numVariables.insert(swiftVar)
                    forStack.append((varName: swiftVar, forLine: bLine.number, bodyLine: nextLineNum))
                }
            } else if trimmed.uppercased() == "NEXT" || trimmed.uppercased().hasPrefix("NEXT ") {
                let afterNext = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                let requestedVar = afterNext.isEmpty ? nil : normalizeVarName(afterNext).0

                if let top = forStack.popLast() {
                    if let req = requestedVar, req != top.varName {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(macroNode),
                                message: GotoDiagnostic(message: "Mismatched NEXT \(req), expected NEXT \(top.varName) on line \(bLine.number)")
                            )
                        )
                    }
                    let exitLine = nextLineNum
                    let record = ForLoopRecord(varName: top.varName, forLine: top.forLine, bodyLine: top.bodyLine, nextLine: bLine.number, exitLine: exitLine)
                    forLoopsByForLine[top.forLine] = record
                    forLoopsByNextLine[bLine.number] = record
                } else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(macroNode),
                            message: GotoDiagnostic(message: "NEXT without FOR on line \(bLine.number)")
                        )
                    )
                }
            }
        }

        for remaining in forStack {
            context.diagnose(
                Diagnostic(
                    node: Syntax(macroNode),
                    message: GotoDiagnostic(message: "FOR without matching NEXT for variable '\(remaining.varName)' on line \(remaining.forLine)")
                )
            )
        }

        // Generate case bodies
        var caseBlocks: [String] = []

        for (index, bLine) in lines.enumerated() {
            let nextLineNumber: Int? = (index + 1 < lines.count) ? lines[index + 1].number : nil
            let translated = translateBasicStatement(
                bLine.rawCode,
                currentLine: bLine.number,
                nextLineNumber: nextLineNumber,
                definedLineNumbers: definedLineNumbers,
                forLoopsByForLine: forLoopsByForLine,
                forLoopsByNextLine: forLoopsByNextLine,
                macroNode: macroNode,
                context: context,
                numVars: &numVariables,
                strVars: &strVariables
            )

            let trimmedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsWithExit = trimmedTranslated.hasSuffix("continue _loop") ||
                               trimmedTranslated.hasSuffix("break _loop") ||
                               trimmedTranslated.contains("_callStack.popLast()")

            var statements = [translated]
            if !endsWithExit {
                if let next = nextLineNumber {
                    statements.append("_line = \(next)\ncontinue _loop")
                } else {
                    statements.append("break _loop")
                }
            }

            let indentedBody = statements
                .joined(separator: "\n")
                .components(separatedBy: .newlines)
                .map { "        \($0)" }
                .joined(separator: "\n")

            caseBlocks.append("""
                case \(bLine.number):
            \(indentedBody)
            """)
        }

        // Hoist variable declarations
        var hoistedDecls: [String] = []
        for v in numVariables.sorted() {
            hoistedDecls.append("var \(v): Double = 0")
        }
        let forVarNames = Set(forLoopsByForLine.values.map { $0.varName })
        for v in forVarNames.sorted() {
            hoistedDecls.append("var _for_\(v)_end: Double = 0")
            hoistedDecls.append("var _for_\(v)_step: Double = 1")
        }
        for v in strVariables.sorted() {
            hoistedDecls.append("var \(v): String = \"\"")
        }

        let firstLine = sortedLineNumbers.first ?? 0
        let hoistedSection = hoistedDecls.isEmpty ? "" : hoistedDecls.map { "    \($0)" }.joined(separator: "\n") + "\n"
        let allCases = caseBlocks.joined(separator: "\n")

        return """
        {
        \(raw: hoistedSection)    var _line: Int = \(raw: String(firstLine))
            var _callStack: [Int] = []
            _callStack.removeAll()
            _loop: while true {
                switch _line {
        \(raw: allCases)
                default:
                    break _loop
                }
            }
        }()
        """
    }

    private static func translateBasicStatement(
        _ code: String,
        currentLine: Int,
        nextLineNumber: Int?,
        definedLineNumbers: Set<Int>,
        forLoopsByForLine: [Int: ForLoopRecord],
        forLoopsByNextLine: [Int: ForLoopRecord],
        macroNode: some FreestandingMacroExpansionSyntax,
        context: some MacroExpansionContext,
        numVars: inout Set<String>,
        strVars: inout Set<String>
    ) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)

        if trimmed.uppercased().hasPrefix("REM") {
            return "// \(trimmed)"
        }

        if trimmed.uppercased().hasPrefix("GOTO") {
            let targetStr = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let target = Int(targetStr) {
                if !definedLineNumbers.contains(target) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(macroNode),
                            message: GotoDiagnostic(message: "GOTO target line \(target) on line \(currentLine) does not exist")
                        )
                    )
                }
                return "_line = \(target)\ncontinue _loop"
            }
        }

        if trimmed.uppercased().hasPrefix("GOSUB") {
            let targetStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let target = Int(targetStr) {
                if !definedLineNumbers.contains(target) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(macroNode),
                            message: GotoDiagnostic(message: "GOSUB target line \(target) on line \(currentLine) does not exist")
                        )
                    )
                }
                let next = nextLineNumber ?? 0
                return """
                _callStack.append(\(next))
                _line = \(target)
                continue _loop
                """
            }
        }

        if trimmed.uppercased() == "RETURN" {
            return """
            if let _ret = _callStack.popLast() {
                _line = _ret
                continue _loop
            } else {
                break _loop
            }
            """
        }

        if trimmed.uppercased() == "END" || trimmed.uppercased() == "STOP" {
            return "break _loop"
        }

        // CLS / HOME
        if trimmed.uppercased() == "CLS" {
            return #"print("\u{001B}[2J\u{001B}[H", terminator: "")"#
        }
        if trimmed.uppercased() == "HOME" {
            return #"print("\u{001B}[H", terminator: "")"#
        }

        // FOR var = start TO end [STEP step]
        if trimmed.uppercased().hasPrefix("FOR ") {
            if let record = forLoopsByForLine[currentLine] {
                let afterFor = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if let eqIdx = afterFor.firstIndex(of: "=") {
                    let rhs = afterFor[afterFor.index(after: eqIdx)...]
                    if let toRange = rhs.range(of: " TO ", options: .caseInsensitive) {
                        let startPart = String(rhs[..<toRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let afterTo = rhs[toRange.upperBound...]
                        var endPart = String(afterTo).trimmingCharacters(in: .whitespaces)
                        var stepPart = "1"
                        if let stepRange = afterTo.range(of: " STEP ", options: .caseInsensitive) {
                            endPart = String(afterTo[..<stepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                            stepPart = String(afterTo[stepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        }
                        let startExpr = translateExpr(startPart, numVars: &numVars, strVars: &strVars)
                        let endExpr = translateExpr(endPart, numVars: &numVars, strVars: &strVars)
                        let stepExpr = translateExpr(stepPart, numVars: &numVars, strVars: &strVars)
                        let v = record.varName
                        let exitLine = record.exitLine
                        return """
                        \(v) = \(startExpr)
                        _for_\(v)_end = \(endExpr)
                        _for_\(v)_step = \(stepExpr)
                        if (_for_\(v)_step > 0 && \(v) > _for_\(v)_end) || (_for_\(v)_step < 0 && \(v) < _for_\(v)_end) {
                            _line = \(exitLine)
                            continue _loop
                        }
                        """
                    }
                }
            }
        }

        // NEXT [var]
        if trimmed.uppercased() == "NEXT" || trimmed.uppercased().hasPrefix("NEXT ") {
            if let record = forLoopsByNextLine[currentLine] {
                let v = record.varName
                let bodyLine = record.bodyLine
                return """
                \(v) += _for_\(v)_step
                if (_for_\(v)_step > 0 && \(v) <= _for_\(v)_end) || (_for_\(v)_step < 0 && \(v) >= _for_\(v)_end) {
                    _line = \(bodyLine)
                    continue _loop
                }
                """
            }
        }

        // PRINT or ?
        if trimmed.uppercased().hasPrefix("PRINT") || trimmed.hasPrefix("?") {
            let rest: String
            if trimmed.hasPrefix("?") {
                rest = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            } else {
                rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            if rest.isEmpty {
                return "print()"
            }
            return translatePrint(rest, numVars: &numVars, strVars: &strVars)
        }

        // LINE INPUT
        if trimmed.uppercased().hasPrefix("LINE INPUT") {
            let rest = trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces)
            return translateInput(rest, isLineInput: true, numVars: &numVars, strVars: &strVars)
        }

        // INPUT
        if trimmed.uppercased().hasPrefix("INPUT") {
            let rest = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return translateInput(rest, isLineInput: false, numVars: &numVars, strVars: &strVars)
        }

        // IF cond THEN ...
        if trimmed.uppercased().hasPrefix("IF") {
            let afterIf = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let thenRange = afterIf.range(of: "THEN", options: .caseInsensitive) {
                let condPart = String(afterIf[..<thenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let thenPart = String(afterIf[thenRange.upperBound...]).trimmingCharacters(in: .whitespaces)

                let swiftCond = translateCondition(condPart, numVars: &numVars, strVars: &strVars)
                let thenStmt = translateBasicStatement(
                    thenPart,
                    currentLine: currentLine,
                    nextLineNumber: nextLineNumber,
                    definedLineNumbers: definedLineNumbers,
                    forLoopsByForLine: forLoopsByForLine,
                    forLoopsByNextLine: forLoopsByNextLine,
                    macroNode: macroNode,
                    context: context,
                    numVars: &numVars,
                    strVars: &strVars
                )
                return "if \(swiftCond) {\n    \(thenStmt)\n}"
            }
        }

        // LET var = expr or var = expr
        var assignCode = trimmed
        if assignCode.uppercased().hasPrefix("LET") {
            assignCode = assignCode.dropFirst(3).trimmingCharacters(in: .whitespaces)
        }

        if let eqIdx = assignCode.firstIndex(of: "=") {
            let lhs = String(assignCode[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let rhs = String(assignCode[assignCode.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)

            let (swiftVar, isStr) = normalizeVarName(lhs)
            if isStr {
                strVars.insert(swiftVar)
            } else {
                numVars.insert(swiftVar)
            }
            let swiftExpr = translateExpr(rhs, numVars: &numVars, strVars: &strVars)
            return "\(swiftVar) = \(swiftExpr)"
        }

        return "// Unrecognized BASIC statement: \(trimmed)"
    }

    private static func normalizeVarName(_ name: String) -> (String, Bool) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if clean.hasSuffix("$") {
            let base = clean.dropLast()
            return ("\(base)_str", true)
        }
        return (clean, false)
    }

    private static func translateCondition(_ cond: String, numVars: inout Set<String>, strVars: inout Set<String>) -> String {
        var c = cond
        // Replace single = with == (avoiding <= and >=)
        c = c.replacingOccurrences(of: "<>", with: "!=")
        c = c.replacingOccurrences(of: "<=", with: "__LE__")
        c = c.replacingOccurrences(of: ">=", with: "__GE__")
        c = c.replacingOccurrences(of: "==", with: "__EQ__")
        c = c.replacingOccurrences(of: "=", with: "==")
        c = c.replacingOccurrences(of: "__LE__", with: "<=")
        c = c.replacingOccurrences(of: "__GE__", with: ">=")
        c = c.replacingOccurrences(of: "__EQ__", with: "==")
        return translateExpr(c, numVars: &numVars, strVars: &strVars)
    }

    private static func translateExpr(_ expr: String, numVars: inout Set<String>, strVars: inout Set<String>) -> String {
        var result = ""
        var currentToken = ""
        var inQuotes = false

        func flushToken() {
            if currentToken.isEmpty { return }
            if currentToken.hasSuffix("$") {
                let (v, _) = normalizeVarName(currentToken)
                strVars.insert(v)
                result += v
            } else if Double(currentToken) != nil {
                result += currentToken
            } else if ["+", "-", "*", "/", "(", ")", "==", "!=", "<", ">", "<=", ">="].contains(currentToken) {
                result += currentToken
            } else if currentToken.uppercased() == "AND" {
                result += "&&"
            } else if currentToken.uppercased() == "OR" {
                result += "||"
            } else if currentToken.uppercased() == "NOT" {
                result += "!"
            } else {
                let (v, isStr) = normalizeVarName(currentToken)
                if isStr { strVars.insert(v) } else { numVars.insert(v) }
                result += v
            }
            currentToken = ""
        }

        for char in expr {
            if char == "\"" {
                inQuotes.toggle()
                result.append(char)
                continue
            }
            if inQuotes {
                result.append(char)
                continue
            }

            if char.isWhitespace || ["+", "-", "*", "/", "(", ")", "=", "<", ">", "!"].contains(char) {
                flushToken()
                result.append(char)
            } else {
                currentToken.append(char)
            }
        }
        flushToken()
        return result
    }

    private static func translatePrint(_ argsStr: String, numVars: inout Set<String>, strVars: inout Set<String>) -> String {
        var parts: [String] = []
        var cur = ""
        var inQuotes = false

        for char in argsStr {
            if char == "\"" {
                inQuotes.toggle()
                cur.append(char)
                continue
            }
            if inQuotes {
                cur.append(char)
                continue
            }

            if char == ";" || char == "," {
                let trimmed = cur.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    parts.append(translateExpr(trimmed, numVars: &numVars, strVars: &strVars))
                }
                cur = ""
            } else {
                cur.append(char)
            }
        }
        let trimmed = cur.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(translateExpr(trimmed, numVars: &numVars, strVars: &strVars))
        }

        let hasTrailingSemicolon = argsStr.trimmingCharacters(in: .whitespaces).hasSuffix(";")
        if parts.isEmpty {
            return hasTrailingSemicolon ? "" : "print()"
        }
        let partsJoined = parts.joined(separator: ", ")

        if hasTrailingSemicolon {
            return "print(\(partsJoined), separator: \"\", terminator: \"\")"
        } else {
            return "print(\(partsJoined), separator: \"\")"
        }
    }

    private static func translateInput(
        _ code: String,
        isLineInput: Bool,
        numVars: inout Set<String>,
        strVars: inout Set<String>
    ) -> String {
        var rest = code.trimmingCharacters(in: .whitespaces)
        var prompt = "? "
        var appendQuestionMark = true

        if rest.hasPrefix("\"") {
            let afterFirstQuote = rest.dropFirst()
            if let closingQuoteIdx = afterFirstQuote.firstIndex(of: "\"") {
                let promptText = String(afterFirstQuote[..<closingQuoteIdx])
                let afterQuote = afterFirstQuote[afterFirstQuote.index(after: closingQuoteIdx)...].trimmingCharacters(in: .whitespaces)
                if afterQuote.hasPrefix(";") {
                    appendQuestionMark = true
                    rest = String(afterQuote.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if afterQuote.hasPrefix(",") {
                    appendQuestionMark = false
                    rest = String(afterQuote.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else {
                    rest = afterQuote
                }
                prompt = promptText + (appendQuestionMark ? "? " : "")
            }
        }

        let varNames = rest.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if varNames.isEmpty {
            return "print(\"\(prompt)\", terminator: \"\")"
        }

        if isLineInput || varNames.count == 1 {
            let rawVar = varNames[0]
            let (v, isStr) = normalizeVarName(rawVar)
            if isStr {
                strVars.insert(v)
                return """
                print(\"\(prompt)\", terminator: \"\")
                if let _in = readLine() {
                    \(v) = _in
                }
                """
            } else {
                numVars.insert(v)
                return """
                print(\"\(prompt)\", terminator: \"\")
                if let _in = readLine(), let _val = Double(_in.trimmingCharacters(in: .whitespaces)) {
                    \(v) = _val
                }
                """
            }
        } else {
            var assigns: [String] = []
            for (idx, rawVar) in varNames.enumerated() {
                let (v, isStr) = normalizeVarName(rawVar)
                if isStr {
                    strVars.insert(v)
                    assigns.append("if _parts.count > \(idx) { \(v) = _parts[\(idx)] }")
                } else {
                    numVars.insert(v)
                    assigns.append("if _parts.count > \(idx), let _v = Double(_parts[\(idx)]) { \(v) = _v }")
                }
            }
            let assignsJoined = assigns.joined(separator: "\n    ")
            return """
            print(\"\(prompt)\", terminator: \"\")
            if let _in = readLine() {
                let _parts = _in.components(separatedBy: \",\").map { $0.trimmingCharacters(in: .whitespaces) }
                \(assignsJoined)
            }
            """
        }
    }
}

// MARK: - Compiler Plugin

@main
struct GotoSwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GotoScopeMacro.self,
        BasicMacro.self,
    ]
}
