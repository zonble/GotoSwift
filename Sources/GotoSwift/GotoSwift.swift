// The Swift Programming Language
// https://docs.swift.org/swift-book

/// Declares a scope that supports line numbers and classic `goto`, `gosub`, and `returnLine` statements.
///
/// Inside the scope, lines can be marked using `line(10)`, `L(10)`, or labeled blocks like `_10: do { ... }`.
/// Variables declared inside lines are hoisted so they can be shared across all line numbers.
///
/// Example:
/// ```swift
/// #gotoScope {
///     line(10)
///     var count = 0
///     line(20)
///     count += 1
///     print("count: \(count)")
///     if count < 5 {
///         goto(20)
///     }
///     line(30)
///     print("Done!")
/// }
/// ```
@freestanding(expression)
public macro gotoScope(_ body: () -> Void) = #externalMacro(module: "GotoSwiftMacros", type: "GotoScopeMacro")

/// Executes a string containing vintage BASIC code with line numbers, `PRINT`, `LET`, `IF...THEN`, `GOTO`, `GOSUB`, `RETURN`, and `END`.
///
/// Example:
/// ```swift
/// #basic("""
/// 10 LET X = 1
/// 20 PRINT "X IS "; X
/// 30 LET X = X + 1
/// 40 IF X <= 3 THEN GOTO 20
/// 50 PRINT "DONE"
/// 60 END
/// """)
/// ```
@freestanding(expression)
public macro basic(_ code: String) = #externalMacro(module: "GotoSwiftMacros", type: "BasicMacro")

// MARK: - Dummy helpers for type-checking inside #gotoScope

public func goto(_ line: Int) {
    fatalError("goto(\(line)) must be used inside #gotoScope")
}

public func gosub(_ line: Int) {
    fatalError("gosub(\(line)) must be used inside #gotoScope")
}

public func returnLine() {
    fatalError("returnLine() must be used inside #gotoScope")
}

public func end() {
    fatalError("end() must be used inside #gotoScope")
}

public func line(_ line: Int) {
    fatalError("line(\(line)) must be used inside #gotoScope")
}

public func L(_ line: Int) {
    fatalError("L(\(line)) must be used inside #gotoScope")
}

/// Clears the terminal screen and resets cursor position (ANSI escape code `\u{001B}[2J\u{001B}[H`).
public func cls() {
    print("\u{001B}[2J\u{001B}[H", terminator: "")
}

/// Moves the cursor to home position `(1, 1)` without clearing entire screen (`\u{001B}[H`).
public func home() {
    print("\u{001B}[H", terminator: "")
}
