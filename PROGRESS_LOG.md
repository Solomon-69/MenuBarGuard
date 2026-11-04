# Menu Bar Guard 1.1: Ice features, progress log

Goal: every feature of Ice (github.com/jordanbaird/Ice, GPL-3.0) rebuilt from scratch in Menu Bar Guard (MIT).
Ice's README was read for the feature list only. No Ice code was looked at or copied.

## 4 Nov 2026

### Research (what macOS 27 allows)
- Menu bar icons are no longer windows (CGWindowList shows none), so icon pictures can only come from a
  capture of the screen while the icon is visible (ScreenCaptureKit `SCScreenshotManager.captureImage(in:)`).
- Each app's icons are readable and pressable through Accessibility (`AXExtrasMenuBar` children, `AXPress`).
  Apple's own icons (owned by MenuBarAgent) are anonymous groups with no press action: shown as
  "Apple: system icon N", opened with a plain click instead.
- macOS has its own overflow chevron (`menu-bar-overflow-indicator`); it is skipped.
- Ice's classic trick (a 10 000 pt wide divider) does NOT work here: macOS 26+ drops any status item that is
  wider than the free space, and everything snaps back. Measured instead: the divider grows exactly to the
  notch's right edge, which pushes every icon left of it out of sight (proved with 200 pt and 480 pt tests).
- Status item order: preferred-position numbers are shared with Apple's Control Center items and are not
  reliable for first placement. So the app checks the order itself; if the shield is left of the divider it
  never collapses (it would hide the shield) and offers "Fix it" / "Put dividers in place", which does three
  quick Command-drags.

### Built
- Sections.swift: hidden + always-hidden dividers, measured collapse, refit when icons change, order check.
- Triggers.swift: show on hover / click on empty space / scroll or swipe, rehide on app switch, timed rehide.
- IceBar.swift: bar under the menu bar with real pictures (or app icon + name); click opens the icon's menu.
- SearchPanel.swift: type to find any icon, arrows + Enter, Esc closes. Non-activating panel.
- Mover.swift: Command-drag moves for the Layout page and the arrange button; fallback click.
- Look.swift: tint (solid/gradient), shadow, border, full/rounded/split, optional on full-screen spaces.
- SpacingApply.swift: icon spacing (NSStatusItemSpacing / SelectionPadding), relaunch of unlocked apps.
- Hotkeys.swift: Carbon hotkeys for each section, search, Ice Bar, dividers, panel; recorder UI.
- SettingsWindow.swift + SettingsPanes.swift: sidebar Settings (General, Layout, Look, Hotkeys, Auto-quit, About).
- Engine: hide first, quit second (collapses open sections before any auto-quit; hidden icons never count).
- Intro: 5 pages (new: Screen Recording, hiding).

### Tests (all invisible: test hook, off-screen render, off-screen real window, silent screencapture)
- tests/section_test.swift: 30 checks, ALL PASS. tests/logic_test.swift: still passes.
- Settings window, real NSWindow placed off screen: light + dark screenshots.
- Ice Bar with real icon pictures (Screen Recording on) and without.
- Hotkeys: both test shortcuts registered with status 0 (noErr); hotkey action dispatch toggles prefs.

### Change request from Solomon (15:15): every new feature OFF by default
- Defaults now: hiding off, always-hidden off, Ice Bar off, click/hover/scroll triggers off, look off,
  spacing default, hotkeys off ("Use hotkeys" switch), search off ("Search menu bar icons" switch).
- Divider icons are not even created until hiding is switched on (removed again when switched off).
- The shield is created exactly like 1.0 (no saved position tricks).
- Cleaned his Mac: removed all test settings and saved divider positions; icon spacing keys confirmed absent
  (system default); look never left on. Proof: shots/defaults-off-bar.png shows only the shield added.
- Live tests that need real clicks run only after 2 minutes of no input, and switch everything off again,
  put the shield back where it was, and relaunch the normal app with open -g.
