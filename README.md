# ABPlayer

A native macOS media player designed for language learners who practice intensive listening.

## Key Features

- **A-B Looping**: Precise control to loop specific segments of audio or video.
- **AI Transcription**: On-device speech-to-text powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit).
- **Smart Library**: Automatically organizes audio files with their subtitles and PDF materials.
- **Study Tools**: Integrated PDF viewer and segment management for focused study.
- **Vocabulary Marking**: Mark and track unknown words directly from subtitles.
- **Progress Tracking**: Automatically records your listening practice time.
- **Keyboard First**: Extensive shortcuts for hands-free control.

## Tech Stack

- **Platform**: macOS 15.7+
- **Language**: Swift 6.2
- **UI**: SwiftUI
- **AI Engine**: WhisperKit (CoreML)
- **Build Tool**: [Tuist](https://tuist.io/)

## Building the Project

This project uses Tuist for project generation.

1. Install [Tuist](https://tuist.io/).
2. Run `tuist install` to fetch dependencies.
3. Run `tuist generate` to create the Xcode project.
4. Open `ABPlayer.xcworkspace` and build.
