# LidTap (private build)

> **Based on [LidTap by Yemcube](https://www.instagram.com/yem.cube)** (Instagram [@yem.cube](https://www.instagram.com/yem.cube)),
> from [harsha20599/lidtap](https://github.com/harsha20599/lidtap). This repository is a personal fork built
> from source for private use under the [LidTap License](LICENSE): MIT plus credit to the original author, and
> no commercial use without their approval. Nothing here is affiliated with or endorsed by Apple.

**Tap your MacBook lid.** LidTap turns the corners of your MacBook's display into buttons, with no extra
hardware. It listens to the motion sensor inside the laptop: a tap on the lid twists the machine slightly
about its hinge, the gyroscope feels that twist about 800 times a second, and a small model trained on
*your* taps works out which part of the screen you tapped. Everything runs on your Mac. No network access,
no account, nothing leaves the machine; see [AUDIT.md](AUDIT.md) for what the code was checked for.

- [Download and install](#download-and-install)
- [Permissions, and why](#permissions-and-why)
- [Calibrate](#calibrate)
- [Zones and actions](#zones-and-actions)
- [Fix a zone that misreads](#fix-a-zone-that-misreads)
- [Turn it off, remove it](#turn-it-off-remove-it)
- [Which Macs work](#which-macs-work)
- [Build it yourself](#build-it-yourself)
- [What this fork changes](#what-this-fork-changes)
- [License](#license)

## Download and install

1. Download **LidTap.dmg** from the [latest release](https://github.com/farhanhaque0619/lid/releases/latest).
   It is built from this repository's source by the [Build LidTap](.github/workflows/build.yml) workflow on a
   macOS runner. The release notes show the SHA-256 of the file.
2. Open the disk image. Optional but recommended: confirm this Mac has the sensor first. In Terminal:
   ```bash
   sh /Volumes/LidTap/check_mac.sh
   ```
   It only reads hardware and version info and needs no sudo.
3. Drag **LidTap** onto the **Applications** folder in the disk image window.
4. Open LidTap from Applications. The app is ad hoc signed and not notarized, so macOS blocks the first
   launch:
   - **macOS 15 or later:** click **Done**, open **System Settings › Privacy & Security**, scroll down to the
     message about LidTap and click **Open Anyway**, then confirm.
   - **macOS 14:** right-click **LidTap.app › Open › Open**.
   - If macOS says the app is **"damaged"**, that is the download quarantine flag. In Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/LidTap.app
     ```
5. A hand icon appears in the menu bar and Settings opens. Grant the permissions below, then click **Calibrate**.

**Updating:** replace the app in Applications. Calibration and settings are kept. Because the signature changes
with every build, switch LidTap off and on again in **Privacy & Security › Accessibility** (and Input Monitoring)
after an update.

## Permissions, and why

LidTap asks for these, in roughly this order. None of them is granted by the installer; you decide each one.

| Prompt | When it appears | What LidTap uses it for | If you decline |
|---|---|---|---|
| **Gatekeeper** ("unidentified developer" / "could not verify") | First launch | Nothing: the build is ad hoc signed, not notarized | See step 4 above |
| **Input Monitoring** | First launch | A listen-only event tap that records the *time* of keystrokes, clicks, scrolls and pointer moves so bumps from typing are not read as taps. Key codes are discarded. On some Macs the motion sensor itself will not stream until this is granted | Taps work with a coarser typing filter; if the motion sensor stays at 0 Hz in Settings › Permissions, grant it |
| **Accessibility** | The first time a zone action runs, or **Settings › Permissions › Allow…** | Posting the keystrokes the actions need: ⌃← and ⌃→ for Spaces, the Play/Pause, Next and Previous media keys, ⌘N in Notes, and the camera shortcut in Zoom, Teams, Webex or Meet for Privacy Guard | Desktop and music zones do nothing (the app tells you). Privacy Guard still blurs and mutes |
| **Automation** (for Chrome, Edge, Brave or Safari) | Only when Privacy Guard fires while a camera is on, no Zoom, Teams or Webex is running, and that browser is | An AppleScript that looks through the browser's open tabs for a Google Meet address and brings it forward | Privacy Guard skips the camera step |

LidTap never asks for **Microphone** or **Camera** access. Privacy Guard mutes by setting the input devices'
mute and volume properties and restores the exact previous values; it checks whether a camera is in use by
reading a system flag, and never captures audio or video. "Open at login" is off until you turn it on in
Settings › General.

Accessibility and Input Monitoring are powerful grants: an app holding them can type anywhere and see every
key. LidTap uses them only as described above, and you can verify that in the source, which is why this fork
is built from source rather than from a downloaded binary.

## Calibrate

Calibration takes about two minutes. Start with the **2×2** grid; fewer zones are more reliable.

Before you start: sit the laptop on a desk, open the lid to the angle you normally use, and keep your hands
off the keyboard and trackpad while tapping. LidTap ignores taps that land right after a click or while the
pointer moves, so a hand resting on the trackpad will make it refuse taps.

1. Click the hand icon in the menu bar, then **Calibrate**. The display goes dark and shows the zones with a
   dot in the highlighted one.
2. **Tap the dot** with a quick, light fingertip flick, **about half a second apart**, as many times as the zone
   asks (five at a time, fifteen per zone in total, in a shuffled order). **Never press hard on the display**:
   LidTap feels the whole laptop move, so force gains nothing, and pressing on a screen can leave marks.
3. Watch the meter at the top. **Good tap** is what you want. **A little crisper** means the tap was too soft
   to record. **Gentler is fine** means it was harder than it needs to be. Tap too soon after the last one and
   it says **Wait for the screen to settle**.
4. Made a mistake? **Undo** removes the last tap. **Stop** or **Esc** ends calibration early; what you recorded
   so far is kept and trained.
5. When every zone is full, LidTap asks to **Record 20 Seconds** of what is *not* a tap. Do it: type a sentence,
   click the trackpad, knock the desk, nudge the lid. Just don't tap the screen.
6. LidTap trains and shows **how many taps land in the right zone**, with a reliability percentage per zone.
   Anything at or above 90% is good. Weak zones are called out; **Add More Taps** gives each zone five more.

With crisp taps on 2×2, upstream measured 95% correct. Taps LidTap is not sure about are ignored rather than
guessed, and the menu bar panel shows what happened to your last tap.

## Zones and actions

The default 2×2 layout is already what this build is meant for:

| Zone | Where | Action |
|---|---|---|
| 1 | Top left | **Desktop Left**: switch to the Space on the left |
| 2 | Top right | **Desktop Right**: switch to the Space on the right |
| 3 | Bottom left | **Play / Pause**: Music, Spotify, YouTube, whatever is playing |
| 4 | Bottom right | **Privacy Guard**: mute every microphone, hide every screen, and turn the meeting camera off |

To change a zone: **Settings › Zones**, click the zone on the drawn display, pick an action. **Try It** runs the
action right away so you can check it. Right-clicking a zone in the menu bar panel does the same. Other actions
available: Next Track, Previous Track, New Note, Open App (launch or bring forward any app), Nothing.

**Privacy Guard** needs to be at least 85% sure of the zone before it fires. Tap the zone again, or click
anywhere, to come back: the screens return, the microphones are restored exactly as they were, and the camera
is turned back on in the meeting app. In **Settings › Zones** (with the Guard zone selected) you can turn
off **"Turn the camera off in meetings"**. Consider starting that way: the camera step sends the meeting app's
standard shortcut, and if you have remapped shortcuts in Zoom, Teams or Meet, it could trigger something else.

## Fix a zone that misreads

- **Check which zone is weak:** **Settings › Training** shows reliability per zone and a table of where
  taps went. Below 85% is flagged, below 75% is red.
- **Top it up:** **Calibrate Again…** in the menu bar panel (or **Calibrate…** in Training) only asks for taps in
  zones that have fewer than fifteen usable ones; if all are full, it adds five to each.
- **Redo one zone from scratch:** in **Training › Recorded taps**, click the trash icon next to that zone, then
  **Calibrate Again…**. Only that zone is asked for.
- **Taps refused as too soft, or bumps counted as taps:** **Settings › Detection** has the live motion trace and
  the sliders. Lower **Minimum tap strength** only if genuinely crisp taps are refused; raise **Minimum** if
  desk knocks register.
- **Wrong zone fires:** in **Training**, raise **Act only when this sure** so LidTap says "Not sure" instead of
  guessing, or lower **Ignore unfamiliar taps** to be stricter.
- **Start over:** **Training › Delete All…**, or switch grids in **Zones › Layout** (that discards the zone taps
  and keeps the bump examples).

Lid angle and surface matter: a model trained at a desk may need a top-up on your lap or at a very different
lid angle.

## Turn it off, remove it

**Pause:** the switch at the top of the menu bar panel. The sensor keeps streaming but nothing acts.

**Quit:** menu bar panel › **Quit LidTap** (⌘Q). If you turned on **Open at login**, turn it off first in
**Settings › General**, or remove LidTap under **System Settings › General › Login Items & Extensions**.

**Remove completely:**

1. Quit LidTap.
2. Delete the app: `/Applications/LidTap.app` (or `~/Applications/LidTap.app` if you put it there).
3. Delete your recorded taps and settings:
   ```bash
   rm -rf ~/Library/Application\ Support/LidTap
   ```
   and the one preference it stores (the last Settings pane you looked at):
   ```bash
   defaults delete dev.lidtap.LidTap 2>/dev/null; true
   ```
4. Remove its permissions in **System Settings › Privacy & Security**: select LidTap under **Accessibility** and
   click **−**; do the same under **Input Monitoring**; under **Automation**, untick or remove LidTap. The
   Terminal equivalent, which also works after the app is gone:
   ```bash
   tccutil reset Accessibility dev.lidtap.LidTap
   ```
   ```bash
   tccutil reset ListenEvent dev.lidtap.LidTap
   ```
   ```bash
   tccutil reset AppleEvents dev.lidtap.LidTap
   ```

LidTap raises the motion sensor's report rate while it runs and does not lower it again on quit; the
sensor returns to its default the next time the Mac sleeps or restarts.

## Which Macs work

- An Apple Silicon MacBook **with the motion sensor**: MacBook Air or Pro with M2 or later, or the 14"/16"
  MacBook Pro with M1 Pro or M1 Max. The **M3 Pro MacBook Pro** this build is for is in that list.
- **Not** the M1 MacBook Air, the 13" M1 MacBook Pro, desktop Macs or Intel Macs: they have no motion sensor.
- **macOS 14 Sonoma or later.**
- `tools/check_mac.sh` (also inside the disk image) confirms all of this on a given Mac without changing anything.

LidTap reads a sensor Apple doesn't document, so a future macOS update could change or break it.

## Build it yourself

**On GitHub:** every push runs [Build LidTap](.github/workflows/build.yml) on a `macos-15` runner: it compiles
with `swiftc`, runs the side-effect-free test suites (`ml`, `detector`, `logic`, `ui`), verifies the signature
and that no network symbols are linked, packages `LidTap.dmg` and uploads it as a workflow artifact. Pushing a
tag that starts with `v` also publishes a GitHub Release with the DMG and its SHA-256.

**On a Mac** with the Xcode Command Line Tools (Xcode 15.3 or later; Xcode 26 adds the Liquid Glass look on macOS 26):

```bash
LidTapApp/scripts/build.sh --no-install
```

```bash
LidTapApp/scripts/test.sh
```

```bash
LidTapApp/scripts/make-dmg.sh
```

Without `--no-install`, `build.sh` also quits any running LidTap and installs the app to `~/Applications`.
The `hardware`, `actions`, `guard` and `e2e` test suites drive the real system (switch Spaces, mute the mic,
cover the screen, launch apps, open a browser tab), so run them only on a Mac you are not using at the time.

## What this fork changes

Compared with [upstream](https://github.com/harsha20599/lidtap) at commit `158d3ab` (its history is included):

- `.github/workflows/build.yml`: builds, tests, packages and releases from source on GitHub's macOS runners.
- `LidTapApp/scripts/make-dmg.sh`: drag-to-install disk image with a read-me, the license and the Mac check.
- `tools/check_mac.sh`: read-only check for Apple Silicon, macOS 14+, and the accelerometer, gyroscope and
  lid-angle sensor, using the same IOKit matching as the app.
- `LidTapApp/Sources/LidTap/UI/Design.swift`: the Liquid Glass call is wrapped in `#if compiler(>=6.2)` so the
  app also compiles with Xcode 15 and 16 (older SDKs have no `glassEffect`). Behaviour on macOS 26 is unchanged.
- The required credit to the original author in this README, in **Settings › General › About**, and in the
  app's copyright string.
- [AUDIT.md](AUDIT.md): a plain-language audit of what the app reads, what it can do, which permissions it
  needs and why, and confirmation that nothing in it talks to the network.

The detection, recognition and action code is otherwise upstream's. The Python prototype (`lidtap/`,
`PROTOTYPE.md`), the research notes and the report are kept as they were.

## License

Free to use, change, tinker with and share under the [LidTap License](LICENSE): MIT, plus two rules.

1. **If you share anything built on LidTap publicly** (an app, a fork, a video or post showing your work),
   **credit "Based on LidTap by Yemcube"** with a link to Instagram
   [@yem.cube](https://www.instagram.com/yem.cube). Private use needs no credit.
2. **Commercial use needs approval first.** Selling it, putting it in a paid product or service, or using it
   in a company's products or advertising: message [@yem.cube](https://www.instagram.com/yem.cube) on Instagram.

This fork is public, so it carries the credit. It is for private use only.

---

# For developers

| Folder | What's in it |
|---|---|
| [`LidTapApp/`](LidTapApp) | The macOS menu bar app (Swift, SwiftUI) and its tests. Start with its [README](LidTapApp/README.md) |
| [`lidtap/`](lidtap), [`PROTOTYPE.md`](PROTOTYPE.md) | The original Python prototype: a browser GUI with live sensor traces, calibration and model comparison |
| [`LidTap.md`](LidTap.md) | How the detection and recognition work, end to end |
| [`reports/`](reports), [`research_notes/`](research_notes) | The research behind the approach: sensor access, prior art, signal processing and ML |
| [`tools/imu_probe.py`](tools/imu_probe.py), [`tools/check_mac.sh`](tools/check_mac.sh) | A minimal probe that reads the motion and lid-angle sensors; the read-only hardware check |
| [`AUDIT.md`](AUDIT.md) | What the app reads, what it can trigger, what it asks for, and what it never does |

**How it works, briefly:** the app reads the accelerometer and gyroscope through IOKit HID
(`AppleSPUHIDDevice`, ~800 Hz), high-pass filters the gyro, and triggers on an adaptive threshold.
Each tap becomes a 200 ms window and 70 features (shape, timing, axis ratios and a resampled template),
classified by a k-nearest-neighbours, logistic-regression or nearest-centroid model, whichever
cross-validates best on your own data. Taps far from anything it has learned, or below its confidence
floor, are rejected. Credit for the sensor work goes to [yamete](https://github.com/chipcolate/yamete),
[apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) and
[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor); see `reports/` for the full list.
