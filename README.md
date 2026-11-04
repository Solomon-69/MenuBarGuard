# Menu Bar Guard

<p align="center"><img src="assets/icon-light-1024.png" width="128"></p>

Free Mac app for MacBooks with a notch. When you have so many menu bar icons that some hide
behind the notch (the little double arrow), Menu Bar Guard politely quits the lowest-priority
apps **you allow**, and brings them back when there is room again.

- **Priority list.** Drag apps into order. Top = keep longest. Lock an app (padlock) to never touch it.
- **Opt-in.** Nothing is ever closed unless you switch on *Auto-quit* for that app.
- **Polite.** Uses a normal "quit" request, never force-quit. Apple's own icons (Wi-Fi, battery, clock) are never touched.
- **Gets them back.** Apps it closed are listed in the panel with a Restart button, and restart on their own when space frees up.
- **Log.** Every action is written in the Log tab.

## Extras in 1.1 (all off until you switch them on)

Open **Settings** (button in the panel). Everything new is off by default, so 1.1 adds only the shield icon.

- **Hide icons.** Icons left of the ‹ divider stay hidden until you click the shield; icons left of « only show with Option-click or a hotkey. Right-click the shield for the panel.
- **Ice Bar.** Shows hidden icons in a bar under the notch. Click one to open its menu.
- **Triggers.** Show hidden icons by clicking or hovering empty menu bar space, or by scrolling on it. Hides again after a delay or when you switch apps.
- **Search.** Type to find any menu bar icon, Enter opens it.
- **Layout.** Drag icons between Visible, Hidden and Always hidden. Menu Bar Guard does the Command-drag for you.
- **Look.** Tint (solid or gradient), shadow, border, rounded or split shape.
- **Spacing.** Tighter or wider gaps between icons (apps must relaunch).
- **Hotkeys.** For each section, search, the Ice Bar, the dividers and the panel.
- **Hide first, quit last.** When hiding is on and the bar is still full, Auto-quit steps in.

Pictures of icons need Screen Recording (optional). Without it you see each app's icon and name.
On macOS 26 and later, a status item wider than the free space is dropped by macOS, so the divider is sized
to reach exactly to the notch instead of using a huge width.

## How it knows

It asks each app where its menu bar icons are (macOS Accessibility). It compares the left-most icon
with the right edge of the notch. Hidden icons, or less than 40 pt of free space (adjustable), count as "full".
Menu Bar Guard needs **Accessibility** permission for this. It only reads icon positions; nothing is recorded or sent.

## Install

Download `MenuBarGuard.dmg` from the latest release, drag to Applications, open, follow the five welcome screens.

## Build

```bash
./build.sh            # builds build/MenuBarGuard.app (Command Line Tools only)
swiftc -swift-version 5 Planner.swift tests/logic_test.swift -o /tmp/t   # rename logic_test.swift to main.swift first
swiftc Planner.swift SectionLogic.swift main.swift -o /tmp/st             # main.swift = copy of tests/section_test.swift
```

Requires macOS 14+, Apple silicon. MIT licence.
