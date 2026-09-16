import Foundation
import GotoSwift

// MARK: - Retro BASIC Interactive REPL

class BasicInterpreter {
    var programLines: [Int: String] = [:]
    var numVars: [String: Double] = [:]
    var strVars: [String: String] = [:]
    var callStack: [Int] = []

    struct ForState {
        var end: Double
        var step: Double
        var bodyLine: Int
        var exitLine: Int
    }
    var forStates: [String: ForState] = [:]

    func reset() {
        programLines.removeAll()
        clearVariables()
    }

    func clearVariables() {
        numVars.removeAll()
        strVars.removeAll()
        callStack.removeAll()
        forStates.removeAll()
    }

    // MARK: - Normalization

    func normalizeVarName(_ name: String) -> (String, Bool) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if clean.hasSuffix("$") {
            let base = clean.dropLast()
            return ("\(base)_str", true)
        }
        return (clean, false)
    }

    // MARK: - Expression Evaluation

    enum Value {
        case num(Double)
        case str(String)

        var asDouble: Double {
            switch self {
            case .num(let d): return d
            case .str(let s): return Double(s) ?? 0
            }
        }

        var asString: String {
            switch self {
            case .num(let d):
                if d.rounded() == d {
                    return String(Int(d))
                }
                return String(d)
            case .str(let s): return s
            }
        }
    }

    func eval(_ exprStr: String) -> Value {
        let trimmed = exprStr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .num(0) }

        // String literal
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            let inner = trimmed.dropFirst().dropLast()
            return .str(String(inner))
        }

        // Check for comparisons: =, <>, <=, >=, <, >
        for op in ["<=", ">=", "<>", "!=", "==", "=", "<", ">"] {
            if let range = findOperator(op, in: trimmed) {
                let left = eval(String(trimmed[..<range.lowerBound]))
                let right = eval(String(trimmed[range.upperBound...]))
                let result: Bool
                switch op {
                case "=", "==":
                    result = left.asString == right.asString
                case "<>", "!=":
                    result = left.asString != right.asString
                case "<=":
                    result = left.asDouble <= right.asDouble
                case ">=":
                    result = left.asDouble >= right.asDouble
                case "<":
                    result = left.asDouble < right.asDouble
                case ">":
                    result = left.asDouble > right.asDouble
                default:
                    result = false
                }
                return .num(result ? 1 : 0)
            }
        }

        // Check for + / - (outside parentheses and quotes)
        for op in ["+", "-"] {
            if let range = findOperator(op, in: trimmed, fromBack: true) {
                let leftStr = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rightStr = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !leftStr.isEmpty {
                    let left = eval(leftStr)
                    let right = eval(rightStr)
                    if op == "+" {
                        if case .str = left {
                            return .str(left.asString + right.asString)
                        } else if case .str = right {
                            return .str(left.asString + right.asString)
                        }
                        return .num(left.asDouble + right.asDouble)
                    } else {
                        return .num(left.asDouble - right.asDouble)
                    }
                }
            }
        }

        // Check for * / /
        for op in ["*", "/"] {
            if let range = findOperator(op, in: trimmed, fromBack: true) {
                let left = eval(String(trimmed[..<range.lowerBound]))
                let right = eval(String(trimmed[range.upperBound...]))
                if op == "*" {
                    return .num(left.asDouble * right.asDouble)
                } else {
                    return .num(right.asDouble != 0 ? left.asDouble / right.asDouble : 0)
                }
            }
        }

        // Literal number
        if let d = Double(trimmed) {
            return .num(d)
        }

        // Variable lookup
        let (v, isStr) = normalizeVarName(trimmed)
        if isStr {
            return .str(strVars[v] ?? "")
        } else {
            return .num(numVars[v] ?? 0)
        }
    }

    private func findOperator(_ op: String, in text: String, fromBack: Bool = false) -> Range<String.Index>? {
        var inQuotes = false
        var parenDepth = 0
        var indices: [String.Index] = []

        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if c == "(" { parenDepth += 1 }
                else if c == ")" { parenDepth -= 1 }
                else if parenDepth == 0 {
                    if text[i...].hasPrefix(op) {
                        indices.append(i)
                    }
                }
            }
            i = text.index(after: i)
        }

        if fromBack, let last = indices.last {
            let endIdx = text.index(last, offsetBy: op.count)
            return last..<endIdx
        } else if let first = indices.first {
            let endIdx = text.index(first, offsetBy: op.count)
            return first..<endIdx
        }
        return nil
    }

    // MARK: - Program Execution

    func run() {
        clearVariables()
        let sortedLineNumbers = programLines.keys.sorted()
        if sortedLineNumbers.isEmpty {
            print("NO PROGRAM")
            return
        }

        // Pre-scan FOR loops
        preScanForLoops(sortedLineNumbers: sortedLineNumbers)

        var pc = 0
        while pc < sortedLineNumbers.count {
            let lineNum = sortedLineNumbers[pc]
            guard let rawCode = programLines[lineNum] else {
                pc += 1
                continue
            }

            var nextLineToJump: Int? = nil
            var shouldStop = false

            executeStatement(rawCode, currentLine: lineNum, sortedLineNumbers: sortedLineNumbers, currentIndex: pc, jumpTo: &nextLineToJump, shouldStop: &shouldStop)

            if shouldStop {
                break
            }

            if let jump = nextLineToJump {
                if let nextIdx = sortedLineNumbers.firstIndex(of: jump) {
                    pc = nextIdx
                } else {
                    print("?UNDEFINED LINE NUMBER \(jump) IN \(lineNum)")
                    break
                }
            } else {
                pc += 1
            }
        }
    }

    private func preScanForLoops(sortedLineNumbers: [Int]) {
        forStates.removeAll()
        var forStack: [(varName: String, forLine: Int, bodyLine: Int)] = []

        for (idx, lineNum) in sortedLineNumbers.enumerated() {
            guard let code = programLines[lineNum] else { continue }
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            let nextLineNum = (idx + 1 < sortedLineNumbers.count) ? sortedLineNumbers[idx + 1] : 0

            if trimmed.uppercased().hasPrefix("FOR ") {
                let afterFor = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if let eqIdx = afterFor.firstIndex(of: "=") {
                    let v = normalizeVarName(String(afterFor[..<eqIdx])).0
                    forStack.append((varName: v, forLine: lineNum, bodyLine: nextLineNum))
                }
            } else if trimmed.uppercased() == "NEXT" || trimmed.uppercased().hasPrefix("NEXT ") {
                let afterNext = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                let reqVar = afterNext.isEmpty ? nil : normalizeVarName(afterNext).0
                if let top = forStack.popLast() {
                    let v = reqVar ?? top.varName
                    forStates[v] = ForState(end: 0, step: 1, bodyLine: top.bodyLine, exitLine: nextLineNum)
                }
            }
        }
    }

    // MARK: - Statement Execution

    func executeStatement(
        _ code: String,
        currentLine: Int? = nil,
        sortedLineNumbers: [Int] = [],
        currentIndex: Int = 0,
        jumpTo: inout Int?,
        shouldStop: inout Bool
    ) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.uppercased().hasPrefix("REM") {
            return
        }

        let upper = trimmed.uppercased()

        // END / STOP
        if upper == "END" || upper == "STOP" {
            shouldStop = true
            return
        }

        // GOTO
        if upper.hasPrefix("GOTO") {
            let targetStr = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let target = Int(targetStr) {
                jumpTo = target
            } else {
                print("?SYNTAX ERROR IN GOTO")
            }
            return
        }

        // GOSUB
        if upper.hasPrefix("GOSUB") {
            let targetStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let target = Int(targetStr) {
                let nextLine = (currentIndex + 1 < sortedLineNumbers.count) ? sortedLineNumbers[currentIndex + 1] : 0
                callStack.append(nextLine)
                jumpTo = target
            } else {
                print("?SYNTAX ERROR IN GOSUB")
            }
            return
        }

        // RETURN
        if upper == "RETURN" {
            if let ret = callStack.popLast() {
                jumpTo = ret
            } else {
                shouldStop = true
            }
            return
        }

        // FOR var = start TO end [STEP step]
        if upper.hasPrefix("FOR ") {
            let afterFor = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let eqIdx = afterFor.firstIndex(of: "=") {
                let v = normalizeVarName(String(afterFor[..<eqIdx])).0
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

                    let startVal = eval(startPart).asDouble
                    let endVal = eval(endPart).asDouble
                    let stepVal = eval(stepPart).asDouble

                    numVars[v] = startVal
                    if var state = forStates[v] {
                        state.end = endVal
                        state.step = stepVal
                        forStates[v] = state
                        if (stepVal > 0 && startVal > endVal) || (stepVal < 0 && startVal < endVal) {
                            jumpTo = state.exitLine
                        }
                    }
                }
            }
            return
        }

        // NEXT [var]
        if upper == "NEXT" || upper.hasPrefix("NEXT ") {
            let afterNext = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let v = afterNext.isEmpty ? (forStates.keys.first ?? "") : normalizeVarName(afterNext).0
            if let state = forStates[v] {
                let cur = (numVars[v] ?? 0) + state.step
                numVars[v] = cur
                if (state.step > 0 && cur <= state.end) || (state.step < 0 && cur >= state.end) {
                    jumpTo = state.bodyLine
                }
            }
            return
        }

        // PRINT or ?
        if upper.hasPrefix("PRINT") || trimmed.hasPrefix("?") {
            let rest: String
            if trimmed.hasPrefix("?") {
                rest = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            } else {
                rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            if rest.isEmpty {
                print()
                return
            }
            executePrint(rest)
            return
        }

        // IF cond THEN stmt
        if upper.hasPrefix("IF") {
            let afterIf = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if let thenRange = afterIf.range(of: "THEN", options: .caseInsensitive) {
                let condPart = String(afterIf[..<thenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let thenPart = String(afterIf[thenRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                let condVal = eval(condPart).asDouble
                if condVal != 0 {
                    if let target = Int(thenPart) {
                        jumpTo = target
                    } else {
                        executeStatement(thenPart, currentLine: currentLine, sortedLineNumbers: sortedLineNumbers, currentIndex: currentIndex, jumpTo: &jumpTo, shouldStop: &shouldStop)
                    }
                }
            }
            return
        }

        // INPUT / LINE INPUT
        if upper.hasPrefix("INPUT") || upper.hasPrefix("LINE INPUT") {
            executeInput(trimmed)
            return
        }

        // LET or assignment
        var assignCode = trimmed
        if upper.hasPrefix("LET") {
            assignCode = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        if let eqIdx = assignCode.firstIndex(of: "=") {
            let lhs = String(assignCode[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let rhs = String(assignCode[assignCode.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            let (v, isStr) = normalizeVarName(lhs)
            let val = eval(rhs)
            if isStr {
                strVars[v] = val.asString
            } else {
                numVars[v] = val.asDouble
            }
            return
        }

        print("?SYNTAX ERROR: \(trimmed)")
    }

    private func executePrint(_ argsStr: String) {
        var parts: [String] = []
        var cur = ""
        var inQuotes = false

        for char in argsStr {
            if char == "\"" { inQuotes.toggle(); cur.append(char); continue }
            if inQuotes { cur.append(char); continue }

            if char == ";" || char == "," {
                let trimmed = cur.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    parts.append(eval(trimmed).asString)
                }
                cur = ""
            } else {
                cur.append(char)
            }
        }
        let trimmed = cur.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            parts.append(eval(trimmed).asString)
        }

        let hasTrailingSemicolon = argsStr.trimmingCharacters(in: .whitespaces).hasSuffix(";")
        let output = parts.joined()

        if hasTrailingSemicolon {
            print(output, terminator: "")
            fflush(stdout)
        } else {
            print(output)
        }
    }

    private func executeInput(_ code: String) {
        var rest = code.trimmingCharacters(in: .whitespaces)
        var isLineInput = false
        if rest.uppercased().hasPrefix("LINE INPUT") {
            isLineInput = true
            rest = String(rest.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        } else if rest.uppercased().hasPrefix("INPUT") {
            rest = String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }

        var prompt = "? "
        if rest.hasPrefix("\"") {
            let afterFirst = rest.dropFirst()
            if let closeIdx = afterFirst.firstIndex(of: "\"") {
                let pText = String(afterFirst[..<closeIdx])
                let afterQuote = afterFirst[afterFirst.index(after: closeIdx)...].trimmingCharacters(in: .whitespaces)
                var addQ = true
                if afterQuote.hasPrefix(";") {
                    addQ = true
                    rest = String(afterQuote.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if afterQuote.hasPrefix(",") {
                    addQ = false
                    rest = String(afterQuote.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else {
                    rest = afterQuote
                }
                prompt = pText + (addQ ? "? " : "")
            }
        }

        print(prompt, terminator: "")
        fflush(stdout)

        guard let inputLine = readLine() else { return }

        let vars = rest.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isLineInput || vars.count <= 1 {
            if let firstVar = vars.first {
                let (v, isStr) = normalizeVarName(firstVar)
                if isStr {
                    strVars[v] = inputLine
                } else {
                    numVars[v] = Double(inputLine.trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        } else {
            let inputs = inputLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for (idx, vRaw) in vars.enumerated() {
                let (v, isStr) = normalizeVarName(vRaw)
                let item = idx < inputs.count ? inputs[idx] : ""
                if isStr {
                    strVars[v] = item
                } else {
                    numVars[v] = Double(item) ?? 0
                }
            }
        }
    }

    // MARK: - REPL Loop

    func startREPL() {
        print("""
        ************************************************
        *                                              *
        *         64K RAM SYSTEM BASIC (1983)          *
        *             POWERED BY SWIFT 6               *
        *                                              *
        ************************************************
        READY.
        """)

        while true {
            print("> ", terminator: "")
            fflush(stdout)

            guard let line = readLine() else {
                print("\nBYE.")
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let upper = trimmed.uppercased()

            // System commands
            if upper == "EXIT" || upper == "QUIT" || upper == "BYE" {
                print("BYE.")
                break
            }
            if upper == "NEW" {
                reset()
                print("READY.")
                continue
            }
            if upper == "CLEAR" {
                clearVariables()
                print("READY.")
                continue
            }
            if upper == "RUN" {
                run()
                print("READY.")
                continue
            }
            if upper == "HELP" {
                print("""
                Commands:
                  RUN             - Execute program
                  LIST            - Display program lines
                  NEW             - Clear program and memory
                  CLEAR           - Clear variables only
                  EXIT / QUIT     - Exit REPL
                  <line> <code    - Store/overwrite line
                  <line>          - Delete line
                  <statement>     - Execute immediate command (e.g. PRINT 1+2)
                """)
                print("READY.")
                continue
            }
            if upper.hasPrefix("LIST") {
                for l in programLines.keys.sorted() {
                    print("\(l) \(programLines[l]!)")
                }
                print("READY.")
                continue
            }

            // Check if line starts with a number
            let scanner = Scanner(string: trimmed)
            var lineNum: Int = 0
            if scanner.scanInt(&lineNum) {
                let rest = scanner.string[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    // Delete line
                    programLines.removeValue(forKey: lineNum)
                } else {
                    // Store / Overwrite line
                    programLines[lineNum] = rest
                }
            } else {
                // Immediate Mode (Direct execution!)
                var jump: Int? = nil
                var stop = false
                executeStatement(trimmed, jumpTo: &jump, shouldStop: &stop)
                print("READY.")
            }
        }
    }
}

// MARK: - Entry Point

let interpreter = BasicInterpreter()
interpreter.startREPL()
