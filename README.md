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

- [What it actually does](#what-it-actually-does)
- [Download and install](#download-and-install)
- [Permissions, and why](#permissions-and-why)
- [Calibrate](#calibrate)
- [Practice mode, then turn actions on](#practice-mode-then-turn-actions-on)
- [Zones and actions](#zones-and-actions)
- [Why did my tap do nothing?](#why-did-my-tap-do-nothing)
- [Fix a zone that misreads](#fix-a-zone-that-misreads)
- [Turn it off, remove it](#turn-it-off-remove-it)
- [Which Macs work](#which-macs-work)
- [Build it yourself](#build-it-yourself)
- [What this fork changes](#what-this-fork-changes)
- [License](#license)

## What it actually does

LidTap is a menu bar app that waits for you to tap the lid of your MacBook. Not the trackpad, not the
keyboard: the screen itself, or its bezel. It splits the screen into a grid of zones, two by two to start,
and when you tap inside a zone it does the one thing you assigned to that zone, such as switching to the
next desktop or pausing your music.

It can do this because every Apple Silicon MacBook since the M2 has a motion sensor in its base. A tap on
the lid twists the whole laptop about the hinge by a tiny amount, and the sensor feels that twist about
800 times a second. A tap on the top-left of the screen twists the machine differently from a tap on the
bottom-right, so after you show it fifteen examples per zone, a small model on your Mac can tell them apart.
It also records twenty seconds of you typing, clicking and knocking the desk, so it knows what *not* to react
to. Everything stays on the Mac. There is no touchscreen involved, no camera, no network.

What it is good at: a few physical shortcuts you can hit without looking, especially when your hands are
away from the keyboard. What it is not: a touchscreen. It cannot track a finger, drag, or feel a held press,
and it is coarse, a handful of zones rather than pixels. Expect roughly nineteen out of twenty taps to land
in the right zone on a 2×2 grid; the rest are ignored rather than guessed, and the menu bar panel tells you
why.

## Download and install

1. Download **LidTap.dmg** from the [latest release](https://github.com/farhanhaque0619/lid/releases/latest).
   It is built from this repository's source by the [Build LidTap](.github/workflows/build.yml) workflow on a
   macOS runner. The release notes show the SHA-256 of the file.
   If no release has been published yet, the same `LidTap.dmg` is attached to every green run of the
   workflow: open [Actions](https://github.com/farhanhaque0619/lid/actions/workflows/build.yml), pick the
   latest run, and download the **LidTap-dmg** artifact (a zip holding `LidTap.dmg` and `SHA256SUMS.txt`;
   GitHub asks you to be signed in). Publishing a release is one step: **Releases › Draft a new release**,
   create the tag `v1.1.0` on this branch and publish; the workflow then builds from that tag and attaches
   the DMG to the release.
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
| **Accessibility** | The first time a zone action runs, or **Settings › Permissions › Allow…** | Posting the keystrokes the actions need: ⌃← and ⌃→ for Spaces, the media and volume keys, ⌘N in Notes, ⌃⌘Q for Lock Screen, any Keyboard Shortcut you record, and the camera shortcut in Zoom, Teams, Webex or Meet for Privacy Guard | Those zones do nothing and the app tells you. Privacy Guard still blurs and mutes; Open App, Open Link, Run Apple Shortcut and Mute Microphone work without it |
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

1. Click the hand icon in the menu bar, then **Calibrate**. The display goes dark and shows a short panel
   with the tips below. Taps don't count until you click **Start**.
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

## Practice mode, then turn actions on

After a fresh install LidTap starts in **practice mode**: every tap you make after calibrating shows a
ripple in the zone it hit and the name of the action that *would* run, and nothing runs. Use it for a minute
to see what LidTap sees. When the readings look right, click **Turn On Actions** in the menu bar panel, on the
calibration summary, or in the Welcome pane. You can switch practice mode back on any time in
**Settings › General**, for example after moving to a different desk.

The **Welcome** pane in Settings (opened automatically on first run, and from **Settings › General › Show
Welcome** later) is a four-step checklist with live status: sensor streaming, Accessibility granted,
calibrated, actions on. It also explains good taps, what each outcome means, and what to try when something
is off.

## Zones and actions

The default 2×2 layout is already what this build is meant for:

| Zone | Where | Action |
|---|---|---|
| 1 | Top left | **Desktop Left**: switch to the Space on the left |
| 2 | Top right | **Desktop Right**: switch to the Space on the right |
| 3 | Bottom left | **Play / Pause**: Music, Spotify, YouTube, whatever is playing |
| 4 | Bottom right | **Privacy Guard**: mute every microphone, hide every screen, and turn the meeting camera off |

To change a zone: **Settings › Zones**, click the zone on the drawn display, pick an action. A sentence under
the picker says what it does, **Try It** runs it right away so you can check, and the zone tells you if
anything is still missing (an app, a key combination, a name, a link). Right-clicking a zone in the menu bar
panel offers the same list.

| Group | Action | What it does | Needs |
|---|---|---|---|
| Desktop | **Desktop Left / Right** | Switch to the Space on the left or right | Accessibility |
| Desktop | **Mission Control** | Show every open window and desktop | nothing |
| Media | **Play / Pause, Next Track, Previous Track** | Control whatever is playing | Accessibility |
| Media | **Volume Up / Down, Mute Sound** | One volume step, or mute the speakers | Accessibility |
| Apps | **New Note** | Open Notes with a fresh note | Accessibility |
| Apps | **Open App** | Launch an app, or bring it to the front if it is already open | pick the app |
| Apps | **Open Link** | Open a web address, or a link such as `shortcuts://` or `raycast://`, in its app | type the link |
| Custom | **Keyboard Shortcut** | Press a combination you record, exactly as if you typed it: ⇧⌘4 for a screenshot, ⌘Space for Spotlight, the shortcut you gave any app | Accessibility, record the keys |
| Custom | **Run Apple Shortcut** | Run one of your Apple Shortcuts by name, in the background. Anything a Shortcut can do, a tap can do: toggle a Focus, start a timer, run a script | type the name |
| System | **Mute Microphone** | Mute every microphone, or unmute if muted | nothing |
| System | **Lock Screen** | Lock the Mac right away | Accessibility |
| Privacy | **Privacy Guard** | Mute every mic, turn the meeting camera off, hide every screen | nothing; Accessibility for the camera step |

Combinations macOS reserves for itself, such as ⌘Tab, can't be recorded as a Keyboard Shortcut; put them in a
Shortcut instead. **Open Link** hands the address to your default browser or the app that owns the link; LidTap
itself still never connects to anything.

**Tap twice to run.** Any zone can be set to ask for a second tap: the first tap shows what would run, and a
second tap in the same zone within three seconds runs it. Turn it on per zone in **Settings › Zones** for
anything you'd rather not trigger by accident, such as Lock Screen or a Shortcut that sends a message.

**Privacy Guard** needs to be at least 85% sure of the zone before it fires. Tap the zone again, or click
anywhere, to come back: the screens return, the microphones are restored exactly as they were, and the camera
is turned back on in the meeting app. In **Settings › Zones** (with the Guard zone selected) you can turn
off **"Turn the camera off in meetings"**. Consider starting that way: the camera step sends the meeting app's
standard shortcut, and if you have remapped shortcuts in Zoom, Teams or Meet, it could trigger something else.

## Why did my tap do nothing?

Open the menu bar panel. Under the drawn display it shows the last tap, what happened to it, and a tip:

- **Ignored** means LidTap chose not to count it: a keystroke within a third of a second, a trackpad click,
  a moving pointer, a scroll, the lid moving, or the screen still wobbling from the last tap. Each has its
  own tip, usually "hands off the trackpad" or "wait half a second".
- **Too soft** means the flick was below the minimum strength. A little crisper is enough.
- **Not sure** means the recogniser wasn't confident, or the tap was unlike anything recorded. Tap nearer the
  calibration dot, or add taps to that zone.
- **Practice** means it was recognised and nothing ran because practice mode is on.
- **Tap again** means that zone asks for a second tap.

**Settings › Detection** shows the same tip under the live motion trace, where you can watch your taps cross
the trigger line.

## Fix a zone that misreads

- **Check which zone is weak:** **Settings › Training** shows reliability per zone and a table of where
  taps went. Below 85% is flagged, below 75% is red.
- **Top it up:** **Calibrate Again…** in the menu bar panel (or **Calibrate…** in Training) only asks for taps in
  zones that have fewer than fifteen usable ones; if all are full, it adds five to each.
- **Redo one zone from scratch:** in **Training › Recorded taps**, click the trash icon next to that zone, then
  **Calibrate Again…**. Only that zone is asked for.
- **Taps refused as too soft, or bumps counted as taps:** **Settings › Detection** has the live motion trace and
  the sliders. Lower **Minimum tap strength** only if genuinely crisp taps are refused; raise **Minimum** if
  desk knocks register. **Reset to Defaults** puts everything back.
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

Version 1.1 adds, on top of that:

- **Nine new actions**: Keyboard Shortcut (with a recorder), Run Apple Shortcut, Open Link, Mission Control,
  Mute Microphone, Volume Up, Volume Down, Mute Sound and Lock Screen. The picker is grouped and every action
  has a one-line explanation.
- **Tap twice to run**, per zone.
- **Practice mode**, on for a fresh install, so nothing runs until you have seen the readings and turned actions on.
- **A tips panel before calibration**; taps don't count until Start.
- **A Welcome pane** with a live checklist, and **Reset to Defaults** in Detection and Training.
- **A tip for every ignored or rejected tap** in the menu bar panel and the Detection pane, and reason-specific
  on-screen feedback.

The detection and recognition code is upstream's. The Python prototype (`lidtap/`,
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
