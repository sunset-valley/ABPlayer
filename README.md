# ABPlayer

ABPlayer is a macOS listening-learning workbench built for English learners who want more than passive playback.

## Product Positioning

ABPlayer focuses on a complete learning loop instead of content consumption:

Discover -> Listen -> Mark Issues -> Take Notes -> Review -> Shadowing -> Track Progress

## Core Experience

- Listening-first player with sentence-level control (play/pause, seek, speed, A-B loop)
- Transcript-assisted intensive listening and sentence follow-up
- Learning capture tools: Notes, Marked Clips, Flash Card workflow
- Progress feedback: History, Stats, Streak for habit building
- Saved learning resources with Favorites and personal library organization

## Information Architecture (from PRD)

- Discover: Today's Picks, Podcast
- My Learning: Continue Listening, Downloads, Flash Card, Notes, Marked Clips
- Library: My Uploads, My Resources
- Progress: History, Stats, Streak
- Saved: Favorites

## MVP Scope

- Audio playback and continue-learning flow
- Podcast browsing and Downloads
- Basic Transcript display with sentence-level marking
- Notes and Marked Clips
- History, Stats, and Favorites

## Tech Stack

- Platform: macOS 15.7+
- Language: Swift 6.2
- UI: SwiftUI
- AI Transcription: [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- Project Tooling: [Tuist](https://tuist.io/)

## Project Structure

- `ABPlayer/Sources`: app source code
  - `ABPlayerApp.swift`: app entry
  - `Views/`: split view shell and UI modules
  - `Models/`: menu and domain models
- `ABPlayer/Resources`: bundled assets
- `ABPlayer/Tests`: unit and business-logic tests
- `Docs/PRD.md`: product requirements and roadmap

## Setup

1. Install [Tuist](https://tuist.io/).
2. Install dependencies:

```bash
tuist install
```

3. Generate workspace:

```bash
tuist generate
```

4. Open `ABPlayer.xcworkspace` in Xcode.

## Build

```bash
xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build
```

## Test

```bash
tuist test
```

## Roadmap Highlights

- Phase 1: stabilize listening playback and learning statistics loop
- Phase 2: enhance Transcript editing/annotation and Flash Card system
- Phase 3: expand Shadowing and intelligent feedback
