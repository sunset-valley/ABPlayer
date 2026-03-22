import AppKit
import Foundation

extension NSColor {
  convenience init?(abHex hex: String) {
    let cleaned = hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
      .uppercased()

    guard cleaned.count == 6,
      let value = Int(cleaned, radix: 16)
    else {
      return nil
    }

    let red = CGFloat((value >> 16) & 0xFF) / 255.0
    let green = CGFloat((value >> 8) & 0xFF) / 255.0
    let blue = CGFloat(value & 0xFF) / 255.0
    self.init(red: red, green: green, blue: blue, alpha: 1)
  }

  var abHexString: String {
    guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
    let red = Int((rgb.redComponent * 255.0).rounded())
    let green = Int((rgb.greenComponent * 255.0).rounded())
    let blue = Int((rgb.blueComponent * 255.0).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
  }
}
