## [0.4.7.136] - 2026-04-08

### Bug Fixes
- make utility windows single-instance
- prune stale library roots on refresh
- clear stale playback state on delete and refresh

### Chores
- configure Mac App Store metadata
- add MAS target and gate Sparkle


## [0.4.6.135] - 2026-04-07

- No significant changes.


## [0.4.5.134] - 2026-04-07

### Features
- add auto-wrap file imports


## [0.4.4.133] - 2026-04-06

### Bug Fixes
- show play/pause HUD before toggle and trim agent guide
- prevent screen sleep during playback

### Other
- add working philosophy


## [0.4.3.132] - 2026-04-05

### Bug Fixes
- harden retry and subtitle commit flow


## [0.4.2.131] - 2026-04-05

### Features
- add new landing page

### Improvements
- remove resize placeholder wrapper

### Other
- rename LandingPage


## [0.4.1.130] - 2026-04-05

### Bug Fixes
- remove duplicate zip


## [0.4.1.129] - 2026-04-05

### Bug Fixes
- sign


## [0.4.1.128] - 2026-04-05

### Bug Fixes
- notary retrying


## [0.4.1.127] - 2026-04-04

### Chores
- add notarized release workflow
- harden notarization script

### Other
- update ci
- update docs


## [0.4.0.126] - 2026-04-04

### Bug Fixes
- reduce progress UI update churn
- repair orphaned listening sessions

### Improvements
- remove ffmpeg dependency for media import


## [0.3.9.125] - 2026-04-03

### Bug Fixes
- recompute layout on viewport width changes
- use accent color for loop button

### Chores
- add UI demo states and guidance copy
- add UI coverage for unified states


## [0.3.8.124] - 2026-04-02

### Chores
- cover session slice aggregation edge cases


## [0.3.7.123] - 2026-04-02

- No significant changes.


## [0.3.7.122] - 2026-04-02

### Bug Fixes
- harden runtime loading and follow playback
- preserve and apply custom transcription mirrors explicitly
- center chart x-axis labels


## [0.3.7.121] - 2026-04-01

### Improvements
- extract app dependency container


## [0.3.6.120] - 2026-04-01

### Features
- add subtitle toggle and sync updates


## [0.3.5.118] - 2026-03-31

### Features
- enforce warmup idle windows for sessions
- persist playback context state

### Bug Fixes
- keep playback after edit


## [0.3.4.117] - 2026-03-31

### Bug Fixes
- stabilize split divider cursor behavior


## [0.3.3.116] - 2026-03-30

### Other
- fix ci


## [0.3.2.115] - 2026-03-30

### Features
- polish playback controls and divider feedback

### Other
- refactor ci flow
- add pre/next buttons for audio player


## [0.3.1.114] - 2026-03-30

### Bug Fixes
- automatically scroll and highlight subtitles

### Other
- Ci/build and relase (#161)
- test export archive (#160)


## [0.3.0.113] - 2026-03-29

### Features
- bundle signed ffmpeg

### Other
- fix ci for including ffmpeg
- update app icon
- add docs for notarization


## [0.2.30.112] - 2026-03-28

### Features
- add service, vm, and views

### Improvements
- remove built-in plugin surface from app shell


## [0.2.29.111] - 2026-03-27

### Features
- add annotation removal flow

### Bug Fixes
- polish annotation popover sizing


## [0.2.28.110] - 2026-03-24

### Features
- implement collection and note creation functionality with UI integration


## [0.2.27.109] - 2026-03-24

### Features
- refresh entry list styling for better scanability
- add entry filtering by style preset and enhance note editing

### Improvements
- optimize sorting logic and improve test function naming


## [0.2.26.108] - 2026-03-23

### Features
- add windowed notes browser with SwiftData-backed notes

### Bug Fixes
- enable csv export for media annotations

### Chores
- move command menu and add ui-test postmortem
- document transcript scroll regression
- skip UI tests in CI runs


## [0.2.26.107] - 2026-03-23

### Features
- add windowed notes browser with SwiftData-backed notes

### Bug Fixes
- enable csv export for media annotations

### Chores
- move command menu and add ui-test postmortem
- document transcript scroll regression


## [0.2.25.106] - 2026-03-23

### Bug Fixes
- stabilize scroll sizing and add UI regression coverage


## [0.2.24.105] - 2026-03-22

### Bug Fixes
- build Refresh S3 payload via jq

### Chores
- 0.2.23

### Other
- Add LICENSE file (#150)


## [0.2.23.104] - 2026-03-22

### Chores
- 0.2.23


## [0.2.22.103] - 2026-03-22

### Features
- move to V2 persistence with stable cue IDs

### Bug Fixes
- stabilize underline rendering and subtitle edit UI input


## [0.2.21.102] - 2026-03-22

### Features
- add cancel action for FFmpeg download

### Bug Fixes
- restore subtitle editing and add UI coverage

### Chores
- refresh S3 storage after publish


## [0.2.20.101] - 2026-03-22

### Features
- unify style menu and route tests through ABPlayerDev

### Bug Fixes
- move actions to a scrollable top row and widen popover
- reset legacy store only once before 0.2.17

### Improvements
- open style management in dedicated window
- move to shared style preset architecture

### Chores
- add ui testing gate playbook


## [0.2.19.100] - 2026-03-21

### Improvements
- drop extra update mirrors and reuse ffmpeg status


## [0.2.18.99] - 2026-03-21

### Features
- add preset mirror options for transcription downloads


## [0.2.17.98] - 2026-03-21

### Bug Fixes
- reset legacy store only for <=0.2.17


## [0.2.16.97] - 2026-03-21

### Features
- add selectable Sparkle feed source in settings
- group cross-cue text marks into unified selection actions


## [0.2.15.96] - 2026-03-21

### Chores
- prepare 0.2.16-95 release and align git-release steps


## [0.2.16.95] - 2026-03-21

- No significant changes.


## [0.2.15.94] - 2026-03-21

### Bug Fixes
- stabilize selection popover anchoring and simplify chrome
- restore text selection after manual scroll


## [0.2.14.93] - 2026-03-20

### Other
- Rescue/pre rebase local (#141)


## [0.2.14.92] - 2026-03-20

### Bug Fixes
- support custom download endpoint for models and tokenizer
- vendor WhisperKit dependencies and disable fallback downloads
- skip download when model already exists on disk

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
