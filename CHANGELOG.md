## [0.2.13.92] - 2026-03-20

### Improvements
- remove unused declaration-only APIs

### Chores
- point Sparkle feed to S3 and validate appcast URL (#137)

### Other
- add TextView
- create a doc rule
- fix tests (#138)


## [0.2.13.91] - 2026-03-19

### Chores
- point Sparkle feed and appcast URLs to S3


## [0.2.13.90] - 2026-03-19

### Bug Fixes
- pass local model folder to avoid HuggingFace network call on load (#135)


## [0.2.12.89] - 2026-03-18

### Features
- Full edition, download mirror & manual download guide for Chinese users (#131)

### Bug Fixes
- eliminate force-unwraps and silent error swallowing across services (#130)

### Improvements
- reduce redundancy and clarify architecture (#132)

### Chores
- update package dependencies and versions

### Other
- use custom swift-transformers
- Refactor SettingsView and TranscriptionView
- Feat proxy (#133)


## [0.2.11.88] - 2026-03-17

### Bug Fixes
- react to sleep setting and safe fullscreen rendering


## [0.2.11.87] - 2026-03-17

### Bug Fixes
- react to sleep setting and safe fullscreen rendering


## [0.2.11.86] - 2026-03-17

### Features
- add custom fullscreen playback mode
- add prevent-sleep playback preference

### Chores
- move git-release skill into .agent directory


## [0.2.11.85] - 2026-03-17

### Chores
- move git-release skill into .agent directory


## [0.2.11.84] - 2026-03-17

### Bug Fixes
- decouple manual navigation from autoplay rules

### Chores
- restructure AGENTS.md and organize Docs layout


## [0.2.11.83] - 2026-03-12

### Bug Fixes
- update queue on sort order and refresh changes
- parse first numeric segment for number sort

### Chores
- revert xcode version
- tests failed


## [0.2.11.82] - 2026-03-12

### Bug Fixes
- parse first numeric segment for number sort
- ensure file selection callback runs on main actor


## [0.2.11.81] - 2026-02-25

### Bug Fixes
- ensure subtitle rows refresh correctly after text edits by using raw text for update checks and removing redundant view IDs

### Chores
- update runner to macos-26 and reformat
- correct macOS deployment target format
- update textTertiary to lighter shade


## [0.2.11.80] - 2026-02-16

### Features
- add option to keep playback paused after word lookup

### Bug Fixes
- refactor FFmpeg status updates to avoid side effects in view updates

### Improvements
- disable focus effect and cleanup VideoPlayerView
- update ViewModel and optimize FPSMonitor
- extract split view components for modularity

### Chores
- update macOS deployment target to 26.0.0 and project settings
- update 0.2.11-78 changes


## [0.2.11.79] - 2026-02-11

### Features
- add folder refresh flow and library-safe sync paths

### Bug Fixes
- move file importer modifier after lifecycle hooks


## [0.2.11.78] - 2026-02-11

### Features
- replace XML skill definition with Markdown
- add folder refresh flow and library-safe sync paths

### Bug Fixes
- sync current cue when tapping subtitle
- move file importer modifier after lifecycle hooks

### Improvements
- isolate split resizing state and add transcription resize placeholder
- migrate FolderNavigationView logic to ViewModel (MVVM)
- optimize data fetching in MainSplitView and ViewModel

### Chores
- cleanup formatting and spacing in view components
- add MVVM architecture rules and update project formatting
- rewrite README with simplified project introduction and features including vocabulary marking


## [0.2.10.77] - 2026-02-09

### Bug Fixes
- fix alignment guide for cue row textView
- improve layout sizing for cue rows

### Improvements
- switch to observer-based playback tracking
- migrate PlayerManager to async/await and update call sites


## [0.2.10.76] - 2026-02-06

### Improvements
- clean up layout backgrounds and footer positioning


## [0.2.10.75] - 2026-02-06

### Features
- allow editing subtitles directly from the cue row
- add cue row overflow menu

### Chores
- cleanup CHANGELOG.md
- refactor rules into separate files and update AGENTS.md
- add telegram notification for failed tests
- fix handleWordSelection call sites with missing onPlay argument


## [0.2.10.74] - 2026-02-04

### Improvements

- streamline word selection logic and fix playback restoration
- load cues on demand via SubtitleLoader

## [0.2.10.73] - 2026-01-31

### Features

- add plugin infrastructure and counter plugin

### Improvements

- remove ContentPanelView and improve file selection sync

## [0.2.10.72] - 2026-01-27

### Bug Fixes

- align video player title to leading edge
- remove file extension from displayName on import

## [0.2.10.71] - 2026-01-27

### Features

- display audio file name in video player
