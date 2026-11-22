import SwiftUI
import UIKit

/// WeChat's own emoji pictures, for codes like "[捂脸]".
@MainActor
enum WeChat {
    private static var cache: [String: UIImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ code: String) -> UIImage? {
        guard code.hasPrefix("["), !missing.contains(code) else { return nil }
        if let img = cache[code] { return img }
        guard let data = wechatImage(code: code), let img = UIImage(data: data) else {
            missing.insert(code)
            return nil
        }
        cache[code] = img
        return img
    }

    /// The picture scaled for text of `size` points (inside a `Text`, an image shows at its own size).
    static func inline(_ code: String, size: CGFloat) -> Text? {
        guard let img = image(code) else { return nil }
        let side = size * 1.3
        let key = "\(code)@\(Int(side))"
        let small = cache[key] ?? UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        cache[key] = small
        return Text(Image(uiImage: small).renderingMode(.original)).baselineOffset(-size * 0.2)
    }

    /// A message's plain text with WeChat's pictures in it.
    static func text(_ message: String, size: CGFloat) -> Text {
        textParts(text: message).reduce(Text(verbatim: "")) { line, part in
            if part.emoji, let picture = inline(part.text, size: size) { return line + picture }
            return line + Text(verbatim: part.text)
        }
    }
}
