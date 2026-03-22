import Carbon.HIToolbox
import Foundation

enum KeyboardInputSourceManager {
  private static let preferredEnglishInputSourceIDs = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.Canadian",
  ]

  @discardableResult
  static func selectEnglishInputSource() -> Bool {
    for inputSourceID in preferredEnglishInputSourceIDs {
      if selectInputSource(withID: inputSourceID) {
        return true
      }
    }
    return false
  }

  private static func selectInputSource(withID inputSourceID: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
    guard let sourceList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
          CFArrayGetCount(sourceList) > 0
    else {
      return false
    }

    let source = unsafeBitCast(CFArrayGetValueAtIndex(sourceList, 0), to: TISInputSource.self)
    return TISSelectInputSource(source) == noErr
  }
}
