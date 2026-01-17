import Foundation
import AppKit

/// Value type representing vocabulary data for a word
/// Decouples views from VocabularyService implementation
struct WordVocabularyData {
  let word: String
  let difficultyLevel: Int?
  let forgotCount: Int
  let rememberedCount: Int
  let createdAt: Date?
  
  /// Whether the word can be marked as "remembered"
  /// Requires at least one "forgot" count and 12 hours since creation
  var canRemember: Bool {
    guard forgotCount > 0, let date = createdAt else { return false }
    return Date().timeIntervalSince(date) >= 12 * 3600
  }
  
  /// Display color based on difficulty level
  var displayColor: NSColor {
    guard let level = difficultyLevel, level > 0 else {
      return .labelColor
    }
    switch level {
    case 1: return .systemGreen
    case 2: return .systemYellow
    default: return .systemRed
    }
  }
  
  /// Cleaned word text (lowercase, no punctuation)
  var cleanedWord: String {
    word.lowercased().trimmingCharacters(in: .punctuationCharacters)
  }
  
  /// Whether this word has any vocabulary tracking data
  var hasVocabularyData: Bool {
    forgotCount > 0 || rememberedCount > 0
  }
  
  /// Create vocabulary data from VocabularyService
  static func from(
    word: String,
    difficultyLevel: (String) -> Int?,
    forgotCount: (String) -> Int,
    rememberedCount: (String) -> Int,
    createdAt: (String) -> Date?
  ) -> WordVocabularyData {
    let cleaned = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    return WordVocabularyData(
      word: word,
      difficultyLevel: difficultyLevel(cleaned),
      forgotCount: forgotCount(cleaned),
      rememberedCount: rememberedCount(cleaned),
      createdAt: createdAt(cleaned)
    )
  }
}
