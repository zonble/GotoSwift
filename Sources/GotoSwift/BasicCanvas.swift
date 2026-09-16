import Foundation

/// A terminal graphics canvas using Unicode Braille Patterns (U+2800 ... U+28FF).
/// Each terminal character cell contains a 2x4 dot matrix.
/// A canvas of width 80, height 50 uses 40 columns x 13 rows in terminal characters.
public class BasicCanvas {
    public let width: Int
    public let height: Int
    private var grid: [[Bool]]

    public init(width: Int = 80, height: Int = 50) {
        self.width = width
        self.height = height
        self.grid = Array(repeating: Array(repeating: false, count: width), count: height)
    }

    public func clear() {
        for y in 0..<height {
            for x in 0..<width {
                grid[y][x] = false
            }
        }
    }

    public func pset(x: Int, y: Int, value: Bool = true) {
        guard x >= 0 && x < width && y >= 0 && y < height else { return }
        grid[y][x] = value
    }

    public func preset(x: Int, y: Int) {
        pset(x: x, y: y, value: false)
    }

    public func point(x: Int, y: Int) -> Bool {
        guard x >= 0 && x < width && y >= 0 && y < height else { return false }
        return grid[y][x]
    }

    /// Draws a line using Bresenham's algorithm.
    public func line(x1: Int, y1: Int, x2: Int, y2: Int, value: Bool = true) {
        var x0 = x1
        var y0 = y1
        let dx = abs(x2 - x0)
        let dy = -abs(y2 - y0)
        let sx = x0 < x2 ? 1 : -1
        let sy = y0 < y2 ? 1 : -1
        var err = dx + dy

        while true {
            pset(x: x0, y: y0, value: value)
            if x0 == x2 && y0 == y2 { break }
            let e2 = 2 * err
            if e2 >= dy {
                err += dy
                x0 += sx
            }
            if e2 <= dx {
                err += dx
                y0 += sy
            }
        }
    }

    /// Draws a rectangle outline or filled box.
    public func box(x1: Int, y1: Int, x2: Int, y2: Int, fill: Bool = false, value: Bool = true) {
        let minX = max(0, min(x1, x2))
        let maxX = min(width - 1, max(x1, x2))
        let minY = max(0, min(y1, y2))
        let maxY = min(height - 1, max(y1, y2))

        if fill {
            for y in minY...maxY {
                for x in minX...maxX {
                    pset(x: x, y: y, value: value)
                }
            }
        } else {
            line(x1: minX, y1: minY, x2: maxX, y2: minY, value: value)
            line(x1: maxX, y1: minY, x2: maxX, y2: maxY, value: value)
            line(x1: maxX, y1: maxY, x2: minX, y2: maxY, value: value)
            line(x1: minX, y1: maxY, x2: minX, y2: minY, value: value)
        }
    }

    /// Draws a circle using Midpoint circle algorithm.
    public func circle(cx: Int, cy: Int, r: Int, value: Bool = true) {
        var x = 0
        var y = r
        var d = 1 - r

        func plot8(_ x: Int, _ y: Int) {
            pset(x: cx + x, y: cy + y, value: value)
            pset(x: cx - x, y: cy + y, value: value)
            pset(x: cx + x, y: cy - y, value: value)
            pset(x: cx - x, y: cy - y, value: value)
            pset(x: cx + y, y: cy + x, value: value)
            pset(x: cx - y, y: cy + x, value: value)
            pset(x: cx + y, y: cy - x, value: value)
            pset(x: cx - y, y: cy - x, value: value)
        }

        plot8(x, y)
        while x < y {
            x += 1
            if d < 0 {
                d += 2 * x + 1
            } else {
                y -= 1
                d += 2 * (x - y) + 1
            }
            plot8(x, y)
        }
    }

    /// Renders the canvas to a string using Unicode Braille Patterns (U+2800..U+28FF).
    /// Each braille character represents a 2-column by 4-row dot matrix.
    /// Bit mapping:
    /// dot(0,0): 0x01, dot(0,1): 0x02, dot(0,2): 0x04
    /// dot(1,0): 0x08, dot(1,1): 0x10, dot(1,2): 0x20
    /// dot(0,3): 0x40, dot(1,3): 0x80
    public func render() -> String {
        var result = ""
        let charWidth = (width + 1) / 2
        let charHeight = (height + 3) / 4

        for cy in 0..<charHeight {
            var line = ""
            for cx in 0..<charWidth {
                let px = cx * 2
                let py = cy * 4
                var code = 0

                if py < height && px < width && grid[py][px] { code |= 0x01 }
                if py + 1 < height && px < width && grid[py + 1][px] { code |= 0x02 }
                if py + 2 < height && px < width && grid[py + 2][px] { code |= 0x04 }
                if py < height && px + 1 < width && grid[py][px + 1] { code |= 0x08 }
                if py + 1 < height && px + 1 < width && grid[py + 1][px + 1] { code |= 0x10 }
                if py + 2 < height && px + 1 < width && grid[py + 2][px + 1] { code |= 0x20 }
                if py + 3 < height && px < width && grid[py + 3][px] { code |= 0x40 }
                if py + 3 < height && px + 1 < width && grid[py + 3][px + 1] { code |= 0x80 }

                if let scalar = UnicodeScalar(0x2800 + code) {
                    line.append(Character(scalar))
                } else {
                    line.append(" ")
                }
            }
            result.append(line)
            result.append("\n")
        }
        return result
    }
}

/// Global canvas instance for Basic / GotoSwift programs.
nonisolated(unsafe) public var globalBasicCanvas = BasicCanvas()

