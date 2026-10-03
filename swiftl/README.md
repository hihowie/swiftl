# Cursor Translator

A macOS menu bar app for typed or pasted text translation and screenshot OCR translation.

## Features

- Lives in the macOS menu bar for easy access
- Type or paste multiline text and translate with Command+Return
- The input field supports normal caret movement, selection, and editing
- The panel stays visible when other apps are clicked; close it with the top-left close button
- Select and copy translations; input stays available when the panel is closed
- Select any area of the screen to capture text (similar to CMD+Shift+4)
- Automatically detects and extracts text from the selected area
- Translate text between multiple languages
- Language selections are remembered automatically; use the button between From and To to swap them
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
screenshot cancellation, and automatic language persistence. They use an isolated
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

## Automatic GitHub Releases

Push a new version tag to build and publish a GitHub Release:

```sh
git tag -a v1.1.0 -m "SwifTL 1.1.0"
git push origin v1.1.0
```

Tags must use `vMAJOR.MINOR.PATCH`; prerelease tags such as `v1.1.0-beta.1`
are also supported and create prereleases. Use a new version tag for each
release. The app's version comes from the tag, and its build number comes
from the GitHub Actions run number.

The workflow runs translation checks, builds and verifies both arm64 and
x86_64 architectures, packages a DMG and ZIP, and publishes them alongside
`SHA256SUMS.txt`. Re-running a tag workflow replaces that release's assets.
No personal access token or Apple certificate secret is needed; the workflow
uses the repository's `GITHUB_TOKEN` and an ad-hoc app signature.

For a build-only check without publishing a release, use GitHub Actions →
**Build and release macOS app** → **Run workflow**, or:

```sh
gh workflow run release.yml --ref main
```

The manual run attaches download artifacts to the Actions run and does not
create a tag or public release. Builds are not notarized by Apple; Developer ID
signing and notarization require a separate certificate setup.
