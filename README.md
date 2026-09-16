# GotoSwift 🍝

在 Swift 裡使用經典古早味的 **行號（Line Numbers）** 與 **`goto`**！

> "If you want to go back to 1980s BASIC inside modern Swift, look no further."

GotoSwift 利用 Swift 巨集（Swift Macros）與 `swift-syntax`，在編譯時期將帶有行號與跳躍指令的程式碼，自動展開成狀態機迴圈：

```swift
while true {
    switch _line {
    case 10: ...
    case 20: ...
    }
}
```

---

## ✨ 特色

1. **`#gotoScope` 巨集**：
   - 在合法的 Swift 語法區塊中書寫行號。
   - 支援 `line(10)`、`L(10)` 或 `_10: do { ... }` 作為行號標籤。
   - 支援 `goto(line)`、`gosub(line)`、`returnLine()` 與 `end()`。
   - **自動變數提升（Variable Hoisting）**：在不同行宣告的 `var` 會被自動提升到迴圈外，跨行號共享變數狀態！
   - **循序 Fallthrough**：依行號數值自動由小到大排序執行，未跳躍時自動前進到下一個行號。
   - **編譯期檢查**：若跳躍到不存在的行號，編譯器直接報錯！

2. **`#basic` 巨集**：
   - 直接輸入多行字串，撰寫純粹的經典 BASIC 程式碼！
   - 支援 `PRINT`、`LET`、`IF ... THEN GOTO`、`GOSUB`、`RETURN`、`END` 等指令。

---

## 🚀 範例展示

### 1. 使用 `#gotoScope`（Swift 語法）

```swift
import GotoSwift

#gotoScope {
    line(10)
    var count = 0
    print("計數開始: \(count)")

    line(20)
    count += 1
    print("目前計數: \(count)")
    if count < 3 {
        print("跳回第 20 行！")
        goto(20)
    }

    line(30)
    print("呼叫副程式第 100 行...")
    gosub(100)

    line(35)
    print("成功從副程式返回！")

    line(40)
    print("結束主程式。")
    end()

    line(100)
    print(">>> 這裡是副程式 (Line 100)")
    returnLine()
}
```

### 2. 使用 `#basic`（純文字 BASIC 語法）

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

## 🧪 測試與執行

執行範例程式：
```bash
swift run GotoSwiftClient
```

執行單元測試：
```bash
swift test
```
