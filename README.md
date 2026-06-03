# Timesheet

A lightweight macOS menu bar app for tracking time and saving entries directly to Google Calendar.

## What it does

- Sits in the menu bar with no Dock icon — click the ⏱ icon to open it
- **Start a timer** for a task or meeting; the elapsed time shows live in the menu bar
- **Stop** to review the entry — edit start/end times before saving
- **Saves to Google Calendar**: events go into a calendar you name **"Timesheet"**
- Colour-coded: Tasks save in green (`colorId 10`), Meetings in yellow (`colorId 5`)
- One-time Google Sign-In via OAuth — token is stored in Keychain, no repeated prompts

## Requirements

- macOS 26 (Tahoe) or later
- A Google account
- A Google Calendar named exactly **"Timesheet"** (create it at [calendar.google.com](https://calendar.google.com) → Other calendars → **+** → New calendar)

## Installation

1. Go to the [**Releases**](../../releases/latest) page
2. Download **Timesheet.dmg**
3. Open the DMG and drag **Timesheet.app** to the Applications folder
4. Launch the app — the ⏱ icon appears in the menu bar

> **First launch note:** macOS may show a Gatekeeper warning because the app is distributed outside the App Store. To open it: right-click (or Control-click) the app → **Open** → **Open** in the dialog.

## Usage

1. Click ⏱ in the menu bar
2. Enter an entry title, choose **Task** or **Meeting**, then **Start Timer**
3. Click **Stop** when done
4. Adjust start/end times if needed, then **Save to Calendar**
5. Authenticate with Google the first time — the browser opens, you sign in once, and subsequent saves go straight through
6. **Done** resets the popover for the next entry

## Building from source

**Prerequisites:** Xcode 26 or later, Apple Developer account

```bash
git clone https://github.com/YOUR_USERNAME/Timesheet.git
cd Timesheet
open Timesheet.xcodeproj
# Set your Team in Signing & Capabilities, then ⌘R
```

### Creating a release build

```bash
chmod +x build_release.sh
./build_release.sh
# Outputs Timesheet.zip in the project root
```

See [`build_release.sh`](build_release.sh) for details. You need a **Developer ID Application** certificate to produce a distributable build — see [Apple's documentation](https://developer.apple.com/documentation/xcode/notarizing-macos-software-before-distribution) for notarization steps.
