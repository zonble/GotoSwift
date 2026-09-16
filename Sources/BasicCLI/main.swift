import Foundation
import GotoSwift

// MARK: - Retro BASIC Interactive REPL

class BasicInterpreter {
    var programLines: [Int: String] = [:]
    var numVars: [String: Double] = [:]
    var strVars: [String: String] = [:]
    var callStack: [Int] = []

    struct ForLoopRecord {
        var varName: String
        var forLine: Int
        var bodyLine: Int
        var nextLine: Int
        var exitLine: Int
    }
    var forLoopsByForLine: [Int: ForLoopRecord] = [:]
    var forLoopsByNextLine: [Int: ForLoopRecord] = [:]
    var activeForLoops: [Int: (end: Double, step: Double)] = [:]

    func reset() {
        programLines.removeAll()
        clearVariables()
        forLoopsByForLine.removeAll()
        forLoopsByNextLine.removeAll()
    }

    func clearVariables() {
        numVars.removeAll()
        strVars.removeAll()
        callStack.removeAll()
        activeForLoops.removeAll()
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
        forLoopsByForLine.removeAll()
        forLoopsByNextLine.removeAll()
        activeForLoops.removeAll()
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
                    let record = ForLoopRecord(varName: v, forLine: top.forLine, bodyLine: top.bodyLine, nextLine: lineNum, exitLine: nextLineNum)
                    forLoopsByForLine[top.forLine] = record
                    forLoopsByNextLine[lineNum] = record
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

        // CLS / HOME
        if upper == "CLS" {
            print("\u{001B}[2J\u{001B}[H", terminator: "")
            fflush(stdout)
            return
        }
        if upper == "HOME" {
            print("\u{001B}[H", terminator: "")
            fflush(stdout)
            return
        }

        // SHOW
        if upper == "SHOW" {
            showCanvas()
            return
        }

        // SCREEN [w], [h]
        if upper.hasPrefix("SCREEN") {
            let rest = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                let w = Int(eval(parts[0]).asDouble)
                let h = Int(eval(parts[1]).asDouble)
                screen(width: w > 0 ? w : 80, height: h > 0 ? h : 50)
            } else if parts.count == 1 {
                screen(width: 80, height: 50)
            } else {
                screen()
            }
            return
        }

        // PSET (x, y)
        if upper.hasPrefix("PSET") {
            let rest = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let (x, y) = parseCoords(rest)
            pset(x, y)
            return
        }

        // PRESET (x, y)
        if upper.hasPrefix("PRESET") {
            let rest = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let (x, y) = parseCoords(rest)
            preset(x, y)
            return
        }

        // CIRCLE (cx, cy), r
        if upper.hasPrefix("CIRCLE") {
            let rest = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if let closeIdx = rest.firstIndex(of: ")") {
                let coordPart = String(rest[..<closeIdx]).trimmingCharacters(in: .whitespaces)
                let afterCoord = rest[rest.index(after: closeIdx)...].trimmingCharacters(in: .whitespaces)
                let (cx, cy) = parseCoords(coordPart)
                var rStr = afterCoord
                if rStr.hasPrefix(",") { rStr = String(rStr.dropFirst()).trimmingCharacters(in: .whitespaces) }
                let rParts = rStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                let r = Int(eval(rParts.first ?? "10").asDouble)
                drawCircle(cx, cy, r)
            }
            return
        }

        // LINE (x1, y1)-(x2, y2) [, [color] [, B | BF]]
        if upper.hasPrefix("LINE") {
            let rest = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if let dashIdx = rest.firstIndex(of: "-") {
                let firstPart = String(rest[..<dashIdx]).trimmingCharacters(in: .whitespaces)
                let secondPart = String(rest[rest.index(after: dashIdx)...]).trimmingCharacters(in: .whitespaces)

                let (x1, y1) = parseCoords(firstPart)
                if let closeIdx = secondPart.firstIndex(of: ")") {
                    let coord2 = String(secondPart[..<closeIdx]).trimmingCharacters(in: .whitespaces)
                    let (x2, y2) = parseCoords(coord2)
                    let extra = String(secondPart[secondPart.index(after: closeIdx)...]).trimmingCharacters(in: .whitespaces).uppercased()
                    if extra.contains("BF") {
                        drawBox(x1, y1, x2, y2, fill: true)
                    } else if extra.contains("B") {
                        drawBox(x1, y1, x2, y2, fill: false)
                    } else {
                        drawLine(x1, y1, x2, y2)
                    }
                }
            }
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

        // FOR v = start TO end [STEP s]
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
                    if let curL = currentLine, let record = forLoopsByForLine[curL] {
                        activeForLoops[record.forLine] = (end: endVal, step: stepVal)
                        if (stepVal > 0 && startVal > endVal) || (stepVal < 0 && startVal < endVal) {
                            jumpTo = record.exitLine
                        }
                    }
                }
            }
            return
        }

        // NEXT [var]
        if upper == "NEXT" || upper.hasPrefix("NEXT ") {
            let afterNext = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let reqVar = afterNext.isEmpty ? nil : normalizeVarName(afterNext).0

            if let curL = currentLine, let record = forLoopsByNextLine[curL] {
                let v = reqVar ?? record.varName
                let (endVal, stepVal) = activeForLoops[record.forLine] ?? (0, 1)
                let cur = (numVars[v] ?? 0) + stepVal
                numVars[v] = cur
                if (stepVal > 0 && cur <= endVal) || (stepVal < 0 && cur >= endVal) {
                    jumpTo = record.bodyLine
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

    // MARK: - File I/O (LOAD, SAVE, FILES)

    func saveFile(_ pathArg: String) {
        var filename = pathArg.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if filename.isEmpty {
            filename = "PROGRAM.BAS"
        }
        if !filename.contains(".") {
            filename += ".BAS"
        }
        let sortedLines = programLines.keys.sorted()
        let content = sortedLines.map { "\($0) \(programLines[$0]!)" }.joined(separator: "\n") + "\n"
        do {
            try content.write(toFile: filename, atomically: true, encoding: .utf8)
            print("SAVED TO \(filename).")
        } catch {
            print("?FILE ERROR: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func loadFile(_ pathArg: String, silent: Bool = false) -> Bool {
        var filename = pathArg.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if filename.isEmpty {
            print("?MISSING FILE NAME")
            return false
        }
        if !FileManager.default.fileExists(atPath: filename) && !filename.contains(".") {
            if FileManager.default.fileExists(atPath: filename + ".BAS") {
                filename += ".BAS"
            } else if FileManager.default.fileExists(atPath: filename + ".bas") {
                filename += ".bas"
            }
        }
        guard let content = try? String(contentsOfFile: filename, encoding: .utf8) else {
            print("?FILE NOT FOUND: \(filename)")
            return false
        }
        reset()
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
            let scanner = Scanner(string: trimmed)
            var lineNum = 0
            if scanner.scanInt(&lineNum) {
                let rest = scanner.string[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)
                programLines[lineNum] = rest
            }
        }
        if !silent {
            print("LOADED \(filename) (\(programLines.count) LINES).")
        }
        return true
    }

    func listFiles() {
        let currentPath = FileManager.default.currentDirectoryPath
        if let files = try? FileManager.default.contentsOfDirectory(atPath: currentPath) {
            let basFiles = files.filter { $0.hasSuffix(".bas") || $0.hasSuffix(".BAS") }.sorted()
            if basFiles.isEmpty {
                print("NO .BAS FILES FOUND IN CURRENT DIRECTORY.")
            } else {
                for f in basFiles {
                    print("  \(f)")
                }
            }
        }
    }

    func parseCoords(_ raw: String) -> (Int, Int) {
        var clean = raw.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("(") { clean = String(clean.dropFirst()) }
        if clean.hasSuffix(")") { clean = String(clean.dropLast()) }
        let parts = clean.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let xVal = parts.count > 0 ? Int(eval(parts[0]).asDouble) : 0
        let yVal = parts.count > 1 ? Int(eval(parts[1]).asDouble) : 0
        return (xVal, yVal)
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
            if upper == "FILES" || upper == "DIR" {
                listFiles()
                print("READY.")
                continue
            }
            if upper.hasPrefix("SAVE") {
                let arg = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                saveFile(arg)
                print("READY.")
                continue
            }
            if upper.hasPrefix("LOAD") {
                let arg = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                loadFile(arg)
                print("READY.")
                continue
            }
            if upper == "HELP" {
                print("""
                Commands:
                  RUN             - Execute program in memory
                  LIST            - Display program lines
                  LOAD "file.bas" - Load program from disk
                  SAVE "file.bas" - Save program to disk
                  FILES / DIR     - List .bas files in current directory
                  CLS             - Clear screen
                  HOME            - Move cursor to top-left
                  NEW             - Clear program and memory
                  CLEAR           - Clear variables only
                  EXIT / QUIT     - Exit REPL
                  <line> <code    - Store/overwrite line
                  <line>          - Delete line
                  <statement>     - Execute immediate command (e.g. ? 1+2)
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

if CommandLine.arguments.count > 1 {
    let targetFile = CommandLine.arguments[1]
    if interpreter.loadFile(targetFile, silent: true) {
        interpreter.run()
    }
} else {
    interpreter.startREPL()
}
