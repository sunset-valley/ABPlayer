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
