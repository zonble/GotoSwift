import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import GotoSwift

#if canImport(GotoSwiftMacros)
import GotoSwiftMacros

let testMacros: [String: Macro.Type] = [
    "gotoScope": GotoScopeMacro.self,
    "basic": BasicMacro.self,
]
#endif

final class GotoSwiftTests: XCTestCase {
    func testGotoScopeExpansion() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            """
            #gotoScope {
                line(10)
                var x = 1
                line(20)
                x += 1
                if x < 3 {
                    goto(20)
                }
                line(30)
                print(x)
            }
            """,
            expandedSource: """
            {
                var x = 1
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    x = 1
                    _line = 20
                    continue _loop
                case 20:
                    x += 1
                    if x < 3 {
                        _line = 20
                                continue _loop
                        }
                    _line = 30
                    continue _loop
                case 30:
                    print(x)
                    break _loop
                    default:
                        break _loop
                    }
                }
            }()
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testGotoScopeLabeledBlocks() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            """
            #gotoScope {
                _10: do {
                    print("A")
                }
                _20: do {
                    print("B")
                }
            }
            """,
            expandedSource: """
            {
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    print("A")
                    _line = 20
                    continue _loop
                case 20:
                    print("B")
                    break _loop
                    default:
                        break _loop
                    }
                }
            }()
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testGotoScopeMissingTargetDiagnostic() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            """
            #gotoScope {
                line(10)
                goto(999)
            }
            """,
            expandedSource: """
            {
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    _line = 999
                    continue _loop
                    default:
                        break _loop
                    }
                }
            }()
            """,
            diagnostics: [
                DiagnosticSpec(message: "Target line number 999 does not exist", line: 3, column: 10)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testBasicExpansion() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            #"""
            #basic("""
            10 LET X = 1
            20 PRINT "COUNT: "; X
            30 LET X = X + 1
            40 IF X <= 2 THEN GOTO 20
            50 END
            """)
            """#,
            expandedSource: #"""
            {
                var X: Double = 0
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    X = 1
                    _line = 20
                    continue _loop
                case 20:
                    print("COUNT: ", X, separator: "")
                    _line = 30
                    continue _loop
                case 30:
                    X = X + 1
                    _line = 40
                    continue _loop
                case 40:
                    if X <= 2 {
                        _line = 20
                    continue _loop
                    }
                    _line = 50
                    continue _loop
                case 50:
                    break _loop
                    default:
                        break _loop
                    }
                }
            }()
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testBasicMissingTargetDiagnostic() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            #"""
            #basic("""
            10 GOTO 500
            """)
            """#,
            expandedSource: #"""
            {
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    _line = 500
                    continue _loop
                    default:
                        break _loop
                    }
                }
            }()
            """#,
            diagnostics: [
                DiagnosticSpec(message: "GOTO target line 500 on line 10 does not exist", line: 1, column: 1)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - End-to-End Runtime Execution Tests

    func testRuntimeGotoExecution() {
        var trace: [Int] = []
        var finalCount = 0

        #gotoScope {
            line(10)
            var count = 0
            trace.append(10)

            line(20)
            count += 1
            trace.append(20)
            if count < 3 {
                goto(20)
            }

            line(30)
            trace.append(30)
            finalCount = count
        }

        XCTAssertEqual(trace, [10, 20, 20, 20, 30])
        XCTAssertEqual(finalCount, 3)
    }

    func testRuntimeSubroutineExecution() {
        var trace: [String] = []

        #gotoScope {
            line(10)
            trace.append("start")

            line(20)
            trace.append("calling-sub")
            gosub(100)

            line(30)
            trace.append("returned-from-sub")
            end()

            line(100)
            trace.append("in-sub")
            returnLine()
        }

        XCTAssertEqual(trace, ["start", "calling-sub", "in-sub", "returned-from-sub"])
    }

    func testRuntimeBasicExecution() {
        #basic("""
        10 LET X = 10
        20 LET Y = 20
        30 PRINT "X + Y = "; X + Y
        40 END
        """)
    }

    func testRuntimeBasicForNextLoop() {
        #basic("""
        10 FOR I = 1 TO 3
        20 PRINT "FOR I="; I
        30 NEXT I
        40 FOR J = 5 TO 1 STEP -2
        50 PRINT "FOR J="; J
        60 NEXT J
        70 END
        """)
    }

    func testRuntimeQuestionMarkPrint() {
        #basic("""
        10 ? "HELLO FROM QUESTION MARK!"
        20 ? "ANSWER = "; 42
        30 ?
        40 END
        """)
    }

    func testVintageLineOverwriteAndDeletion() {
        var trace: [Int] = []

        #gotoScope {
            line(10)
            trace.append(1)

            // Overwrite line 10!
            line(10)
            trace.append(10)

            // Line 20 will be defined then deleted!
            line(20)
            trace.append(20)

            line(20) // Empty statement deletes line 20!

            line(30)
            trace.append(30)
            end()
        }

        XCTAssertEqual(trace, [10, 30])

        #basic("""
        10 LET X = 1
        10 LET X = 99
        20 LET Y = 500
        20
        25 ? "X = "; X
        30 END
        """)
    }

    func testBasicInputExpansion() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            #"""
            #basic("""
            10 INPUT "NAME: ", NAME$
            20 INPUT "AGE: "; AGE
            30 LINE INPUT ADDR$
            40 END
            """)
            """#,
            expandedSource: #"""
            {
                var AGE: Double = 0
                var ADDR_str: String = ""
                var NAME_str: String = ""
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    print("NAME: ", terminator: "")
                    if let _in = readLine() {
                        NAME_str = _in
                    }
                    _line = 20
                    continue _loop
                case 20:
                    print("AGE: ? ", terminator: "")
                    if let _in = readLine(), let _val = Double(_in.trimmingCharacters(in: .whitespaces)) {
                        AGE = _val
                    }
                    _line = 30
                    continue _loop
                case 30:
                    print("? ", terminator: "")
                    if let _in = readLine() {
                        ADDR_str = _in
                    }
                    _line = 40
                    continue _loop
                case 40:
                    break _loop
                    default:
                        break _loop
                    }
                }
            }()
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testBasicClsExpansion() throws {
        #if canImport(GotoSwiftMacros)
        assertMacroExpansion(
            #"""
            #basic("""
            10 CLS
            20 HOME
            30 END
            """)
            """#,
            expandedSource: #"""
            {
                var _line: Int = 10
                var _callStack: [Int] = []
                _callStack.removeAll()
                _loop: while true {
                    switch _line {
                case 10:
                    print("\u{001B}[2J\u{001B}[H", terminator: "")
                    _line = 20
                    continue _loop
                case 20:
                    print("\u{001B}[H", terminator: "")
                    _line = 30
                    continue _loop
                case 30:
                    break _loop
                    default:
                        break _loop
                    }
                }
            }()
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}

