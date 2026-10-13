import SwiftUI
import AppKit
extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0x37474f
        let alpha = clean.count == 8 ? Double(value & 255) / 255 : 1
        let rgb = clean.count == 8 ? value >> 8 : value
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: alpha)
    }
    var hexRepresentation: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#37474f" }
        return String(format: "#%02x%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
    }
}
extension Date {
    func formatted(_ pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = pattern
        return f.string(from: self)
    }
}
// Select the public State property wrapper explicitly; CLT27 omits the newer State macro plugin.
typealias UIState<Value> = SwiftUI.State<Value>
