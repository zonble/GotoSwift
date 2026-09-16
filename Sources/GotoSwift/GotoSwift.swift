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

/// Initializes or resizes the global graphics canvas (default 80x50).
public func screen(width: Int = 80, height: Int = 50) {
    globalBasicCanvas = BasicCanvas(width: width, height: height)
}

/// Plots a pixel on the graphics canvas.
public func pset(_ x: Int, _ y: Int) {
    globalBasicCanvas.pset(x: x, y: y, value: true)
}

/// Clears a pixel on the graphics canvas.
public func preset(_ x: Int, _ y: Int) {
    globalBasicCanvas.preset(x: x, y: y)
}

/// Draws a line between (x1, y1) and (x2, y2) on the graphics canvas.
public func drawLine(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
    globalBasicCanvas.line(x1: x1, y1: y1, x2: x2, y2: y2, value: true)
}

/// Draws a rectangle or filled box on the graphics canvas.
public func drawBox(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, fill: Bool = false) {
    globalBasicCanvas.box(x1: x1, y1: y1, x2: x2, y2: y2, fill: fill, value: true)
}

/// Draws a circle on the graphics canvas.
public func drawCircle(_ cx: Int, _ cy: Int, _ r: Int) {
    globalBasicCanvas.circle(cx: cx, cy: cy, r: r, value: true)
}

/// Renders the graphics canvas to stdout using Unicode Braille Patterns.
public func showCanvas() {
    print(globalBasicCanvas.render(), terminator: "")
}
