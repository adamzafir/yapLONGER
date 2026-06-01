# Scripties

Scripties is a teleprompter app for practicing presentations. It lets you write or edit scripts, read them back with voice-driven autoscroll, record practice sessions, and review performance after each run.

This project was built as part of the Swift Accelerator Programme 2025.

## Links

- Website: https://scripties-4ug0.onrender.com/
- App Store: https://apps.apple.com/sg/app/scripties/id6755456358

## What it does

- Create and manage presentation scripts
- Practice with a teleprompter that advances as you speak
- Record practice sessions for later playback
- Review delivery feedback using:
  - Words per minute
  - Consistency score
- Browse past reviews for each script
- Complete a short onboarding flow before first use

## Tech Stack

- Swift
- SwiftUI
- AVFoundation
- Speech
- Accelerate

## Requirements

- Xcode
- iOS Simulator or an iPhone/iPad running the app
- Microphone permission
- Speech recognition permission

## Getting Started

1. Open `yapLONGER.xcodeproj` in Xcode.
2. Select the `yapLONGER` scheme.
3. Choose an iPhone or iPad simulator, or a physical device.
4. Build and run the app.

## Usage

1. Complete onboarding on first launch.
2. Create a new script from the Scripts screen.
3. Open the script and start a practice session.
4. Read naturally while the teleprompter follows your speech.
5. Stop the session to review the recording and feedback.
6. Save the review to track your progress over time.

## Project Structure

- `iOS/Viewmodels` - app state, persistence, audio analysis, and review logic
- `iOS/Views/Screens` - SwiftUI screens for onboarding, scripts, teleprompter, recording, and review
- `iOS/Others` - assets and supporting media

## Notes

- The app uses local device capabilities for speech recognition and audio recording.
- Review scores are generated from the practice session, so results depend on the quality of the recording and recognition input.
