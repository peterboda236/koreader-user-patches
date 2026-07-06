# KOReader User Patches

A collection of user patches for [KOReader](https://github.com/koreader/koreader) that enhance the reading experience with richer statistics and frontlight controls.

---

## Patches

### 🌙 Frontlight Widget — Night Mode & Light Profiles

**`2-frontlight-widget-profiles.lua`**

<img width="384" height="512" alt="FileManager_2026-07-01_123610" src="https://github.com/user-attachments/assets/8fbf2b2a-a176-4c6d-b4e8-9efa6ea5845f" />


Extends the built-in frontlight widget with a **Night Mode** toggle and **5 savable light profiles**, laid out as:

- Row 1: Night Mode · Profile 1 · Profile 2
- Row 2: Profile 3 · Profile 4 · Profile 5

**Highlights:**
- **Tap** a profile button to instantly apply its saved brightness, warmth (on natural-light devices), and night-mode state.
- **Long-press** a profile button to rename and save the *current* frontlight settings into that slot.
- Profile names are editable and persist across restarts.

---

### 🌙 Frontlight Widget — Night Mode Toggle
**`2-frontlight-widget-nightmode.lua`**

<img width="384" height="512" alt="FileManager_2026-06-30_074755" src="https://github.com/user-attachments/assets/8ef06f58-e241-42ca-b4c4-a196b02f662b" />


Adds a **Night Mode** toggle button directly to the bottom of the built-in frontlight widget. Toggle inverts the screen and persists the setting — no need to dig through menus.

---

### 📑 TOC Reading Time

**`2-toc-reading-time.lua`**

<img width="384" height="512" alt="Reader_Az Elso Torveny vilaga 1  - Hidegen talalva - Abercrombie, Joe #p(878) epub_p456_2026-06-30_074806" src="https://github.com/user-attachments/assets/fca94799-7197-4f54-a3ef-e3d1ddc6a722" />

Enriches the table of contents with an estimated reading time for each chapter, displayed alongside the existing page count.

1. Chapter  (41) ........................ 8

becomes:

1. Chapter  (41 | 00:44) ........................ 8

Can Enable/Disable in Reader mode / Settings.

Falls back to the original format if the Statistics plugin has no speed data yet (e.g. at the very start of a book).

Requirements: the Statistics plugin must be active and "Show chapter length" must be enabled in the TOC settings.

---

### 📊 Reading Insights - Migrated a patch to a plugin in KOReader

Plugin can be downloaded from here: https://github.com/peterboda236/readinginsights.koplugin

---

### 📖 Reading Stats Popup - Merged into Reading insights plugin

Plugin can be downloaded from here: https://github.com/peterboda236/readinginsights.koplugin


---

## Installation

Place the `.lua` files into KOReader's `patches` folder on your device:

```
<koreader_dir>/patches/
```

Restart KOReader. Patches prefixed with `2-` are applied after the UI initializes.

---

## Credits

Inspired by and based in part on patches by [@quanganhdo](https://github.com/quanganhdo/koreader-user-patches).
