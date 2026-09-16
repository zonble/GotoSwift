# GotoSwift 🍝

Line numbers and `goto` in modern Swift, because you deserve the freedom to write spaghetti code in 2026.

> *"I don't know who would write line numbers in Swift, but I believe everyone deserves the freedom to do so."*  
> — *GotoSwift Manifesto*
>
> *"Only those who understand GOTO truly understand programming."*

GotoSwift leverages **Swift Macros** and `swift-syntax` to bring back the golden age of 1980s BASIC into modern, type-safe Swift. At compile-time, it transforms your line-numbered code into a state machine loop:

```swift
_loop: while true {
    switch _line {
    case 10:
        ...
        _line = 20
        continue _loop
    case 20:
        ...
    default:
        break _loop
    }
}
```

---

## ✨ Features

- **`#gotoScope` (Native Swift Syntax)**:
  - Write standard Swift statements with line numbers using `line(10)`, `L(10)`, or labeled blocks `_10: do { ... }`.
  - Classic control flow: `goto(line)`, `gosub(line)`, `returnLine()`, and `end()`.
  - **Automatic Variable Hoisting**: Variables declared across different line numbers (`var x = 0`) are automatically hoisted outside the loop, enabling seamless state sharing across jumps.
  - **Sequential Fallthrough**: Lines execute in ascending order by line number. If a line doesn't jump, it naturally falls through to the next sorted line.
  - **Compile-Time Diagnostics**: Jumping to a non-existent line number emits a compile error directly in Xcode / Swift compiler!

- **`#basic` (Vintage BASIC Syntax)**:
  - Write vintage BASIC code directly inside a multiline string literal.
  - Supports `LET`, `PRINT`, `IF ... THEN GOTO`, `GOSUB`, `RETURN`, `END`, and line-level comments (`REM`).

---

## 🚀 Quick Start

### 1. Using `#gotoScope`

```swift
import GotoSwift

#gotoScope {
    line(10)
    var count = 0
    print("Starting counter with count = \(count)")

    line(20)
    count += 1
    print("Count is now: \(count)")
    if count < 3 {
        print("Jumping back to line 20...")
        goto(20)
    }

    line(30)
    print("Calling subroutine at line 100...")
    gosub(100)

    line(35)
    print("Successfully returned from subroutine!")

    line(40)
    print("Reached end of main program.")
    end()

    line(100)
    print(">>> [Line 100] Hello from vintage subroutine!")
    returnLine()
}
```

### 2. Using `#basic`

```swift
import GotoSwift

#basic("""
10 LET X = 1
20 PRINT "BASIC COUNT: "; X
30 LET X = X + 1
40 IF X <= 3 THEN GOTO 20
50 GOSUB 100
60 PRINT "BASIC PROGRAM FINISHED"
70 END
100 PRINT "HELLO FROM BASIC SUBROUTINE!"
110 RETURN
""")
```

---

## 🛠 How It Works

Swift macros operate directly on the Abstract Syntax Tree (AST):

1. **AST Parsing**: `#gotoScope` extracts the statements inside the closure, identifies line marker calls or label nodes, and partitions the code into discrete line blocks.
2. **Variable Hoisting**: All `VariableDeclSyntax` nodes within cases are hoisted to the top of the closure, and converted into re-assignments inside each case block.
3. **Control Flow Rewriting**: `goto(N)` calls are rewritten into `_line = N; continue _loop`. `gosub(N)` pushes the return line number onto `_callStack` before jumping.
4. **Compile-Time Safety**: Jump targets are verified against the set of defined line numbers. An undefined target emits a compile-time diagnostic.

---

## 📦 Installation

Add **GotoSwift** to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/zonble/GotoSwift.git", from: "1.0.0"),
]
```

Or add it directly in Xcode via **File > Add Package Dependencies...** using:
`https://github.com/zonble/GotoSwift.git`

---

## 🧪 Testing

Run the test suite (8 tests covering macro expansion, diagnostics, and runtime execution):

```bash
swift test
```

Run the example client:

```bash
swift run GotoSwiftClient
```

---

## 📄 License

MIT License. Feel free to use it to confuse your colleagues, write vintage games, or protest structured programming.
