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
}

