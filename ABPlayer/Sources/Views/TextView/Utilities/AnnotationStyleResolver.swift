import AppKit
import Foundation

enum AnnotationStyleResolver {
  static func resolve(_ annotation: AnnotationRenderData) -> ResolvedAnnotationStyle {
    annotation.resolvedStyle
  }
}
