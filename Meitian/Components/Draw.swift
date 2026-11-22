import SwiftUI

/// Draws the core's draw commands (core/src/draw.rs): hit effects, auras and arena scenery.
enum OpsRenderer {
    static func draw(_ ops: Data, in context: GraphicsContext, size: CGSize) {
        guard !ops.isEmpty else { return }
        let normal = context
        var light = context
        light.blendMode = .plusLighter
        ops.withUnsafeBytes { raw in
            var r = Reader(raw: raw)
            while r.more {
                switch Int(r.next()) {
                case 1:
                    let c = r.point(), radius = r.next()
                    let color = r.color()
                    let ctx = r.flag() ? light : normal
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: c, startRadius: 0, endRadius: radius))
                case 2:
                    let c = r.point(), radius = r.next()
                    let color = r.color()
                    let ctx = r.flag() ? light : normal
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                case 3:
                    let c = r.point(), radius = r.next(), width = r.next()
                    let color = r.color()
                    let ctx = r.flag() ? light : normal
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(color), lineWidth: width)
                case 4:
                    let a = r.point(), b = r.point(), width = r.next()
                    let color = r.color()
                    let ctx = r.flag() ? light : normal
                    var p = Path()
                    p.move(to: a)
                    p.addLine(to: b)
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                case 5:
                    let n = Int(r.next())
                    let top = r.color(), bottom = r.color()
                    let y1 = r.next(), y2 = r.next()
                    let ctx = r.flag() ? light : normal
                    var p = r.path(n)
                    p.closeSubpath()
                    if top == bottom {
                        ctx.fill(p, with: .color(top))
                    } else {
                        ctx.fill(p, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: 0, y: y1),
                                                          endPoint: CGPoint(x: 0, y: max(y2, y1 + 0.1))))
                    }
                case 6:
                    let code = UInt32(max(r.next(), 32)), c = r.point(), points = r.next(), degrees = r.next(), alpha = r.next()
                    var ctx = normal
                    ctx.opacity = alpha
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: .degrees(degrees))
                    ctx.draw(Text(UnicodeScalar(code).map { String(Character($0)) } ?? " ")
                        .font(.system(size: points, weight: .heavy)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.42)), at: .zero)
                case 7:
                    normal.fill(Path(CGRect(origin: .zero, size: size)), with: .color(r.color()))
                case 8:
                    let n = Int(r.next()), width = r.next()
                    let color = r.color()
                    let ctx = r.flag() ? light : normal
                    ctx.stroke(r.path(n), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                default:
                    return   // a newer core: stop rather than draw garbage
                }
            }
        }
    }

    private struct Reader {
        let raw: UnsafeRawBufferPointer
        var at = 0

        init(raw: UnsafeRawBufferPointer) { self.raw = raw }

        var more: Bool { at + 4 <= raw.count }

        mutating func next() -> Double {
            guard more else { return 0 }
            let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
            at += 4
            return Double(Float(bitPattern: bits))
        }

        mutating func flag() -> Bool { next() > 0 }

        mutating func point() -> CGPoint {
            let x = next()
            let y = next()
            return CGPoint(x: x, y: y)
        }

        mutating func color() -> Color {
            let r = next(), g = next(), b = next(), a = next()
            return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        }

        mutating func path(_ n: Int) -> Path {
            var p = Path()
            for i in 0..<max(n, 0) {
                let q = point()
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            return p
        }
    }
}
