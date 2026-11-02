# What LidTap does, checked against its source

A plain-language audit of the LidTap macOS app in this repository, done by reading every Swift source file,
the build and test scripts, the docs and the research notes at upstream commit `158d3ab`. The app built by
this repository's workflow is that source plus the small changes listed in the README.

**Short version.** The README's claim holds: the app has no network code at all, no account, no analytics
and no update check. It reads the motion sensor and the lid-angle sensor, watches the *timing* of your
keyboard and mouse input, and can do exactly eight things, none of which is "run a command". It asks for
Input Monitoring and Accessibility, which are powerful permissions, and uses them narrowly. Nothing in the
code is hidden or at odds with what the documentation says.

## What it reads

| Source | How | Why |
|---|---|---|
| Accelerometer and gyroscope | IOKit HID, `AppleSPUHIDDevice` services with usage page `0xFF00`, usages 3 and 9, about 800 reports a second (`Core/IMUReader.swift`) | A lid tap twists the laptop about its hinge; the gyroscope is the trigger and the features come from both sensors |
| Lid-angle sensor | Same sensor hub, usage page `0x20`, usage `0x8A`, polled about 20 times a second | Taps while the lid is moving are ignored |
| Keyboard, mouse, trackpad | A **listen-only** `CGEvent` tap on key down/up/modifier, mouse down/up, scroll and pointer-move events (`Core/InputMonitor.swift`) | Typing and clicking shake the laptop like a tap. Only the event *type and timestamp* are kept, in a rolling five-second window; key codes are discarded |
| Microphone devices | CoreAudio device properties: mute flag and input volume (`Actions/MeetingControl.swift`) | Privacy Guard reads the current values, sets mute on and volume to zero, and restores the saved values on release. No audio is captured |
| Cameras | CoreMediaIO property "device is running somewhere" | Privacy Guard checks whether any app is using a camera. No video is captured |
| Running and installed apps | `NSWorkspace` and the contents of the Applications folders | The app picker for the Open App action, and finding which meeting app to send the camera shortcut to |

To stream at 800 Hz the app sets three properties on the system's sensor driver (`AppleSPUHIDDriver`):
reporting on, power on, report interval 1 ms. It does not reset them on quit; the sensor returns to its default
rate after sleep or restart. The research notes put the cost at roughly 3% of one CPU core while running.

## What it can do

The action set is a closed list in `Actions/ZoneAction.swift`. There is no shell command, script or URL action
in the app (the Python prototype in `lidtap/` has shell-command actions; it is a separate tool and is not built).

| Action | Mechanism |
|---|---|
| Desktop Left / Right | Posts ⌃← / ⌃→ as keyboard events (needs Accessibility) |
| Play/Pause, Next, Previous | Posts the system media-key events (needs Accessibility) |
| New Note | Opens Notes, waits for it to be frontmost, posts ⌘N (needs Accessibility) |
| Open App | `NSWorkspace` launch or activate, by the bundle identifier you chose in Settings |
| Mission Control | Opens the system's Mission Control app (`com.apple.exposelauncher`); falls back to ⌃↑ |
| Volume Up / Down, Mute Sound | Posts the system volume key events (needs Accessibility) |
| Keyboard Shortcut | Posts the key combination you recorded in Settings, as key down and up (needs Accessibility). The recorder uses a local event monitor inside LidTap's own window, which needs no permission |
| Run Apple Shortcut | Starts `/usr/bin/shortcuts run <name>` as a child process: a fixed executable with the name as an argument, no shell. What the Shortcut then does is up to the Shortcut and Apple's own permission prompts |
| Open Link | Hands the address to `NSWorkspace`, which opens it in your default browser or the app owning the scheme. LidTap itself makes no connection; your browser does. `file:`, `javascript:` and `data:` links are refused |
| Mute Microphone | The same CoreAudio mute as Privacy Guard, as a toggle, with its own saved state |
| Lock Screen | Posts ⌃⌘Q (needs Accessibility) |
| Privacy Guard | A blur panel over every screen at screen-saver level; mutes every input device and re-asserts the mute once a second; if a camera is in use and Accessibility is granted, brings the meeting app forward and posts its camera-toggle shortcut (⌘⇧V Zoom, ⌘⇧O Teams, ⌘⇧V Webex, ⌘E Google Meet), then checks the camera actually stopped. On release it restores the microphones, posts the shortcut again and returns to the previous app |

Guard rails in the code: a tap must be at least as confident as the "Act only when this sure" setting
(default 60%) and at least 85% for Privacy Guard; taps unlike anything recorded are rejected as unfamiliar;
taps within 0.3 s of a key, click or scroll, during pointer movement, during a typing burst, or while the lid
moves are ignored. While Privacy Guard is on, no other zone acts. A click anywhere releases it and the click
is swallowed, so it does not land on whatever is underneath. Since version 1.1, a fresh install runs in
practice mode (recognise and show, run nothing) until the user turns actions on, and any zone can require a
second tap within three seconds before it runs. Calibration taps are not recorded until the user clicks Start
on the tips panel.

## Permissions it asks for

| Permission | Where in the code | Needed for | Declining |
|---|---|---|---|
| Input Monitoring | `InputMonitor.start()` calls `CGRequestListenEventAccess()` at launch if not granted | The event tap above. The IOKit sensor access is gated by the same permission class on some Macs | Falls back to the system's "seconds since last event" counters, which need no permission. If the sensor does not stream, grant it |
| Accessibility | `ActionRunner.perform` asks once, the first time an action needs it; also **Settings › Permissions › Allow…** | Posting the keyboard and media-key events listed above | Those actions report "needs Accessibility" and do nothing |
| Automation (Apple Events) | `Meetings.focusMeetTab` runs `/usr/bin/osascript` against Chrome, Edge, Brave or Safari | Finding a Google Meet tab when Privacy Guard needs to turn a browser camera off. The script scans tab URLs for `meet.google.com/` and returns only "ok" or "none" | Guard skips the camera step |
| Microphone, Camera, Screen Recording, Location, Contacts, Files | Not requested | | |
| Launch at login | `SMAppService`, only when you turn on **Open at login** | | Off by default |

Because the build is ad hoc signed, macOS ties each permission grant to that exact build. After installing a
new build, Accessibility (and sometimes Input Monitoring) must be switched off and on again.

## Network: none

A search of every file under `LidTapApp/Sources` for `URLSession`, `NSURLConnection`, the `Network`
framework (`NWConnection`, `NWListener`), `CFSocket`, `socket(`, `getaddrinfo`, `curl`, `http://` and
`https://` finds nothing. The only URL the app opens is the `x-apple.systempreferences:` deep link into
System Settings. The frameworks it links are AppKit, SwiftUI, Charts, IOKit, CoreAudio, CoreMediaIO and
ServiceManagement. The build workflow repeats the check on the compiled binary.

Two actions added in version 1.1 reach outside the app without the app itself opening a connection: **Open
Link** asks macOS to open an address you typed, in your browser or the owning app, and **Run Apple Shortcut**
runs a Shortcut you named, which can do whatever that Shortcut does. Both run only what you configured for a
zone; neither is assigned by default.

Elsewhere in the repository, two things do touch the network and neither is part of the app:

- The Python prototype (`lidtap/server.py`) runs a web GUI on `127.0.0.1:8765`, protected by a per-run token,
  and can run shell commands you configure as zone actions. It is not built or shipped.
- One test in the `guard` suite opens a Chrome window to `meet.google.com` to test the tab finder. That suite
  is never run by the workflow.

## What it writes

| Path | Content |
|---|---|
| `~/Library/Application Support/LidTap/config.json` | Settings and zone actions, including any key combinations, Shortcut names and links you entered |
| `~/Library/Application Support/LidTap/dataset.json` | Every recorded tap: label, time, lid angle, peak values and the raw 200 ms gyroscope and accelerometer windows. This is your calibration data; it never leaves the folder |
| `~/Library/Application Support/LidTap/status.json` | A one-line status snapshot rewritten each second (rate, lid angle, last ten tap outcomes), used by the tests |
| `~/Library/Preferences/dev.lidtap.LidTap.plist` | The last Settings pane you looked at |
| Unified log, subsystem `dev.lidtap` | Tap strengths, outcomes and zone labels, visible in Console. No key or pointer data |

Set `LIDTAP_DATA_DIR` to move the data folder.

## Things worth knowing

1. **`--test-hooks`** is a developer launch flag. With it, any process on the Mac can replay taps, toggle Privacy
   Guard or open Settings by posting a `dev.lidtap.test` distributed notification. A normal launch never sets it.
   Do not add it to a login item.
2. **Privacy Guard's camera step** sends a fixed shortcut to the meeting app. If you have remapped Zoom, Teams or
   Meet shortcuts, the shortcut could do something else there. It can be turned off in Settings › Zones.
3. **Not notarized.** Gatekeeper blocks the first launch; the README explains the Open Anyway step. This is a
   consequence of building with ad hoc signing, as upstream does, rather than paying for a Developer ID.
4. **The unsafe test suites really act on the Mac.** `hardware` powers the sensor driver off and on and reads
   microphone state; `actions` switches Spaces, toggles Spotify, launches Calculator, creates and deletes a Note
   and posts synthetic clicks; `guard` mutes the microphones, covers the screens, clicks the screen centre, asks
   the test binary for Camera access and starts a capture session, and opens a browser tab; `e2e` quits a running
   LidTap and relaunches it with `--test-hooks`. The workflow runs only `ml`, `detector`, `logic` and `ui`, which
   work on fixture data in temporary folders and never start the sensor or the event tap.
5. **The build script** compiles with `swiftc`, signs with `codesign --sign -` and, unless told `--no-install`,
   quits any running LidTap and replaces `~/Applications/LidTap.app`. It uses a compiler overlay to hide one
   header file in the Command Line Tools during compilation only. No sudo, no system files touched.
6. **Trust follows the source.** The permissions above would let a different version of this app do far more.
   If you ever pull new upstream changes, read the diff before building.

## How to verify this yourself

```bash
grep -rniE 'URLSession|NWConnection|NWListener|CFSocket|socket\(|getaddrinfo|http://|https://' LidTapApp/Sources
```

```bash
grep -rn 'Process()\|osascript\|NSAppleScript' LidTapApp/Sources
```

The first prints nothing. The second prints the Google Meet tab finder in `MeetingControl.swift` and the
Shortcuts runner in `ActionRunner.swift`, both with a fixed executable path and no shell.

## Build record

First build from this repository, [run 1](https://github.com/farhanhaque0619/lid/actions/runs/41494249049)
of the workflow on commit `8f7cf2c`:

| | |
|---|---|
| Runner | GitHub `macos-15`, Apple Silicon |
| Toolchain | Xcode 26.3, macOS 26.2 SDK, Swift 6.2.4 (so the Liquid Glass branch was compiled in) |
| Compile | 52 s, three pre-existing warnings in `AppModel.swift`, no errors |
| Tests | `ml`, `detector`, `logic`, `ui`: 69 passed, 0 failed, 0 skipped. Features match the Python prototype to 1e-13; on upstream's 60 recorded 2×2 taps the three recognisers cross-validate at 91 to 93%, and the app picked logistic regression at 95% |
| Signature | `codesign --verify --strict --deep`: valid; `Signature=adhoc`, identifier `dev.lidtap.LidTap`, no team |
| Linked frameworks | IOKit, CoreAudio, CoreMediaIO, ServiceManagement, AppKit, ApplicationServices, Charts, CoreFoundation, CoreGraphics, Foundation, SwiftUI, Symbols and the Swift runtime. No CFNetwork, no Network.framework |
| Network symbols in the binary | none (checked with `nm -u`) |
| Disk image | `LidTap.dmg`, 1.5 MB, SHA-256 `c00d60cd2e9d06fabb12d3dcafdac4571e16e7c3603681d2fb8b6a4a9282a692` |

Every later run records the same checks in its log, and each release lists its own SHA-256.
