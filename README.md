# 🔋 BatteryGuard

A tiny macOS menu bar app that **won't let you ignore a low battery**.

When your Mac drops to **20%** while unplugged, BatteryGuard puts a big alert in the middle of your screen. It has **no close button**. The only way to make it go away is to plug in your charger, and then it disappears on its own.

> I made this for myself because I kept ignoring the tiny macOS low-battery notification and my Mac kept dying. It's open source, so do whatever you want with it.

---

## ✨ Features

- **Can't be dismissed.** The alert stays on top of every app, every desktop (Space) and fullscreen windows until you plug in.
- **Closes on its own.** Connect the charger and it fades out with a soft chime.
- **Lets you keep working.** The screen dims, but clicks still go through to the apps behind it, so you can save your work.
- **Two warning levels:**
  - **20%:** orange alert
  - **10%:** red "Critically Low" alert with a stronger sound
- **Repeats the sound** at every further 5% drop, so you notice it.
- **Live battery % in the menu bar**, which turns red when low.
- **Starts at login** automatically. You can toggle this from the menu.
- **Very light:**
  - ~270 KB app (~84 KB DMG)
  - No Dock icon
  - No dependencies
  - Waits for macOS power events instead of constantly checking the battery
- **Universal:** runs on Apple Silicon and Intel Macs, macOS 13 Ventura or newer.

## 📦 Install

1. Download `BatteryGuard.dmg` from the [Releases](../../releases) page.
2. Open it and drag **BatteryGuard** into **Applications**.
3. Launch it from Applications.

### "BatteryGuard can't be opened" warning

The app isn't signed with a paid Apple Developer account, so macOS blocks it the first time. Do **one** of these:

- **Right-click** the app → **Open** → **Open**
- Or go to **System Settings → Privacy & Security** → click **Open Anyway**
- Or run this in Terminal:
  ```bash
  xattr -dr com.apple.quarantine /Applications/BatteryGuard.app
  ```

You only need to do this once.

## 🖱️ Usage

BatteryGuard lives in your menu bar and shows your battery icon and %. Click it to see:

| Menu item | What it does |
|---|---|
| `87% — On battery` | Current battery status |
| **Preview Alert** | Shows the alert so you can see what it looks like (this preview has a close button) |
| **Launch at Login** | Turns auto-start on or off |
| **Quit BatteryGuard** | Stops the app |

## 🛠️ Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). Full Xcode isn't required.

```bash
git clone <this-repo>
cd batterynotifier

./build.sh            # build to build/BatteryGuard.app
./build.sh install    # build, copy to /Applications and launch
./build.sh dmg        # build and package build/BatteryGuard.dmg
```

### Change the battery levels

Edit the top of `Sources/main.swift`:

```swift
let lowThreshold = 20          // show alert at or below this %
let criticalThreshold = 10     // alert turns red + extra sound
```

Then run `./build.sh install`.

**Tip:** to test it, set `lowThreshold` just above your current battery %, unplug, and watch the alert appear. Plug in and it should vanish.

## ⚙️ How it works

- Uses IOKit's `IOPSNotificationCreateRunLoopSource` to get notified by macOS whenever the power source or battery level changes.
- A 60-second backup check and a wake-from-sleep check make sure nothing is missed.
- The alert is a borderless panel at screen-saver window level, set to join all Spaces and appear over fullscreen apps.
- Launch at login uses a LaunchAgent at `~/Library/LaunchAgents/com.local.batteryguard.plist`.

The whole app is one Swift file: [`Sources/main.swift`](Sources/main.swift).

## 🗑️ Uninstall

1. Click the menu bar icon → **Quit BatteryGuard**.
2. Delete `/Applications/BatteryGuard.app`.
3. Delete `~/Library/LaunchAgents/com.local.batteryguard.plist`.

## 📄 License

Released into the **public domain** under [The Unlicense](LICENSE).

Use it, copy it, change it, sell it, ship it in your own app. No credit needed and no strings attached. It's provided as-is, with no warranty.
