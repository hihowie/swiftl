# Cursor Translator

A macOS menu bar app for typed or pasted text translation and screenshot OCR translation.

## Features

- Lives in the macOS menu bar for easy access
- Type or paste multiline text and translate with Command+Return
- Select and copy translations; input stays available when the panel is closed
- Select any area of the screen to capture text (similar to CMD+Shift+4)
- Automatically detects and extracts text from the selected area
- Translate text between multiple languages
- Simple, lightweight, and intuitive interface

## Requirements

- macOS 13.0 or later
- Xcode 14.0 or later

## Setup

1. Grab the latest Github Release or clone this repository
2. Open the `SwifTL.xcodeproj` file in Xcode
3. Build and run the application

## Usage

1. Open DMG File and drag drop SwifTL into Applications folder
2. Navigate to Settings > Privacy & Security to Allow SwifTL to run
3. Click the translator icon in the menu bar
4. Select your source and target languages
5. Type or paste text and click "Translate" (or press Command+Return).
6. For screenshot translation, click "Screenshot". Press Escape to cancel selection.
7. Click and drag to select the area containing text you want to translate
8. The translated text will appear in the app's interface

## Implementation Notes

- The app uses Vision framework for OCR (Optical Character Recognition)
- SwifTL uses a free Google Translate Web API to be offered 100% FREE. If you would like to use your own DeepL API key you can do so from the SwifTL settings.


## Local build and package

From the repository root, run:

```sh
bash swiftl/scripts/package.sh
```

The script creates a universal Release app (Apple Silicon and Intel), applies
an ad-hoc signature with the app sandbox entitlements, and creates a verified
`SwifTL.dmg` with an Applications shortcut. Outputs default to `../dist`; pass
an output directory as the first argument to override it. Xcode is required.
This build is for local testing and is not notarized for public distribution.

Open `../dist/SwifTL.app`, then click its book icon in the macOS menu bar.
Choose source and target languages and click **Translate** for typed/pasted text, or **Screenshot** for OCR translation.
Screen Recording permission must be granted by the user in System Settings
for screenshot capture; restart the app if macOS requests it.


## Translation checks

```sh
bash swiftl/scripts/check.sh
# Also send three non-sensitive sample texts to Google:
bash swiftl/scripts/check.sh --live
```

Checks cover input validation, duplicate submission, parameter encoding,
segmented responses, malformed data, network errors, retry, clearing,
screenshot cancellation, and default language persistence. They use an isolated
preferences suite and do not modify your saved languages. Text history is kept
only in memory while the app is running.


## Verification for the input-translation update

- Universal Release build, ad-hoc signature verification, and DMG checksum passed.
- Automated view-model checks passed, including the Google and DeepL request paths.
- Real Google requests passed for English to Chinese, Chinese to English, and
  multiline text containing ampersands, plus signs, punctuation, Chinese, and emoji.
- UI checks passed for paste, Command+Return, Return as newline, copying to the
  clipboard, clearing, panel reopening, and Escape to cancel screenshot selection.
- Screenshot capture through OCR was not verified because Screen Recording access
  must be granted by the user. A real DeepL request was not made; its request format
  and response handling were checked using mocked responses.
