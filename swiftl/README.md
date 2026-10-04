# SwifTL

A native macOS window app for typed or pasted text translation and screenshot OCR translation.

## Features

- Opens as a normal window with a Dock icon; no menu bar status icon
- Supports resizing, minimizing, and reopening from the Dock or Window → Show SwifTL
- Type or paste multiline text and translate with Command+Return
- The input field supports normal caret movement, selection, and editing
- The window stays visible when other apps are clicked; close it with the top-left close button
- Select and copy translations; input stays available when the window is closed
- Select any area of the screen to capture text (similar to CMD+Shift+4)
- Automatically detects and extracts text from the selected area
- Auto detects the source locally: Chinese → English, other languages → Simplified Chinese
- Read translations with paragraph-by-paragraph bilingual or translation-only display
- English single words show local Dictionary definitions and system pronunciation
- Translate text between multiple languages
- Language selections are remembered automatically; use the button between From and To to swap them
- Check GitHub Releases and install verified updates inside the app
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
3. Launch SwifTL from Applications or the Dock
4. Leave From on Auto for smart Chinese/English translation, or choose a source and target manually
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
an ad-hoc signature, and creates a verified
`SwifTL.dmg` with an Applications shortcut. Outputs default to `../dist`; pass
an output directory as the first argument to override it. Xcode is required.
This build is for local testing and is not notarized for public distribution.

Open `../dist/SwifTL.app` to show the main window. Closing the window keeps the app
and current text in memory; click its Dock icon to reopen it. Use Command+Q to quit.
Leave **From → Auto** enabled, or choose source and target languages manually, then click **Translate** for typed/pasted text or **Screenshot** for OCR translation.
Screen Recording permission must be granted by the user in System Settings
for screenshot capture; restart the app if macOS requests it.


## Translation checks

```sh
bash swiftl/scripts/check.sh
# Also send non-sensitive multilingual and paragraph samples to Google:
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

## Normal-window update

SwifTL now uses a standard, resizable macOS window and a Dock icon, without
a menu bar status item. Close the window to keep current text in memory; reopen
it from the Dock or Window → Show SwifTL (Command+1). Command+Q quits the app.
The main window remembers its position and size.

Universal Release build, app signature, DMG checksum, translation checks, and
a real typed English-to-Chinese translation with Command+Return passed.
Window reopening preserved both input and translation. Screenshot selection
cancellation returned to the main window; full OCR capture still requires the
user’s Screen Recording permission and was not verified in this update.

## Quick selection translation

Keep SwifTL running, select text in another app, and press **Option+Shift+T**.
The app reads the selected text through Accessibility, falling back to a
simulated copy when necessary. It attempts to restore all existing clipboard
representations after that copy; if focus changes, it abandons capture.
No translation is triggered just by selecting text. An optional **Show a button
after selecting text** setting is off by default. When enabled, an Accessibility
selection read after mouse release can display a small button near the pointer.
The selection is sent for translation only when that button is clicked. This
mode does not simulate copy and works only where the source exposes selection.

- Choose another selected-text shortcut in Settings: Option+Shift+T,
  Control+Option+T, or Command+Shift+Y. Registration conflicts are shown there.
- Enable SwifTL in **System Settings → Privacy & Security → Accessibility**
  for direct selection reading and automatic copy. The app never grants this
  permission itself and does not request it at startup.
- Without Accessibility access, copy text yourself and press
  **Command+Option+Shift+T**, or click the clipboard button in the main window.
- A small nonactivating result window appears near the selection, or near the
  pointer if the source app does not provide selection bounds. It uses the main
  window's current languages and translation provider.
- Copy the translation, read it aloud using macOS voices, or pin the window.
  An unpinned result closes on an outside click; Close dismisses it. Escape
  dismisses a focused result, or works globally when Accessibility is enabled.
  Pinning keeps it visible until explicitly dismissed.
- **Open in main window** transfers the original text, translation, and languages
  after the request finishes. Quick requests leave main-window edits untouched.
- A **Translate with SwifTL** system service is declared for selected text.
  Install the app in Applications and enable it under Keyboard → Keyboard
  Shortcuts → Services if it does not appear in the source app's Services menu.

Cross-app Accessibility is incompatible with App Sandbox, so this direct-download
build now runs without the sandbox. Existing sandboxed language preferences are
migrated if the new preferences have no saved language pair. Screenshot permission
remains separate. Ad-hoc rebuilds may require reauthorizing Accessibility; a stable
Developer ID signature is needed for smoother permission handling across updates.

Verification: universal build, app signature, DMG checksum, model regression checks,
real clipboard translation, pin/copy controls, speech start/stop controls, and transfer
to the main window were checked. Direct cross-app AX capture, the optional selection button, automatic copy fallback,
and system-service discovery were not fully verified because Accessibility was not
granted and the test app was run outside Applications. Global hotkeys registered
without a conflict, but the UI automation did not trigger Carbon hotkeys; physical
keyboard triggering remains to be checked. Actual audio output was not measured.

## Chrome selection compatibility

The selection reader enables Chromium's accessibility tree and looks for selection
on the focused element, its parents, the pointer's enclosing web area, and web
areas in the active window. It also supports opaque browser text-marker ranges.
It reads selected text only, never a control's whole value, skips secure fields,
and bounds tree traversal and AX request time. Reads run off the UI thread;
mouse or application changes discard outdated automatic-button results.

Settings now show **Accessibility: Enabled** or **Not enabled for this copy of
SwifTL**, plus the last automatic-button capture status. If macOS shows an enabled
SwifTL entry but the app reports no permission, remove that entry and add the
currently running app again. Ad-hoc signatures change with a rebuild, so an older
copy's authorization may not apply. Keep one installed copy in Applications.
During local verification, macOS retained the signature of an older unpacked
GitHub build even after the permission switch was enabled. The TCC log explicitly
reported a code-requirement mismatch with the running `dist/SwifTL.app`. Old test
copies were unregistered and archived; permission must be re-added for the current
copy before live Chrome selection can be verified.

For Chrome: enable **Show a button after selecting text**, confirm **Accessibility:
Enabled**, close an existing quick result, then drag across ordinary webpage text
and release the mouse. The button should appear near the pointer. Selections in
SwifTL itself do not trigger it. For images or a webpage that exposes no selected
text, use Screenshot or copy text and invoke clipboard translation.

Tests cover browser group focus, complete web-area selection across fragments,
missing focus, secure fields, whitespace, unrelated toolbar selection, and cyclic
trees. Local universal build, signature, DMG checksum, and translation checks passed.
The GitHub Actions universal packaging build also passed for commit `9064496`.
A new Chrome test page was prepared; live selection detection is pending effective
Accessibility permission for the rebuilt app.

## Automatic language, bilingual reading, and word mode

**From → Auto** is the default for this update. SwifTL detects the input language
locally with Natural Language, translating Chinese (including Traditional) to
English and other languages to Simplified Chinese. A single English-word candidate
is treated as English. Short or ambiguous input can be misidentified; choose From
manually to override it. Google receives `sl=auto`, and DeepL's automatic requests
omit `source_lang`. The direction is chosen once locally before translation;
provider detection never triggers an additional translation request.

Auto shows the computed target under To. Select a concrete From language to choose
To manually. Previous manual choices remain saved. After a successful Auto result,
Swap switches to the reversed actual direction in manual mode. Unknown or unavailable
source languages cannot be swapped automatically.

**Bilingual** puts each original paragraph directly above its translation. Switch
to **Translation only** to hide the originals; this display choice is shared between
the main window and quick results and is remembered. Blank lines separate paragraphs;
single line breaks remain inside a paragraph. CRLF is normalized. Google translates
one paragraph at a time; DeepL uses ordered arrays in batches of up to 50 texts,
kept below its request-size limit. Copy exports translated paragraphs only.

All paragraphs must succeed before the translation is published. A failure retains
the original and allows retry, without showing a partially aligned result. Editing
while a request runs is allowed; a notice makes clear that the result belongs to
the submitted snapshot. Screenshot OCR keeps a separate original without replacing
manual input. Vision revision 3 enables automatic language detection, and OCR runs
on a background queue so the window remains responsive.

An English single word (including internal apostrophes/hyphens and surrounding
punctuation) automatically shows a word card. **Pronounce** reads the original in
English; **Text mode** switches that result to ordinary bilingual display.
**Local dictionary** uses macOS Dictionary Services and presents the definition as
provided, without parsing or fabricating examples. Missing dictionaries do not
block translation. **Open Dictionary** opens the word in Apple's Dictionary app,
where dictionaries can be enabled in settings. Local lookup and pronunciation
remain available after a network translation failure. No extra account, key,
third-party dictionary service, or text history is added.

### Verification for this update

- Production-model checks cover auto/manual modes and saved preferences, language
  detection, word boundaries, missing dictionaries, paragraph order, batch limits,
  response-count errors, failure/retry, edited snapshots, stale dictionary callbacks,
  screenshot-original isolation, and complete quick-result transfer.
- Actual Google translations passed for English, Simplified/Traditional Chinese,
  Japanese, multiple paragraphs, special characters, and an English single word.
- Production Vision OCR recognized a generated English image in Auto and manual
  modes, without screen-recording access. First use can take longer while macOS
  compiles its recognition models.
- Native UI checks passed for bilingual/translation-only display, word definitions,
  Text mode, input-change notices, Command+Return, copy feedback, language swap,
  window reopening, and opening Dictionary at the selected word. Pronunciation
  was triggered through the UI; audible output was not independently assessed.
- Universal Release build, ad-hoc signature, and DMG checksum passed. Live DeepL
  calls were not made; its batching and response parsing were checked with mocks.
- The rebuilt app reports no effective Accessibility permission. Live Chrome
  selection remains unverified. Full screen capture through OCR and quick-panel
  UI transfer also remain unverified (the UI tool kept targeting the main window);
  the shared result model and transfer were checked automatically. Reauthorize the
  installed app copy for Accessibility and Screen Recording when required.

## In-app GitHub updates

Use **SwifTL → Check for Updates…** in the app menu, or the **Updates** section in
Settings. SwifTL checks the public `hihowie/swiftl` latest-release endpoint without
a login or token. Only stable releases with a newer numeric version are offered;
manual Actions artifacts and prereleases are excluded. Nothing is downloaded until
you click **Install and Restart**.

The app downloads the release's universal ZIP, verifies the SHA-256 digest provided
by GitHub, validates archive paths, bundle identity, version, and code signature,
then prepares the new app beside the running copy. A separate helper waits for
SwifTL to quit, swaps in the new copy, and reopens it. The previous copy remains as
a hidden `.SwifTL-backup-*.app` beside the installed app. If the replacement or
reopen command fails, the helper attempts to restore the previous copy. An app crash
after macOS accepts the reopen command cannot be detected by this helper.

Install SwifTL in a writable Applications folder first. Automatic replacement is
unavailable from a mounted DMG, App Translocation, or a read-only app folder.
**Download installer** and **View release** provide manual fallbacks; releases
without a ZIP digest support manual installation only. Settings and Keychain data
are kept; current input/results are cleared by the restart. Ad-hoc signing means
macOS may require Accessibility or Screen Recording authorization again after an
update. Package hash verification does not provide Developer ID notarization.

Updater checks cover numeric versions, duplicate checks, missing/draft/prerelease
responses, unavailable networks and retry, invalid URLs/digests, signed ZIP
validation, corrupted signatures, symbolic links, replacement, backup, and rollback.
The installer tests use disposable app copies and do not replace the running app.
`check.sh --live` additionally checks the published stable release and downloads,
verifies, and installs its real ZIP in a disposable copy.
