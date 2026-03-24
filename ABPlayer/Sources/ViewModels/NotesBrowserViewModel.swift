import Foundation
import Observation

@Observable
@MainActor
final class NotesBrowserViewModel {
  enum MediaSource: String, Hashable {
    case allVideos
    case allAudios

    var title: String {
      switch self {
      case .allVideos:
        return "All Videos"
      case .allAudios:
        return "All Audios"
      }
    }

    var systemImage: String {
      switch self {
      case .allVideos:
        return "film"
      case .allAudios:
        return "waveform"
      }
    }

    var fileType: FileType {
      switch self {
      case .allVideos:
        return .video
      case .allAudios:
        return .audio
      }
    }
  }

  enum Source: Hashable {
    case media(MediaSource)
    case collection(UUID)
  }

  enum MiddleMode {
    case media
    case notes
  }

  enum MiddleSelection: Hashable {
    case media(UUID)
    case note(UUID)
  }

  enum EntryFilter: Hashable {
    case all
    case stylePreset(UUID)
  }

  struct EntryFilterOption: Identifiable, Hashable {
    let filter: EntryFilter
    let title: String

    var id: String {
      switch filter {
      case .all:
        return "all"
      case .stylePreset(let stylePresetID):
        return "style-\(stylePresetID.uuidString.lowercased())"
      }
    }
  }

  struct Input {
    enum Event {
      case onAppear
      case refresh
      case selectSource(Source?)
      case selectMiddleItem(MiddleSelection?)
      case selectEntryFilter(EntryFilter)
    }

    let event: Event
  }

  struct LeftSourceItem: Identifiable, Hashable {
    let source: Source
    let title: String
    let systemImage: String

    var id: Source {
      source
    }
  }

  struct LeftSourceSection: Identifiable {
    let id: String
    let title: String
    let items: [LeftSourceItem]
  }

  struct MiddleListItem: Identifiable, Hashable {
    let selection: MiddleSelection
    let title: String
    let subtitle: String?
    let systemImage: String

    var id: MiddleSelection {
      selection
    }
  }

  struct ExportSelection: Equatable {
    enum Kind: Equatable {
      case note(noteID: UUID, noteTitle: String)
      case media(mediaID: UUID, mediaName: String)
    }

    let kind: Kind
  }

  struct Output {
    let leftSections: [LeftSourceSection]
    let middleMode: MiddleMode
    let middleItems: [MiddleListItem]
    let entryFilterOptions: [EntryFilterOption]
    let selectedEntryFilter: EntryFilter
    let entries: [NotesBrowserEntry]
    let exportFilter: NotesBrowserEntryFilter
    let exportSelection: ExportSelection?
    let selectedSource: Source?
    let selectedMiddleItem: MiddleSelection?
  }

  @ObservationIgnored
  private var notesService: NotesBrowserService?

  private(set) var output: Output
  private var selectedSource: Source?
  private var selectedMiddleItem: MiddleSelection?
  private var selectedEntryFilter: EntryFilter

  init() {
    output = Output(
      leftSections: [],
      middleMode: .media,
      middleItems: [],
      entryFilterOptions: [.init(filter: .all, title: "All")],
      selectedEntryFilter: .all,
      entries: [],
      exportFilter: .all,
      exportSelection: nil,
      selectedSource: nil,
      selectedMiddleItem: nil
    )
    selectedEntryFilter = .all
  }

  func configureIfNeeded(notesService: NotesBrowserService) {
    guard self.notesService == nil else { return }
    self.notesService = notesService
  }

  @discardableResult
  func transform(input: Input) -> Output {
    switch input.event {
    case .onAppear:
      if selectedSource == nil {
        selectedSource = .media(.allVideos)
      }
      reloadState()
    case .refresh:
      reloadState()
    case .selectSource(let source):
      selectedSource = source
      selectedMiddleItem = nil
      reloadState()
    case .selectMiddleItem(let item):
      selectedMiddleItem = item
      reloadState()
    case .selectEntryFilter(let filter):
      selectedEntryFilter = filter
      reloadState()
    }

    return output
  }

  private func reloadState() {
    guard let notesService else {
      output = Output(
          leftSections: [],
          middleMode: .media,
          middleItems: [],
          entryFilterOptions: [.init(filter: .all, title: "All")],
          selectedEntryFilter: .all,
          entries: [],
          exportFilter: .all,
          exportSelection: nil,
          selectedSource: nil,
          selectedMiddleItem: nil
        )
      return
    }

    let collections = notesService.collections()
    selectedSource = validatedSource(from: selectedSource, collections: collections)

    let leftSections = buildLeftSections(collections: collections)
    let middleMode = resolveMiddleMode(selectedSource: selectedSource)
    let middleItems = buildMiddleItems(
      notesService: notesService,
      selectedSource: selectedSource,
      collections: collections
    )

    selectedMiddleItem = validatedMiddleSelection(from: selectedMiddleItem, middleItems: middleItems)
    if selectedMiddleItem == nil {
      selectedMiddleItem = middleItems.first?.selection
    }

    let allEntries = buildEntries(notesService: notesService, for: selectedMiddleItem)
    let entryFilterOptions = buildEntryFilterOptions(entries: allEntries)
    selectedEntryFilter = validatedEntryFilter(from: selectedEntryFilter, options: entryFilterOptions)
    let entries = filterEntries(allEntries, with: selectedEntryFilter)
    let exportSelection = resolveExportSelection(
      selectedMiddleItem: selectedMiddleItem,
      middleItems: middleItems
    )

    output = Output(
      leftSections: leftSections,
      middleMode: middleMode,
      middleItems: middleItems,
      entryFilterOptions: entryFilterOptions,
      selectedEntryFilter: selectedEntryFilter,
      entries: entries,
      exportFilter: exportFilter(from: selectedEntryFilter),
      exportSelection: exportSelection,
      selectedSource: selectedSource,
      selectedMiddleItem: selectedMiddleItem
    )
  }

  private func validatedSource(from source: Source?, collections: [NoteCollection]) -> Source {
    guard let source else {
      return .media(.allVideos)
    }

    switch source {
    case .media:
      return source
    case .collection(let collectionID):
      if collections.contains(where: { $0.id == collectionID }) {
        return source
      }
      return .media(.allVideos)
    }
  }

  private func buildLeftSections(collections: [NoteCollection]) -> [LeftSourceSection] {
    let mediaSection = LeftSourceSection(
      id: "media",
      title: "Media",
      items: [
        LeftSourceItem(source: .media(.allVideos), title: MediaSource.allVideos.title, systemImage: MediaSource.allVideos.systemImage),
        LeftSourceItem(source: .media(.allAudios), title: MediaSource.allAudios.title, systemImage: MediaSource.allAudios.systemImage),
      ]
    )

    let collectionItems = collections.map { collection in
      LeftSourceItem(source: .collection(collection.id), title: collection.name, systemImage: "folder")
    }
    let collectionSection = LeftSourceSection(
      id: "collections",
      title: "Collections",
      items: collectionItems
    )

    return [mediaSection, collectionSection]
  }

  private func resolveMiddleMode(selectedSource: Source?) -> MiddleMode {
    guard let selectedSource else { return .media }

    switch selectedSource {
    case .media:
      return .media
    case .collection:
      return .notes
    }
  }

  private func buildMiddleItems(
    notesService: NotesBrowserService,
    selectedSource: Source?,
    collections: [NoteCollection]
  ) -> [MiddleListItem] {
    guard let selectedSource else { return [] }

    switch selectedSource {
    case .media(let source):
      return notesService.mediaWithAnnotations(fileType: source.fileType).map { media in
        MiddleListItem(
          selection: .media(media.id),
          title: media.displayName,
          subtitle: nil,
          systemImage: media.fileType.iconName
        )
      }
    case .collection(let collectionID):
      guard collections.contains(where: { $0.id == collectionID }) else {
        return []
      }
      let notes = (try? notesService.notes(inCollectionID: collectionID)) ?? []
      return notes.map { note in
        MiddleListItem(
          selection: .note(note.id),
          title: note.title,
          subtitle: nil,
          systemImage: "note.text"
        )
      }
    }
  }

  private func validatedMiddleSelection(
    from selection: MiddleSelection?,
    middleItems: [MiddleListItem]
  ) -> MiddleSelection? {
    guard let selection else { return nil }

    if middleItems.contains(where: { $0.selection == selection }) {
      return selection
    }

    return nil
  }

  private func buildEntries(
    notesService: NotesBrowserService,
    for selection: MiddleSelection?
  ) -> [NotesBrowserEntry] {
    guard let selection else { return [] }

    switch selection {
    case .media(let mediaID):
      return notesService.entries(forMediaID: mediaID)
    case .note(let noteID):
      return (try? notesService.entries(forNoteID: noteID)) ?? []
    }
  }

  private func buildEntryFilterOptions(entries: [NotesBrowserEntry]) -> [EntryFilterOption] {
    var stylesByID: [UUID: String] = [:]
    for entry in entries {
      guard let stylePresetID = entry.stylePresetID else { continue }
      let styleName = entry.stylePresetName?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let styleName, !styleName.isEmpty {
        stylesByID[stylePresetID] = styleName
      } else if stylesByID[stylePresetID] == nil {
        stylesByID[stylePresetID] = "Style"
      }
    }

    let styleOptions = stylesByID
      .map { stylePresetID, styleName in
        EntryFilterOption(filter: .stylePreset(stylePresetID), title: styleName)
      }
      .sorted { lhs, rhs in
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }

    return [EntryFilterOption(filter: .all, title: "All")] + styleOptions
  }

  private func validatedEntryFilter(from filter: EntryFilter, options: [EntryFilterOption]) -> EntryFilter {
    guard options.contains(where: { $0.filter == filter }) else {
      return .all
    }
    return filter
  }

  private func filterEntries(_ entries: [NotesBrowserEntry], with filter: EntryFilter) -> [NotesBrowserEntry] {
    switch filter {
    case .all:
      return entries
    case .stylePreset(let stylePresetID):
      return entries.filter { $0.stylePresetID == stylePresetID }
    }
  }

  private func exportFilter(from filter: EntryFilter) -> NotesBrowserEntryFilter {
    switch filter {
    case .all:
      return .all
    case .stylePreset(let stylePresetID):
      return .stylePreset(stylePresetID)
    }
  }

  private func resolveExportSelection(
    selectedMiddleItem: MiddleSelection?,
    middleItems: [MiddleListItem]
  ) -> ExportSelection? {
    guard let selectedMiddleItem else {
      return nil
    }

    switch selectedMiddleItem {
    case .note(let noteID):
      guard let selectedItem = middleItems.first(where: { $0.selection == .note(noteID) }) else {
        return nil
      }
      return ExportSelection(kind: .note(noteID: noteID, noteTitle: selectedItem.title))
    case .media(let mediaID):
      guard let selectedItem = middleItems.first(where: { $0.selection == .media(mediaID) }) else {
        return nil
      }
      return ExportSelection(kind: .media(mediaID: mediaID, mediaName: selectedItem.title))
    }
  }
}
