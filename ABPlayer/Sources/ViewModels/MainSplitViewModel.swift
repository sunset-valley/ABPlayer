import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MainSplitViewModel {
  // MARK: - Layout State
  var draggingWidth: Double?
  var draggingHeight: Double?
  
  // Persisted Layout State - Horizontal Split
  var playerSectionWidth: Double {
    didSet {
      UserDefaults.standard.set(playerSectionWidth, forKey: "mainSplitPlayerSectionWidth")
    }
  }
  
  var showContentPanel: Bool {
    didSet {
      UserDefaults.standard.set(showContentPanel, forKey: "mainSplitShowContentPanel")
    }
  }
  
  // Persisted Layout State - Vertical Split
  var topPanelHeight: Double {
    didSet {
      UserDefaults.standard.set(topPanelHeight, forKey: "mainSplitTopPanelHeight")
    }
  }
  
  var showBottomPanel: Bool {
    didSet {
      UserDefaults.standard.set(showBottomPanel, forKey: "mainSplitShowBottomPanel")
    }
  }

  // MARK: - Constants
  let minWidthOfPlayerSection: CGFloat = 480
  let minWidthOfContentPanel: CGFloat = 300
  let minHeightOfTopPanel: CGFloat = 200
  let minHeightOfBottomPanel: CGFloat = 150
  let dividerWidth: CGFloat = 8

  // MARK: - Initialization
  init() {
    let storedWidth = UserDefaults.standard.double(forKey: "mainSplitPlayerSectionWidth")
    self.playerSectionWidth = storedWidth > 0 ? storedWidth : 480
    
    if UserDefaults.standard.object(forKey: "mainSplitShowContentPanel") == nil {
      self.showContentPanel = true
    } else {
      self.showContentPanel = UserDefaults.standard.bool(forKey: "mainSplitShowContentPanel")
    }
    
    let storedHeight = UserDefaults.standard.double(forKey: "mainSplitTopPanelHeight")
    self.topPanelHeight = storedHeight > 0 ? storedHeight : 400
    
    if UserDefaults.standard.object(forKey: "mainSplitShowBottomPanel") == nil {
      self.showBottomPanel = true
    } else {
      self.showBottomPanel = UserDefaults.standard.bool(forKey: "mainSplitShowBottomPanel")
    }
  }

  // MARK: - Logic
  
  func clampWidth(_ width: Double, availableWidth: CGFloat) -> Double {
    let maxWidth = Double(availableWidth) - dividerWidth - minWidthOfContentPanel
    return min(max(width, minWidthOfPlayerSection), max(maxWidth, minWidthOfPlayerSection))
  }
  
  func clampHeight(_ height: Double, availableHeight: CGFloat) -> Double {
    let maxHeight = Double(availableHeight) - dividerWidth - minHeightOfBottomPanel
    return min(max(height, minHeightOfTopPanel), max(maxHeight, minHeightOfTopPanel))
  }
}
