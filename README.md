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
  - **Authentic 1980s Line Editing**:
    - Re-declaring an existing line number **overwrites** the previous definition.
    - Declaring an empty line number **deletes** that line from the program!
  - **Screen Control (`CLS` & `HOME`)**: Native `cls()` and `home()` helper functions to clear the terminal screen or reset cursor position.
  - **Compile-Time Diagnostics**: Jumping to a non-existent line number emits a compile error directly in Xcode / Swift compiler!

- **`#basic` (Vintage BASIC Syntax)**:
  - Write vintage BASIC code directly inside a multiline string literal.
  - Supports `LET`, `PRINT` (and the legendary `?` shorthand), `IF ... THEN GOTO`, `GOSUB`, `RETURN`, and `END`.
  - **Screen Control (`CLS` & `HOME`)**: Authentic 1980s screen clearing (`CLS`) and cursor resetting (`HOME`).
  - **Retro Terminal Graphics (`SCREEN`, `LINE`, `CIRCLE`, `PSET`, `PRESET`, `SHOW`)**: High-resolution Bresenham vector graphics rendered via Unicode Braille Patterns (`LINE (x1, y1)-(x2, y2)`, `LINE -(x2, y2), , B` for boxes, `BF` for filled boxes, `CIRCLE (cx, cy), r`).
  - **Console Input (`INPUT` & `LINE INPUT`)**: Read strings or numbers interactively from the terminal, with support for prompts (`INPUT "NAME: "; NAME$`) and comma-separated multiple values!
  - **`FOR ... NEXT` Loops**: Full support for loops, `STEP` increments/decrements (including negative step countdowns), and nested loops!
  - **Vintage Line Overwrite & Deletion**: Enter the same line number to overwrite, or a line number with empty content to delete it.

---

## 🚀 Quick Start

### 1. Using `#gotoScope` (Swift Syntax)

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

### 2. Using `#basic` with `?`, `FOR ... NEXT`, and Subroutines

```swift
import GotoSwift

#basic("""
10 ? "HELLO FROM RETRO BASIC!"
20 LET X = 1
30 ? "COUNT: "; X
40 LET X = X + 1
50 IF X <= 3 THEN GOTO 30
60 GOSUB 100
70 ? "PROGRAM FINISHED"
80 END
100 ? "HELLO FROM SUBROUTINE!"
110 RETURN
""")
```

### 3. Printing a Christmas Tree with Nested `FOR ... NEXT`! 🎄

```swift
import GotoSwift

#basic("""
10 REM === RETRO BASIC CHRISTMAS TREE ===
20 LET H = 7
30 FOR I = 1 TO H
40   FOR S = 1 TO H - I
50     ? " ";
60   NEXT S
70   FOR A = 1 TO 2 * I - 1
80     ? "*";
90   NEXT A
100  ? ""
110 NEXT I
120 REM === TREE TRUNK ===
130 FOR T = 1 TO 2
140   FOR S = 1 TO H - 1
150     ? " ";
160   NEXT S
170   ? "|"
180 NEXT T
190 ? "MERRY CHRISTMAS IN RETRO BASIC & SWIFT! 🎄"
200 END
""")
```

```text
      *
     ***
    *****
   *******
  *********
 ***********
*************
      |
      |
MERRY CHRISTMAS IN RETRO BASIC & SWIFT! 🎄
```

### 4. 1980s String Art Fan with Bresenham Vector Graphics! 🎨

Remember drawing fans with `FOR` loops and `LINE`? GotoSwift renders vector graphics straight into your terminal using Unicode Braille Patterns:

```swift
#basic("""
10 SCREEN 80, 48
20 CLS
30 FOR X = 0 TO 78 STEP 4
40   LINE (0, 0)-(X, 46)
50 NEXT X
60 FOR Y = 0 TO 46 STEP 4
70   LINE (0, 0)-(78, Y)
80 NEXT Y
90 SHOW
100 END
""")
```

Or run the bundled demo file directly:
```bash
swift run basic Examples/fan.bas
```

#### 📐 Canvas Resolution & Coordinates

| Feature | Details |
|---|---|
| **Pixel Resolution** | Default **80 × 50** dots (Customizable via `SCREEN width, height`) |
| **Origin** | Top-left `(0, 0)` to bottom-right `(width - 1, height - 1)` with auto-clipping |
| **Terminal Footprint** | Rendered with **Unicode Braille Patterns** (U+2800..U+28FF) where each character cell maps to a **2 × 4** dot matrix. Default 80×50 uses **40 columns × 13 rows** of terminal text! |
| **Graphics Primitives** | `LINE (x1, y1)-(x2, y2)`, `LINE -(x2, y2), , B` (box), `BF` (filled box), `CIRCLE (cx, cy), r`, `PSET (x, y)`, `PRESET (x, y)` |

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

## 🧪 Testing & Running

Run the unit tests (13 tests covering macro expansion, diagnostics, screen control, loop step verification, and runtime execution):

```bash
swift test
```

Run the example client:

```bash
swift run GotoSwiftClient
```

### 🖥️ Launch the Interactive Retro BASIC REPL!

Travel back to 1983 and write BASIC interactively in your terminal:

```bash
swift run basic
```

```text
************************************************
*                                              *
*         64K RAM SYSTEM BASIC (1983)          *
*             POWERED BY SWIFT 6               *
*                                              *
************************************************
READY.
> ? 2 + 3 * 4
14
READY.
> 10 FOR I = 1 TO 3
> 20 ? "HELLO FROM 1983! I="; I
> 30 NEXT I
> LIST
10 FOR I = 1 TO 3
20 ? "HELLO FROM 1983! I="; I
30 NEXT I
> RUN
HELLO FROM 1983! I=1
HELLO FROM 1983! I=2
HELLO FROM 1983! I=3
READY.
```

### 💾 File Commands & Running `.bas` Scripts

You can save, load, and manage classic BASIC programs on disk:

- **`SAVE "program.bas"`**: Save the current program lines in memory to a text file.
- **`LOAD "program.bas"`**: Load program lines from disk into memory.
- **`FILES` / `DIR`**: List `.bas` files in the current working directory.
- **`NEW`**: Wipe program lines and variable state.
- **`HELP`**: Show available interactive commands.

#### Execute a `.bas` File Directly:

Run vintage BASIC programs directly from your shell without entering the REPL:

```bash
swift run basic Examples/xmas.bas
```

---

## 📄 License

MIT License. Feel free to use it to confuse your colleagues, write vintage games, or protest structured programming.
