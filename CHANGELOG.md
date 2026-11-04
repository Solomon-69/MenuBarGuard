# Changelog

## 1.1.4
- New switch in Settings, Auto-quit: Show Guard in the menu bar. Turn it off and Guard keeps working with no icon, so it takes no menu bar space. Opening the app again from Applications brings Settings back.

## 1.1.3
- Reacts faster when the menu bar fills up (checks every 2 seconds, acts within about 1 second of a change).
- Closed apps no longer come back for 2 minutes after one was closed, and need more spare room to return, so icons stop flipping in and out past the notch.

## 1.1.2
- Opening and closing no longer bounce: the icon does not spring on click and the panel opens with a smooth, non-bouncing motion.
- Guard's own icon now counts as menu bar space, so the free-space figure and the full/almost-full check include it (before, the macOS arrow could appear because of it).

## 1.1.1
- Fixes Guard doing nothing after an update: macOS drops the Accessibility switch when the app is re-signed. Allow now clears the old entry, asks again and opens the right Settings page. Guard also asks once at launch when it is missing.

## 1.0.0
First release: overflow detection through Accessibility, priority list with drag reorder and padlock,
opt-in Auto-quit, restart and auto-restore, log, welcome screens.

## 1.0.1
New app icon (deep teal shield, with a dark version).

## 1.1.0
Optional extras inspired by the behaviour of Ice (written from scratch, no Ice code). **All of them are off by
default**: out of the box 1.1 adds only the one shield icon, exactly like 1.0. Switch each on in the new Settings window.
- New Settings window with a sidebar: General, Menu Bar Layout, Menu Bar Look, Hotkeys, Auto-quit, About.
  The panel keeps working as before and has a Settings button.
- Hidden section (left of ‹) and always-hidden section (left of «). Click the shield to show them,
  Option-click for the always-hidden ones; right-click opens the panel.
- Ice Bar: hidden icons in a small bar under the menu bar and notch; click one to open its menu.
- Show hidden icons by clicking or hovering empty menu bar space, or by scrolling/swiping on the menu bar.
  Hides again after a delay or when you switch apps.
- Search every menu bar icon; Enter opens it.
- Drag icons between sections in Settings (no Command key needed), plus "Put dividers in place".
- Menu bar look: solid or gradient tint, shadow, border, full/rounded/split shape, optional on full-screen spaces.
- Icon spacing (tighter or wider), with an option to relaunch menu bar apps.
- Hotkeys for each section, search, the Ice Bar, the divider icons and the panel.
- Auto-quit now hides first and only quits low-priority apps if the bar is still full.
- Optional Screen Recording permission for real icon pictures (otherwise app icon and name).
- Welcome screens: new pages for Screen Recording and hiding.
